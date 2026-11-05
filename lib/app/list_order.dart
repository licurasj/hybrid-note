import '../lists/list_definition.dart';
import 'account_preferences.dart';

// The lists in the order the user chose (Q-49). [definitions] comes in
// creation order, which is also where anything without a place goes: lists
// never opened (Last used) and lists not arranged yet, such as new ones (My
// order). Ids with no list are skipped. A to Z sorts by the name on screen.
List<ListDefinition> orderLists(
  List<ListDefinition> definitions, {
  required ListOrder order,
  required List<String> myOrder,
  required List<String> recent,
  required String Function(ListDefinition definition) nameOf,
}) {
  final Map<String, int> created = {
    for (int i = 0; i < definitions.length; i++) definitions[i].id: i,
  };

  int byPlaces(List<String> places, ListDefinition a, ListDefinition b) {
    int place(ListDefinition definition) {
      final int index = places.indexOf(definition.id);
      return index < 0 ? places.length + created[definition.id]! : index;
    }

    return place(a).compareTo(place(b));
  }

  int byName(ListDefinition a, ListDefinition b) {
    final int names = nameOf(
      a,
    ).toLowerCase().compareTo(nameOf(b).toLowerCase());
    return names != 0 ? names : created[a.id]!.compareTo(created[b.id]!);
  }

  return [...definitions]..sort(switch (order) {
    ListOrder.lastUsed => (a, b) => byPlaces(recent, a, b),
    ListOrder.myOrder => (a, b) => byPlaces(myOrder, a, b),
    ListOrder.alphabetical => byName,
  });
}
