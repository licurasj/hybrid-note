import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/demo/memory_list_store.dart';
import 'package:hybrid_note/lists/list_store.dart';

import '../lists/list_store_contract_test.dart'
    show StaggeredListStore, listStoreContract;
import '../support/firestore_store.dart' show starterLists;

// The demo's store (T-18 unit 2a) against the shared ListStore contract.
void main() {
  final Map<ListStore, Future<void> Function()> closers = {};
  Future<void> dispose(ListStore store) => closers.remove(store)!();

  listStoreContract('MemoryListStore', () async {
    final MemoryListStore store = MemoryListStore(lists: starterLists());
    closers[store] = store.close;
    return store;
  }, dispose: dispose);

  listStoreContract('MemoryListStore with staggered updates', () async {
    final MemoryListStore inner = MemoryListStore(lists: starterLists());
    final StaggeredListStore store = StaggeredListStore(inner);
    closers[store] = () async {
      await store.close();
      await inner.close();
    };
    await store.watch().first;
    return store;
  }, dispose: dispose);
}
