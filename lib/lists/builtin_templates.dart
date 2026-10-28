import 'list_definition.dart';
import 'list_vocabulary.dart';

// The four list templates, described with the generic vocabulary (Q-22 D).
// A new account gets one starter copy of each, an ordinary list that can be
// edited and deleted; "New list" offers them, and the AI gets them as
// examples. A copy has its own list id and names its template in
// `templateId`. The ids below are template keys, kept from the time these
// were fixed built-in lists. Labels are l10n keys from lib/l10n/app_en.arb;
// colours are the Q-19 A palette.
class BuiltinTemplates {
  static const String tasksId = 'builtin.tasks';
  static const String groceryId = 'builtin.grocery';
  static const String journalId = 'builtin.journal';
  static const String watchReadId = 'builtin.watchRead';

  static final DateTime _created = DateTime.utc(2026, 10, 25);

  static List<ListDefinition> all({List<String> taskCategories = const []}) {
    return [
      tasks(categories: taskCategories),
      grocery(),
      journal(),
      watchRead(),
    ];
  }

  static ListDefinition tasks({List<String> categories = const []}) {
    return ListDefinition(
      id: tasksId,
      nameKey: 'tasks',
      icon: 'pending_actions',
      color: '#FF4D12',
      templateId: tasksId,
      fields: [
        const FieldDefinition(
          key: 'title',
          type: FieldType.text,
          labelKey: 'title',
          required: true,
          primary: true,
        ),
        const FieldDefinition(
          key: 'description',
          type: FieldType.longText,
          labelKey: 'description',
        ),
        const FieldDefinition(
          key: 'done',
          type: FieldType.checkbox,
          labelKey: 'completed',
          role: FieldRole.completion,
        ),
        FieldDefinition(
          key: 'category',
          type: FieldType.category,
          labelKey: 'category',
          role: FieldRole.category,
          options: [
            for (final String category in categories)
              FieldOption(value: category, label: category),
          ],
        ),
        const FieldDefinition(
          key: 'subtasks',
          type: FieldType.checklist,
          labelKey: 'subtasks',
        ),
        // Labelled "Date": reminders are stored but no notification fires
        // yet (plan section 2, caveat 5).
        const FieldDefinition(
          key: 'reminderAt',
          type: FieldType.dateTime,
          labelKey: 'date',
          role: FieldRole.reminder,
        ),
        const FieldDefinition(
          key: 'repeat',
          type: FieldType.recurrence,
          labelKey: 'repeat',
        ),
      ],
      view: const ViewDefinition(
        kind: ViewKind.checklist,
        filterChipsBy: 'category',
        bucketBy: 'reminderAt',
      ),
      behaviors: const [
        BehaviorDefinition(
          kind: BehaviorKind.recurOnClear,
          params: {'dateField': 'reminderAt', 'recurrenceField': 'repeat'},
        ),
        BehaviorDefinition(kind: BehaviorKind.clearCompleted),
      ],
      updatedAt: _created,
    );
  }

  static ListDefinition grocery() {
    return ListDefinition(
      id: groceryId,
      nameKey: 'grocery',
      icon: 'shopping_cart',
      color: '#00A63E',
      templateId: groceryId,
      fields: const [
        FieldDefinition(
          key: 'title',
          type: FieldType.text,
          labelKey: 'title',
          required: true,
          primary: true,
        ),
        FieldDefinition(
          key: 'description',
          type: FieldType.longText,
          labelKey: 'description',
        ),
        FieldDefinition(
          key: 'done',
          type: FieldType.checkbox,
          labelKey: 'completed',
          role: FieldRole.completion,
        ),
        FieldDefinition(
          key: 'section',
          type: FieldType.choice,
          labelKey: 'section',
          role: FieldRole.section,
          options: [
            FieldOption(value: 'current', labelKey: 'currentGroceryRun'),
            FieldOption(value: 'nextTime', labelKey: 'nextTime'),
          ],
          defaultValue: 'current',
        ),
        FieldDefinition(
          key: 'autoAddToNext',
          type: FieldType.toggle,
          labelKey: 'repeatsToNextTime',
        ),
      ],
      view: const ViewDefinition(
        kind: ViewKind.sectioned,
        sectionBy: 'section',
      ),
      behaviors: const [
        BehaviorDefinition(
          kind: BehaviorKind.copyOnClear,
          params: {
            'when': 'autoAddToNext',
            'where': {'section': 'current'},
            'setField': {'section': 'nextTime'},
            'dedupeBy': 'title',
          },
        ),
        BehaviorDefinition(
          kind: BehaviorKind.moveAll,
          params: {'field': 'section', 'from': 'nextTime', 'to': 'current'},
        ),
        BehaviorDefinition(kind: BehaviorKind.clearCompleted),
      ],
      updatedAt: _created,
    );
  }

  static ListDefinition journal() {
    return ListDefinition(
      id: journalId,
      nameKey: 'journal',
      icon: 'book',
      color: '#E5007E',
      templateId: journalId,
      fields: const [
        FieldDefinition(
          key: 'title',
          type: FieldType.text,
          labelKey: 'title',
          required: true,
          primary: true,
        ),
        FieldDefinition(
          key: 'body',
          type: FieldType.longText,
          labelKey: 'entry',
        ),
      ],
      view: const ViewDefinition(
        kind: ViewKind.timeline,
        dateField: 'createdAt',
        timelineGrouping: TimelineGrouping.month,
      ),
      updatedAt: _created,
    );
  }

  static ListDefinition watchRead() {
    return ListDefinition(
      id: watchReadId,
      nameKey: 'watchRead',
      icon: 'movie',
      color: '#6B3BFF',
      templateId: watchReadId,
      fields: const [
        FieldDefinition(
          key: 'title',
          type: FieldType.text,
          labelKey: 'title',
          required: true,
          primary: true,
        ),
        FieldDefinition(
          key: 'type',
          type: FieldType.choice,
          labelKey: 'type',
          options: [
            FieldOption(value: 'movie', labelKey: 'movie'),
            FieldOption(value: 'tvShow', labelKey: 'tvShow'),
            FieldOption(value: 'book', labelKey: 'book'),
          ],
          defaultValue: 'movie',
        ),
        FieldDefinition(
          key: 'status',
          type: FieldType.choice,
          labelKey: 'status',
          role: FieldRole.status,
          options: [
            FieldOption(value: 'planned', labelKey: 'planned'),
            FieldOption(value: 'inProgress', labelKey: 'inProgress'),
            FieldOption(value: 'completed', labelKey: 'completed'),
          ],
          defaultValue: 'planned',
        ),
        FieldDefinition(
          key: 'season',
          type: FieldType.counter,
          labelKey: 'season',
          min: 0,
          visibleWhen: FieldCondition(field: 'type', values: ['tvShow']),
        ),
        FieldDefinition(
          key: 'episode',
          type: FieldType.counter,
          labelKey: 'episode',
          min: 0,
          visibleWhen: FieldCondition(field: 'type', values: ['tvShow']),
        ),
        FieldDefinition(
          key: 'notes',
          type: FieldType.longText,
          labelKey: 'notes',
        ),
      ],
      view: const ViewDefinition(
        kind: ViewKind.grouped,
        groupBy: 'status',
      ),
      updatedAt: _created,
    );
  }
}
