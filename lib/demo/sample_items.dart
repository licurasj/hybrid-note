import '../lists/builtin_templates.dart';
import '../lists/list_item.dart';

// The demo's sample items (T-18, Q-87): English in every language, by
// template id, for StarterLists.copies, which gives them their ids and list.
// Dates are relative to [now], so the journal and the item times look recent.
// The Tasks samples leave the reminder field empty: nothing rings on web.
Map<String, List<ListItem>> demoSampleItems(DateTime now) {
  int count = 0;
  ListItem item(Map<String, dynamic> values, {Duration ago = Duration.zero}) {
    // A minute apart, so the order is the one written here.
    final DateTime at = now
        .subtract(ago)
        .subtract(Duration(minutes: 60 - count++));
    return ListItem(
      id: 'sample-$count',
      listId: '',
      values: values,
      createdAt: at,
      updatedAt: at,
    );
  }

  Map<String, dynamic> subtask(String id, String title, {bool done = false}) {
    final String at = now.toUtc().toIso8601String();
    return {
      'id': id,
      'title': title,
      'done': done,
      'createdAt': at,
      'updatedAt': at,
    };
  }

  return {
    BuiltinTemplates.tasksId: [
      item({'title': 'Call the dentist', 'done': false}),
      item({
        'title': 'Plan the weekend trip',
        'description': 'Somewhere by the sea, two nights.',
        'done': false,
        'subtasks': [
          subtask('trip-1', 'Book train tickets', done: true),
          subtask('trip-2', 'Find a place to stay'),
          subtask('trip-3', 'Pack the camera'),
        ],
      }),
      item({'title': 'Renew the library card', 'done': false}),
      item({'title': 'Water the plants', 'done': true}),
    ],
    BuiltinTemplates.groceryId: [
      item({'title': 'Milk', 'done': false, 'section': 'current'}),
      item({'title': 'Eggs', 'done': false, 'section': 'current'}),
      item({'title': 'Bananas', 'done': true, 'section': 'current'}),
      item({'title': 'Coffee beans', 'done': false, 'section': 'current'}),
      item({'title': 'Olive oil', 'done': false, 'section': 'nextTime'}),
    ],
    BuiltinTemplates.journalId: [
      item({
        'title': 'A slow Sunday',
        'body': 'Long walk by the river, then soup and a book.',
      }, ago: const Duration(days: 2)),
      item({
        'title': 'New café on the corner',
        'body': 'Great flat white. Try the cardamom bun next time.',
      }, ago: const Duration(days: 1)),
      item({
        'title': 'Started the garden',
        'body': 'Planted basil and mint on the balcony.',
      }),
    ],
    BuiltinTemplates.watchReadId: [
      item({
        'title': 'Severance',
        'type': 'tvShow',
        'status': 'inProgress',
        'season': 2,
        'episode': 3,
      }),
      item({'title': 'Spirited Away', 'type': 'movie', 'status': 'completed'}),
      item({
        'title': 'The Left Hand of Darkness',
        'type': 'book',
        'status': 'planned',
      }),
      item({
        'title': 'Project Hail Mary',
        'type': 'book',
        'status': 'inProgress',
      }),
    ],
  };
}
