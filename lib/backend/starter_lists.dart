import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../lists/builtin_templates.dart';
import '../lists/list_definition.dart';
import '../lists/list_item.dart';
import 'firestore_list_store.dart';

// Starter copies of the templates, written once per account (Q-22 D).
//
// One transaction reads the marker document users/{uid}; if it is absent it
// writes the marker and a copy of each template. A transaction reads from
// the server, so a device that starts with an empty cache still sees a
// marker another device wrote, and the copies never come back after the
// user deletes them. Offline the transaction fails and nothing is written;
// the next call tries again.
//
// The copies are ordinary lists with fresh ids (`list-<uuid>`, like any new
// list) and the template's `templateId`. Their `_createdAt` is staggered by
// a millisecond so they keep the template order. Sample items (T-18) get
// fresh ids on every run, since item ids are unique across a user's lists.
//
// With no templates, only the marker is written: "Start empty" after a
// failed seeding (Q-27), so the starter lists never appear later.
class StarterLists {
  static const String seededAtKey = 'starterSeededAt';

  static DocumentReference<Map<String, dynamic>> marker(
    FirebaseFirestore firestore,
    String uid,
  ) {
    return firestore.collection('users').doc(uid);
  }

  // Writes the starter lists unless the account has them already. Returns
  // true when this call wrote them. Throws what the transaction throws, for
  // example a FirebaseException 'unavailable' offline.
  //
  // [sampleItems] maps a template id to items to copy into that list; their
  // ids and listId are replaced.
  static Future<bool> ensure(
    FirebaseFirestore firestore,
    String uid, {
    List<ListDefinition>? templates,
    Map<String, List<ListItem>> sampleItems = const {},
    DateTime? now,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final DocumentReference<Map<String, dynamic>> markerRef = marker(
      firestore,
      uid,
    );
    // Seen before on this device: no server round trip.
    try {
      final DocumentSnapshot<Map<String, dynamic>> cached = await markerRef
          .get(const GetOptions(source: Source.cache));
      if (cached.exists) {
        return false;
      }
    } on FirebaseException {
      // Not in the cache.
    }

    final DateTime seededAt = (now ?? DateTime.now()).toUtc();
    final List<ListDefinition> sources = templates ?? BuiltinTemplates.all();
    final bool seeded = await firestore.runTransaction<bool>((
      transaction,
    ) async {
      if ((await transaction.get(markerRef)).exists) {
        return false;
      }
      transaction.set(markerRef, {seededAtKey: seededAt.toIso8601String()});
      final List<StarterCopy> copies = StarterLists.copies(
        sources,
        sampleItems: sampleItems,
        now: seededAt,
      );
      for (int index = 0; index < copies.length; index++) {
        final StarterCopy copy = copies[index];
        final DocumentReference<Map<String, dynamic>> listRef = firestore.doc(
          'users/$uid/lists/${copy.definition.id}',
        );
        transaction.set(
          listRef,
          FirestoreListStore.definitionData(
            copy.definition,
            createdAt: seededAt.add(Duration(milliseconds: index)),
          ),
        );
        for (final ListItem item in copy.items) {
          transaction.set(
            listRef.collection('items').doc(item.id),
            FirestoreListStore.itemData(item, copy.definition.schemaRevision),
          );
        }
      }
      return true;
    }, timeout: timeout);

    // A plain read puts the marker in the cache (a transaction read may
    // not), so the next start skips the transaction, offline too.
    try {
      await markerRef.get(const GetOptions(source: Source.server));
    } on FirebaseException {
      // The next call checks the server again.
    }
    return seeded;
  }

  // The starter copies of [templates] with their sample items, in template
  // order, with fresh list and item ids; the demo's in-memory store (T-18)
  // starts from them too.
  static List<StarterCopy> copies(
    List<ListDefinition> templates, {
    Map<String, List<ListItem>> sampleItems = const {},
    required DateTime now,
  }) {
    return [
      for (final ListDefinition template in templates)
        _copy(template, sampleItems, now),
    ];
  }

  static StarterCopy _copy(
    ListDefinition template,
    Map<String, List<ListItem>> sampleItems,
    DateTime now,
  ) {
    final ListDefinition copy = template.copyWith(
      id: 'list-${const Uuid().v4()}',
      updatedAt: now,
    );
    return (
      definition: copy,
      items: [
        for (final ListItem sample
            in sampleItems[template.templateId ?? template.id] ?? const [])
          ListItem(
            id: const Uuid().v4(),
            listId: copy.id,
            values: sample.values,
            createdAt: sample.createdAt,
            updatedAt: sample.updatedAt,
          ),
      ],
    );
  }
}

// One starter list and its sample items.
typedef StarterCopy = ({ListDefinition definition, List<ListItem> items});
