import 'list_catalog.dart';
import 'list_definition.dart';
import 'list_error.dart';
import 'list_item.dart';
import 'list_patch.dart';
import 'list_rules.dart';
import 'list_vocabulary.dart';

// Reads the arguments of the AI's list tools (T-19; schemas in
// schema/ai_tools.schema.json) into what the editor and the screens use:
// ListPatchOps, ListChanges and ListDefinitions. Nothing here throws on
// malformed input: a wrong type, an unknown key, a missing argument or an
// id that is not there comes back as a ListError (Q-14 A), so the device
// can send the errors back for one self-correction round (Q-34 A).
//
// The AI format differs from the stored JSON in one way: a map with free
// keys (an item's values, copyOnClear's `where` and `setField`) is a list
// of {field, value} entries, since strict tool schemas need every object's
// keys to be known. ListInput turns the entries back into maps.

// The JSON type of one argument.
enum ArgType implements WireName {
  string('string'),
  boolean('boolean'),
  integer('integer'),
  number('number'),
  object('object'),
  list('list'),
  // Any JSON value, null included.
  any('any');

  const ArgType(this.wire);

  @override
  final String wire;

  bool accepts(Object? value) {
    switch (this) {
      case ArgType.string:
        return value is String;
      case ArgType.boolean:
        return value is bool;
      case ArgType.integer:
        return value is int;
      case ArgType.number:
        return value is num;
      case ArgType.object:
        return value is Map;
      case ArgType.list:
        return value is List;
      case ArgType.any:
        return true;
    }
  }
}

// The keys each JSON object of a definition may have, and the shapes of
// the objects inside it. Definitions read from storage keep unknown keys
// (ListDefinition.extra); input from the AI or an op must not have any.
enum InputShape {
  field({
    'key', 'type', 'label', 'labelKey', 'required', 'primary', 'role',
    'options', 'default', 'min', 'max', 'visibleWhen',
  }),
  option({'value', 'label', 'labelKey'}),
  visibleWhen({'field', 'in'}),
  view({
    'kind', 'sectionBy', 'groupBy', 'dateField', 'timelineGrouping',
    'filterChipsBy', 'bucketBy',
  }),
  behavior({
    'kind', 'dateField', 'recurrenceField', 'when', 'where', 'setField',
    'dedupeBy', 'field', 'from', 'to',
  }),
  // A definition as create_list sends it: id, dates and template are the
  // app's to set.
  newList({'name', 'icon', 'color', 'fields', 'view', 'behaviors'});

  const InputShape(this.keys);

  final Set<String> keys;
}

class ListInput {
  // unknownArg errors for keys of [json] (and of the objects inside it)
  // that [shape] does not have. [path] names [json] in the errors.
  static List<ListError> unknownKeys(
    Object? json,
    InputShape shape,
    String op,
    String path,
  ) {
    if (json is! Map) {
      return const [];
    }
    final List<ListError> errors = [
      for (final Object? key in json.keys)
        if (!shape.keys.contains(key)) _unknown(op, '$path.$key'),
    ];
    void each(String key, InputShape inner) {
      final Object? list = json[key];
      if (list is List) {
        for (int i = 0; i < list.length; i++) {
          errors.addAll(unknownKeys(list[i], inner, op, '$path.$key[$i]'));
        }
      }
    }

    switch (shape) {
      case InputShape.field:
        each('options', InputShape.option);
        errors.addAll(unknownKeys(json['visibleWhen'], InputShape.visibleWhen, op, '$path.visibleWhen'));
      case InputShape.newList:
        each('fields', InputShape.field);
        each('behaviors', InputShape.behavior);
        errors.addAll(unknownKeys(json['view'], InputShape.view, op, '$path.view'));
      case InputShape.option:
      case InputShape.visibleWhen:
      case InputShape.view:
      case InputShape.behavior:
        break;
    }
    return errors;
  }

  // Errors for a JSON object's arguments: unknown names, missing required
  // ones and values of the wrong type. A null value counts as missing.
  static List<ListError> checkArgs(
    Object? json,
    String op,
    Map<String, ArgType> types, {
    Set<String> required = const {},
    String path = '',
  }) {
    if (json is! Map) {
      return [_wrongType(op, path.isEmpty ? 'arguments' : path, ArgType.object)];
    }
    final String prefix = path.isEmpty ? '' : '$path.';
    return [
      for (final Object? key in json.keys)
        if (!types.containsKey(key)) _unknown(op, '$prefix$key'),
      for (final MapEntry<String, ArgType> entry in types.entries)
        if (json[entry.key] == null && entry.value != ArgType.any)
          if (required.contains(entry.key))
            ListError(ListErrorCode.missingArg, {'op': op, 'arg': '$prefix${entry.key}'})
          else if (json.containsKey(entry.key))
            _wrongType(op, '$prefix${entry.key}', entry.value)
          else ...[]
        else if (!entry.value.accepts(json[entry.key]))
          _wrongType(op, '$prefix${entry.key}', entry.value),
    ];
  }

  static ListError _unknown(String op, String arg) {
    return ListError(ListErrorCode.unknownArg, {'op': op, 'arg': arg});
  }

  static ListError _wrongType(String op, String arg, ArgType expected) {
    return ListError(
      ListErrorCode.wrongArgType,
      {'op': op, 'arg': arg, 'expected': expected.wire},
    );
  }

  static ListError _badOp(String op, FormatException error) {
    return ListError(ListErrorCode.badOp, {'op': op, 'detail': error.message});
  }

  // The list a tool call targets: one of the user's lists (Q-36).
  static (ListDefinition?, List<ListError>) _target(
    Map args,
    ListCatalog catalog,
  ) {
    final Object? listId = args['listId'];
    if (listId is! String) {
      return (null, const []);
    }
    final ListDefinition? definition = catalog.definition(listId);
    return definition == null
        ? (null, [ListError(ListErrorCode.unknownList, {'list': listId})])
        : (definition, const []);
  }

  // A {field, value} entries list as a map; errors when it is not one.
  static (Map<String, dynamic>, List<ListError>) _entries(
    Object? json,
    String op,
    String path,
  ) {
    final Map<String, dynamic> map = {};
    final List<ListError> errors = [];
    if (json is! List) {
      return (map, [_wrongType(op, path, ArgType.list)]);
    }
    for (int i = 0; i < json.length; i++) {
      final List<ListError> entryErrors = checkArgs(
        json[i],
        op,
        const {'field': ArgType.string, 'value': ArgType.any},
        required: const {'field'},
        path: '$path[$i]',
      );
      errors.addAll(entryErrors);
      if (entryErrors.isEmpty) {
        final Map entry = json[i] as Map;
        map[entry['field'] as String] = entry['value'];
      }
    }
    return (map, errors);
  }

  // A behavior in the AI format with its entries as maps.
  static (Object?, List<ListError>) _behavior(Object? json, String op, String path) {
    if (json is! Map) {
      return (json, const []);
    }
    final Map<String, dynamic> behavior = Map<String, dynamic>.from(json);
    final List<ListError> errors = [];
    for (final String key in const ['where', 'setField']) {
      if (behavior[key] != null) {
        final (Map<String, dynamic> map, List<ListError> entryErrors) =
            _entries(behavior[key], op, '$path.$key');
        behavior[key] = map;
        errors.addAll(entryErrors);
      }
    }
    return (behavior, errors);
  }

  // patch_list {listId, ops}: the ops for the list, which must be the open
  // one (Q-36; the caller checks that). The ops' own arguments are checked
  // when they are applied (ListPatch.apply runs ListPatchOp.argErrors).
  static (String?, List<ListPatchOp>, List<ListError>) patchList(
    Object? args,
    ListCatalog catalog,
  ) {
    const String op = 'patch_list';
    final List<ListError> errors = checkArgs(
      args,
      op,
      const {'listId': ArgType.string, 'ops': ArgType.list},
      required: const {'listId', 'ops'},
    );
    if (args is! Map) {
      return (null, const [], errors);
    }
    final (ListDefinition? definition, List<ListError> targetErrors) = _target(args, catalog);
    errors.addAll(targetErrors);
    final List<ListPatchOp> ops = [];
    final Object? rawOps = args['ops'];
    if (rawOps is List) {
      for (int i = 0; i < rawOps.length; i++) {
        final String path = 'ops[$i]';
        final Object? raw = rawOps[i];
        if (raw is! Map) {
          errors.add(_wrongType(op, path, ArgType.object));
          continue;
        }
        final Map<String, dynamic> json = Map<String, dynamic>.from(raw);
        final PatchOpKind? kind = enumFromWire(PatchOpKind.values, json['op']);
        if (kind == null) {
          errors.add(ListError(
            ListErrorCode.badOp,
            {'op': '${json['op']}', 'detail': 'unknown patch op'},
          ));
          continue;
        }
        // The AI never changes whether a list may be sent to it.
        if (kind == PatchOpKind.setListInfo && json.containsKey('aiAllowed')) {
          errors.add(_unknown(op, '$path.aiAllowed'));
          continue;
        }
        if (kind == PatchOpKind.addBehavior) {
          final (Object? behavior, List<ListError> behaviorErrors) =
              _behavior(json['behavior'], op, '$path.behavior');
          json['behavior'] = behavior;
          if (behaviorErrors.isNotEmpty) {
            errors.addAll(behaviorErrors);
            continue;
          }
        }
        json.remove('op');
        ops.add(ListPatchOp(kind, json));
      }
    }
    return (definition?.id, ops, errors);
  }

  // upsert_items {listId, items: [{id?, values}]}: an item with an id
  // edits that item of the list (only the given fields; a null value
  // clears one), one without adds a new item with the fields' defaults.
  // The items are checked against the list's fields.
  static (ListChanges, List<ListError>) upsertItems(
    Object? args,
    ListCatalog catalog, {
    required String Function() newId,
    required DateTime now,
  }) {
    const String op = 'upsert_items';
    final List<ListError> errors = checkArgs(
      args,
      op,
      const {'listId': ArgType.string, 'items': ArgType.list},
      required: const {'listId', 'items'},
    );
    if (args is! Map) {
      return (const ListChanges(), errors);
    }
    final (ListDefinition? definition, List<ListError> targetErrors) = _target(args, catalog);
    errors.addAll(targetErrors);
    final Object? items = args['items'];
    if (definition == null || items is! List) {
      return (const ListChanges(), errors);
    }
    final (List<ListItem> saved, List<ListError> itemErrors) = _items(
      items,
      definition,
      catalog.itemsOf(definition.id),
      op,
      newId: newId,
      now: now,
    );
    errors.addAll(itemErrors);
    return (errors.isEmpty ? ListChanges(saved: saved) : const ListChanges(), errors);
  }

  static (List<ListItem>, List<ListError>) _items(
    List items,
    ListDefinition definition,
    List<ListItem> existing,
    String op, {
    required String Function() newId,
    required DateTime now,
    bool allowIds = true,
  }) {
    final List<ListItem> saved = [];
    final List<ListError> errors = [];
    for (int i = 0; i < items.length; i++) {
      final String path = 'items[$i]';
      final List<ListError> argErrors = checkArgs(
        items[i],
        op,
        {if (allowIds) 'id': ArgType.string, 'values': ArgType.list},
        required: const {'values'},
        path: path,
      );
      if (argErrors.isNotEmpty) {
        errors.addAll(argErrors);
        continue;
      }
      final Map json = items[i] as Map;
      final String? id = json['id'] as String?;
      ListItem? before;
      if (id != null) {
        before = existing.where((item) => item.id == id).firstOrNull;
        if (before == null) {
          errors.add(ListError(ListErrorCode.unknownItem, {'item': id, 'list': definition.id}));
          continue;
        }
      }
      final (Map<String, dynamic> values, List<ListError> entryErrors) =
          _entries(json['values'], op, '$path.values');
      errors.addAll(entryErrors);
      for (final String key in values.keys) {
        final FieldDefinition? field = definition.field(key);
        if (field == null) {
          errors.add(ListError(ListErrorCode.unknownField, {'field': key, 'list': definition.id}));
        } else if (field.type == FieldType.checklist) {
          values[key] = _subItems(values[key], newId, now);
        }
      }
      if (entryErrors.isNotEmpty) {
        continue;
      }
      final Map<String, dynamic> merged = {
        if (before == null)
          for (final FieldDefinition field in definition.fields)
            if (field.defaultValue != null) field.key: field.defaultValue,
        ...?before?.values,
        ...values,
      }..removeWhere((key, value) => value == null);
      final ListItem item = ListItem(
        id: before?.id ?? newId(),
        listId: definition.id,
        values: merged,
        createdAt: before?.createdAt ?? now,
        updatedAt: now,
      );
      errors.addAll([
        for (final ListError error in item.validateAgainst(definition))
          error.forItem(item.id),
      ]);
      saved.add(item);
    }
    return (saved, errors);
  }

  // Checklist sub-items may come as {title, done}; they get the id and
  // dates every sub-item has. Anything else is left for validateAgainst.
  static Object? _subItems(Object? value, String Function() newId, DateTime now) {
    if (value is! List) {
      return value;
    }
    return [
      for (final Object? entry in value)
        if (entry is Map)
          {
            'id': entry['id'] ?? newId(),
            'createdAt': now.toIso8601String(),
            'updatedAt': now.toIso8601String(),
            ...Map<String, dynamic>.from(entry),
          }
        else
          entry,
    ];
  }

  // delete_items {listId, ids}: every id must be an item of that list.
  static (ListChanges, List<ListError>) deleteItems(
    Object? args,
    ListCatalog catalog,
  ) {
    const String op = 'delete_items';
    final List<ListError> errors = checkArgs(
      args,
      op,
      const {'listId': ArgType.string, 'ids': ArgType.list},
      required: const {'listId', 'ids'},
    );
    if (args is! Map) {
      return (const ListChanges(), errors);
    }
    final (ListDefinition? definition, List<ListError> targetErrors) = _target(args, catalog);
    errors.addAll(targetErrors);
    final Object? ids = args['ids'];
    if (definition == null || ids is! List) {
      return (const ListChanges(), errors);
    }
    final Set<String> known = {for (final ListItem item in catalog.itemsOf(definition.id)) item.id};
    final List<String> deleted = [];
    for (int i = 0; i < ids.length; i++) {
      final Object? id = ids[i];
      if (id is! String) {
        errors.add(_wrongType(op, 'ids[$i]', ArgType.string));
      } else if (!known.contains(id)) {
        errors.add(ListError(ListErrorCode.unknownItem, {'item': id, 'list': definition.id}));
      } else {
        deleted.add(id);
      }
    }
    return (errors.isEmpty ? ListChanges(deletedIds: deleted) : const ListChanges(), errors);
  }

  // create_list {list, items?}: a new list with the id [listId] and,
  // optionally, its first items (values only, no ids).
  static (ListDefinition?, List<ListItem>, List<ListError>) createList(
    Object? args, {
    required String listId,
    required String Function() newId,
    required DateTime now,
  }) {
    const String op = 'create_list';
    final List<ListError> errors = checkArgs(
      args,
      op,
      const {'list': ArgType.object, 'items': ArgType.list},
      required: const {'list'},
    );
    if (args is! Map || args['list'] is! Map) {
      return (null, const [], errors);
    }
    final Map<String, dynamic> list = Map<String, dynamic>.from(args['list'] as Map);
    errors.addAll(unknownKeys(list, InputShape.newList, op, 'list'));
    errors.addAll(checkArgs(
      list,
      op,
      const {
        'name': ArgType.string,
        'icon': ArgType.string,
        'color': ArgType.string,
        'fields': ArgType.list,
        'view': ArgType.object,
        'behaviors': ArgType.list,
      },
      required: const {'name', 'icon', 'color', 'fields', 'view'},
      path: 'list',
    ).where((error) => error.code != ListErrorCode.unknownArg));
    final Object? behaviors = list['behaviors'];
    if (behaviors is List) {
      final List<Object?> converted = [];
      for (int i = 0; i < behaviors.length; i++) {
        final (Object? behavior, List<ListError> behaviorErrors) =
            _behavior(behaviors[i], op, 'list.behaviors[$i]');
        errors.addAll(behaviorErrors);
        converted.add(behavior);
      }
      list['behaviors'] = converted;
    }
    if (errors.isNotEmpty) {
      return (null, const [], errors);
    }
    final ListDefinition definition;
    try {
      definition = ListDefinition.fromJson({
        ...list,
        'id': listId,
        'updatedAt': now.toIso8601String(),
      });
    } on FormatException catch (error) {
      return (null, const [], [_badOp(op, error)]);
    }
    errors.addAll(definition.validate());
    final Object? items = args['items'];
    final (List<ListItem> saved, List<ListError> itemErrors) = items is List && errors.isEmpty
        ? _items(items, definition, const [], op, newId: newId, now: now, allowIds: false)
        : (const <ListItem>[], const <ListError>[]);
    errors.addAll(itemErrors);
    return errors.isEmpty ? (definition, saved, errors) : (null, const [], errors);
  }
}
