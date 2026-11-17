import 'dart:async';
import 'dart:convert';

import '../lists/list_catalog.dart';
import '../lists/list_definition.dart';
import '../lists/list_error.dart';
import '../lists/list_item.dart';
import '../lists/list_patch.dart';
import '../lists/list_rules.dart';
import '../lists/list_store.dart';

// The demo's lists (T-18, Q-135): a ListStore that keeps every list and item
// in memory only, so a page reload starts again from the samples. It runs
// the shared contract tests (test/lists/list_store_contract_test.dart).
//
// One device and no server: every write lands at once and in one step, so
// the read side always shows whole changes, a patch always reads the current
// data, and nothing is refused for want of a connection. Stored copies are
// made through JSON, as Firestore would store them, so a caller's objects
// never change the store's data.
class MemoryListStore implements ListStore {
  MemoryListStore({
    List<ListDefinition> lists = const [],
    List<ListItem> items = const [],
  }) {
    for (final ListDefinition definition in lists) {
      _putDefinition(definition);
    }
    for (final ListItem item in items) {
      if (_definitions.containsKey(item.listId)) {
        _items[item.listId]![item.id] = _copyItem(item);
      }
    }
    _catalog = _build();
  }

  final Map<String, ListDefinition> _definitions = {};
  final Map<String, Map<String, ListItem>> _items = {};
  // Launcher order: each list's place, by when it was first created. A
  // deleted list keeps its place, so Undo brings it back where it was.
  final Map<String, int> _places = {};
  int _nextPlace = 0;

  final StreamController<ListCatalog> _changes =
      StreamController<ListCatalog>.broadcast();
  late ListCatalog _catalog;

  Future<void> close() async {
    if (!_changes.isClosed) {
      await _changes.close();
    }
  }

  @override
  ListCatalog get current => _catalog;

  @override
  Stream<ListCatalog> watch() {
    late final StreamController<ListCatalog> controller;
    StreamSubscription<ListCatalog>? subscription;
    controller = StreamController<ListCatalog>(
      onListen: () {
        controller.add(_catalog);
        subscription = _changes.stream.listen(
          controller.add,
          onDone: controller.close,
        );
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  ListCatalog _build() {
    final List<String> ids = _definitions.keys.toList()
      ..sort((a, b) => _places[a]!.compareTo(_places[b]!));
    return ListCatalog(
      definitions: [for (final String id in ids) _definitions[id]!],
      items: [for (final String id in ids) ..._items[id]!.values],
    );
  }

  void _emit() {
    _catalog = _build();
    if (!_changes.isClosed) {
      _changes.add(_catalog);
    }
  }

  static Object? _json(Object? value) => jsonDecode(jsonEncode(value));

  static ListItem _copyItem(ListItem item) =>
      ListItem.fromJson(_json(item.toJson()));

  static ListDefinition _copyDefinition(ListDefinition definition) =>
      ListDefinition.fromJson(_json(definition.toJson()));

  void _putDefinition(ListDefinition definition) {
    _definitions[definition.id] = _copyDefinition(definition);
    _items.putIfAbsent(definition.id, () => {});
    _places.putIfAbsent(definition.id, () => _nextPlace++);
  }

  void _putItem(ListItem item) {
    _items[item.listId]?[item.id] = _copyItem(item);
  }

  // [item] fitted to its list's current fields, as the Firestore store fits
  // each write.
  ListItem _fitted(ListItem item) {
    final ListDefinition? definition = _definitions[item.listId];
    if (definition == null) {
      return item;
    }
    return ListPatch.fitItem(definition, item) ?? item;
  }

  String? _listOfItem(String itemId) {
    for (final MapEntry<String, Map<String, ListItem>> entry
        in _items.entries) {
      if (entry.value.containsKey(itemId)) {
        return entry.key;
      }
    }
    return null;
  }

  @override
  Future<void> apply(ListChanges changes) async {
    for (final ListItem item in changes.saved) {
      if (!_definitions.containsKey(item.listId)) {
        continue;
      }
      // An item that moved to another list leaves its old one.
      final String? from = _listOfItem(item.id);
      if (from != null && from != item.listId) {
        _items[from]!.remove(item.id);
      }
      _putItem(_fitted(item));
    }
    for (final String itemId in changes.deletedIds) {
      final String? listId = _listOfItem(itemId);
      if (listId != null) {
        _items[listId]!.remove(itemId);
      }
    }
    _emit();
  }

  Future<void> _changeOptions(
    String listId,
    String fieldKey,
    List<FieldOption> Function(List<FieldOption> options) change,
  ) async {
    final ListDefinition? definition = _definitions[listId];
    if (definition?.field(fieldKey) == null) {
      return;
    }
    await patchList(listId, [
      ListPatchOp(PatchOpKind.setOptions, {
        'key': fieldKey,
        'options': change(
          definition!.field(fieldKey)!.options,
        ).map((option) => option.toJson()).toList(),
      }),
    ]);
  }

  @override
  Future<void> addOption(String listId, String fieldKey, String value) {
    return _changeOptions(
      listId,
      fieldKey,
      (options) => options.any((option) => option.value == value)
          ? options
          : [...options, FieldOption(value: value, label: value)],
    );
  }

  @override
  Future<void> removeOption(String listId, String fieldKey, String value) {
    return _changeOptions(
      listId,
      fieldKey,
      (options) => options.where((option) => option.value != value).toList(),
    );
  }

  @override
  Future<void> refresh() async {}

  @override
  Future<List<ListError>> createList(
    ListDefinition definition, {
    List<ListItem> items = const [],
  }) async {
    if (_definitions.containsKey(definition.id)) {
      return [
        ListError(ListErrorCode.listExists, {'list': definition.id}),
      ];
    }
    // Item ids are unique across every list, since item deletes go by id.
    final Set<String> newIds = {};
    final List<ListError> errors = [
      ...definition.validate(),
      for (final ListItem item in items)
        if (!newIds.add(item.id))
          ListError(ListErrorCode.duplicateItemId, const {}, item.id)
        else if (_listOfItem(item.id) != null)
          ListError(ListErrorCode.itemIdTaken, const {}, item.id),
      for (final ListItem item in items)
        if (item.listId != definition.id)
          ListError(ListErrorCode.itemInOtherList, {
            'list': item.listId,
          }, item.id)
        else
          for (final ListError error in item.validateAgainst(definition))
            error.forItem(item.id),
    ];
    if (errors.isEmpty) {
      _putDefinition(definition);
      items.forEach(_putItem);
      _emit();
    }
    return errors;
  }

  @override
  Future<ListPatchResult?> patchList(String listId, List<ListPatchOp> ops) {
    return _patch(listId, ops);
  }

  Future<ListPatchResult?> _patch(
    String listId,
    List<ListPatchOp> ops, {
    ListPatchResult? Function(ListDefinition definition)? refuse,
  }) async {
    final ListDefinition? definition = _definitions[listId];
    if (definition == null) {
      return null;
    }
    final ListPatchResult? refused = refuse?.call(definition);
    if (refused != null) {
      return refused;
    }
    final ListPatchResult result = ListPatch.apply(
      definition,
      _items[listId]!.values.toList(),
      ops,
      DateTime.now().toUtc(),
    );
    if (result.isValid) {
      _putDefinition(result.definition);
      for (final ListItem item in result.items) {
        if (result.changedItemIds.contains(item.id)) {
          _putItem(item);
        }
      }
      _emit();
    }
    return result;
  }

  @override
  Future<ListPatchResult?> patchListAi(
    String listId,
    List<ListPatchOp> ops, {
    required ListDefinition previewed,
  }) {
    ListPatchResult refused(ListDefinition definition, ListErrorCode code) {
      return ListPatchResult(
        definition: definition,
        items: const [],
        changedItemIds: const {},
        hiddenValues: 0,
        errors: [
          ListError(code, {'list': listId}),
        ],
        definitionBefore: definition,
        itemsBefore: const [],
      );
    }

    return _patch(
      listId,
      ops,
      refuse: (definition) => !definition.aiAllowed
          ? refused(definition, ListErrorCode.aiNotAllowed)
          : AiItemWrite.sameFields(definition, previewed)
          ? null
          : refused(definition, ListErrorCode.previewChanged),
    );
  }

  @override
  Future<AiWriteResult> applyAiItems(AiItemWrite write) async {
    final String listId = write.listId;
    if (write.writes > ListStore.maxAiWrites) {
      return AiWriteResult.refused(ListErrorCode.answerTooLarge, listId);
    }
    final Map<String, ListItem> stored = _items[listId] ?? const {};
    final AiWriteResult result = write.over(_definitions[listId], {
      for (final String id in write.touchedIds)
        if (stored[id] != null) id: stored[id]!,
    });
    if (result.isValid) {
      result.saved.forEach(_putItem);
      for (final String id in result.deletedIds) {
        _items[listId]!.remove(id);
      }
      _emit();
    }
    return result;
  }

  @override
  Future<List<ListError>> deleteCreatedList(CreatedList created) async {
    final String listId = created.listId;
    if (!created.isCurrent(
      _definitions[listId],
      _items[listId]?.values ?? const [],
    )) {
      return [
        ListError(ListErrorCode.listChanged, {'list': listId}),
      ];
    }
    _definitions.remove(listId);
    _items.remove(listId);
    _emit();
    return const [];
  }

  @override
  Future<DeletedList?> deleteList(String listId) async {
    final ListDefinition? definition = _definitions.remove(listId);
    if (definition == null) {
      return null;
    }
    final List<ListItem> items = _items.remove(listId)!.values.toList();
    _emit();
    return DeletedList(definition: definition, items: items);
  }

  @override
  Future<void> restoreList(DeletedList deleted) async {
    _putDefinition(deleted.definition);
    deleted.items.forEach(_putItem);
    _emit();
  }

  @override
  Future<bool?> undoClear(
    String listId, {
    required List<ListItem> cleared,
    required List<ListItem> created,
  }) async {
    final Map<String, ListItem>? items = _items[listId];
    if (!_definitions.containsKey(listId) || items == null) {
      return false;
    }
    if (cleared.any((item) => items.containsKey(item.id))) {
      return false;
    }
    for (final ListItem item in created) {
      final ListItem? stored = _items[item.listId]?[item.id];
      if (stored == null ||
          !ListSnapshot.sameJson(stored.values, _json(item.values))) {
        return false;
      }
    }
    for (final ListItem item in cleared) {
      _putItem(_fitted(item));
    }
    for (final ListItem item in created) {
      _items[item.listId]?.remove(item.id);
    }
    _emit();
    return true;
  }

  @override
  Future<List<ListError>> restoreSnapshot(ListSnapshot snapshot) async {
    final String listId = snapshot.listId;
    final ListDefinition? current = _definitions[listId];
    final Map<String, ListItem> stored = _items[listId] ?? const {};
    final Map<String, ListItem> touched = {
      for (final String id in snapshot.itemIds)
        if (stored[id] != null) id: stored[id]!,
    };
    if (current == null || !snapshot.isCurrent(current, touched)) {
      return [
        ListError(ListErrorCode.listChanged, {'list': listId}),
      ];
    }
    final ListDefinition? definition = snapshot.restoredDefinition(
      current,
      DateTime.now().toUtc(),
    );
    if (definition != null) {
      _putDefinition(definition);
    }
    for (final String id in snapshot.itemIds) {
      final ListItem? item = snapshot.itemsBefore[id];
      if (item == null) {
        _items[listId]!.remove(id);
      } else {
        _putItem(item);
      }
    }
    _emit();
    return const [];
  }
}
