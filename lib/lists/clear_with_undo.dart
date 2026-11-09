import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../app/app_banner.dart';
import '../l10n/generated/app_localizations.dart';
import 'list_catalog.dart';
import 'list_definition.dart';
import 'list_item.dart';
import 'list_rules.dart';
import 'list_store.dart';

// What one clear did, kept so Undo can take it back (T-23, Q-101): the items
// it removed, as they were, and the items it made (Grocery's Next time copies,
// a repeating task's next one).
class ClearUndo {
  const ClearUndo({
    required this.listId,
    required this.cleared,
    required this.created,
  });

  // The clear [changes] made from [items] (the list's items before it).
  factory ClearUndo.of(
    String listId,
    List<ListItem> items,
    ListChanges changes,
  ) {
    final Set<String> deleted = changes.deletedIds.toSet();
    return ClearUndo(
      listId: listId,
      cleared: [for (final ListItem item in items) if (deleted.contains(item.id)) item],
      created: changes.saved,
    );
  }

  final String listId;
  final List<ListItem> cleared;
  final List<ListItem> created;

  int get count => cleared.length;

  // Whether [stored] (the list's items now) is still as the clear left it:
  // no cleared item is back and every made item is there, unchanged. Like AI
  // Undo (Q-52), anything else means someone has changed it since.
  bool isCurrent(Iterable<ListItem> stored) {
    final Map<String, ListItem> byId = {for (final ListItem item in stored) item.id: item};
    if (cleared.any((item) => byId.containsKey(item.id))) {
      return false;
    }
    return created.every((item) {
      final ListItem? now = byId[item.id];
      return now != null && ListSnapshot.sameJson(now.values, item.values);
    });
  }

  // Puts the cleared items back with their ids and values, and removes what
  // the clear made.
  ListChanges reverse() => ListChanges(
        saved: cleared,
        deletedIds: [for (final ListItem item in created) item.id],
      );
}

// Clears ticked items with "Cleared · Undo" (Q-101). The list page's × and
// Clear ticked, its top-bar clear and home's × on a Today row all come here,
// so they clear and undo the same way. Undo goes away once anything it would
// undo has changed, here or on another phone. Writes queue offline like a
// tick, so this works offline too.
class ClearWithUndo {
  ClearWithUndo._();

  // Only the latest clear can be undone; its banner replaces any before.
  static StreamSubscription<ListCatalog>? _watch;

  static Future<void> run({
    required ListStore store,
    required ListDefinition definition,
    required List<ListItem> items,
    bool Function(ListItem item)? inScope,
    AppBannerController? banners,
    required AppLocalizations loc,
  }) async {
    final ListChanges changes = ListRules.clearCompleted(
      definition,
      items,
      DateTime.now().toUtc(),
      inScope: inScope,
    );
    if (changes.isEmpty) {
      return;
    }
    final ClearUndo undo = ClearUndo.of(definition.id, items, changes);
    final Future<void> written = store.apply(changes);

    if (banners != null && undo.count > 0) {
      _offerUndo(store, banners, loc, undo);
    }
    await written;
  }

  static void _offerUndo(
    ListStore store,
    AppBannerController banners,
    AppLocalizations loc,
    ClearUndo undo,
  ) {
    _watch?.cancel();
    _watch = null;

    // A write may reach the catalog a little later, so the clear counts as
    // changed only after it was seen as it left things (as AI Undo does).
    bool seen = false;
    bool changed = false;
    late final int serial;

    void stop() {
      _watch?.cancel();
      _watch = null;
    }

    serial = banners.show(
      loc.clearedBanner(undo.count),
      actionLabel: loc.undo,
      onAction: () {
        stop();
        if (changed) {
          return;
        }
        store.apply(undo.reverse()).catchError((Object error) {
          developer.log('undo clear failed: $error', name: 'ClearWithUndo');
        });
      },
    );

    // The banner goes by itself after a while, or another replaces it; the
    // watch goes with it.
    late final VoidCallback onBanner;
    onBanner = () {
      if (!banners.isShowing(serial)) {
        banners.changes.removeListener(onBanner);
        stop();
      }
    };
    banners.changes.addListener(onBanner);
    _watch = store.watch().listen((catalog) {
      if (!banners.isShowing(serial)) {
        stop();
        return;
      }
      if (undo.isCurrent(catalog.itemsOf(undo.listId))) {
        seen = true;
      } else if (seen) {
        changed = true;
        stop();
        banners.dismissIf(serial);
      }
    });
  }
}
