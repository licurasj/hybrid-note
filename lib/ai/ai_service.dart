import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../lists/list_catalog.dart';
import '../lists/list_definition.dart';
import '../lists/list_item.dart';
import '../lists/list_labels.dart';

// The AI command (T-19): one callable Cloud Function, `aiCommand` in
// us-central1, that holds the provider keys and the caps. It writes no list
// data; the device validates its tool calls, previews and applies them
// (plan 7.1 step 5). The request and answer shapes are those of
// functions/src/request.ts and functions/src/handler.ts.
abstract interface class AiService {
  // Throws AiRefusal when the function refuses or cannot be reached.
  Future<AiAnswer> send(AiRequest request);
}

// The provider named in the one-time notice. It changes with ACTIVE_MODEL
// in functions/src/config.ts, and with the notice text (deepseek-3: list
// descriptions, Q-44); a change here shows the notice again.
const String aiNoticeId = 'deepseek-3';

// One of the user's lists as the function sees it (Q-36): id, name and a
// short field summary, no items.
class AiListSummary {
  const AiListSummary({
    required this.id,
    required this.name,
    this.description,
    required this.fields,
  });

  final String id;
  final String name;
  // The list's description (Q-44), when it has one.
  final String? description;
  final List<Map<String, Object?>> fields;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    if (description != null) 'description': description,
    'fields': fields,
    // Only lists with AI on are sent (L16, M4); the function refuses a
    // summary without the flag.
    'aiAllowed': true,
  };
}

class AiToolCall {
  const AiToolCall(this.name, this.args);

  final String name;
  final Object? args;

  Map<String, Object?> toJson() => {'name': name, 'args': args};
}

// The device's self-correction round (Q-34 A): the previous answer's tool
// calls and the ListErrors found in them, in English.
class AiCorrection {
  const AiCorrection({required this.toolCalls, required this.errors});

  final List<AiToolCall> toolCalls;
  final List<String> errors;

  // The function's limits (functions/src/request.ts).
  static const int maxCalls = 10;
  static const int maxErrors = 20;
  static const int maxErrorChars = 300;

  Map<String, Object?> toJson() => {
    'toolCalls': [
      for (final AiToolCall call in toolCalls.take(maxCalls)) call.toJson(),
    ],
    'errors': [
      for (final String error in errors.take(maxErrors))
        error.length <= maxErrorChars
            ? error
            : error.substring(0, maxErrorChars),
    ],
  };
}

// The user answers the AI's reply (Q-42): the earlier request and the
// reply, sent with the answer.
class AiFollowUp {
  const AiFollowUp({required this.prompt, required this.reply});

  final String prompt;
  final String reply;

  // The function's limit on the quoted reply (functions/src/request.ts).
  static const int maxReplyChars = 500;

  Map<String, Object?> toJson() => {
    'prompt': prompt,
    'reply': reply.length <= maxReplyChars
        ? reply
        : reply.substring(0, maxReplyChars),
  };
}

class AiRequest {
  const AiRequest({
    required this.prompt,
    required this.locale,
    required this.today,
    required this.lists,
    this.openList,
    this.openItems = const [],
    this.correction,
    this.followUp,
  });

  // At most this many of the open list's items are sent (Q-31).
  static const int maxItems = 20;

  // The request for [prompt] with the catalog's lists. Lists with AI off are
  // left out entirely, and an open list with AI off is not sent (the bar is
  // not shown there). The open list's most recently changed items go along.
  factory AiRequest.of({
    required String prompt,
    required String locale,
    required DateTime now,
    required ListCatalog catalog,
    required ListLabels labels,
    String? openListId,
    AiFollowUp? followUp,
  }) {
    final List<ListDefinition> allowed = [
      for (final ListDefinition definition in catalog.definitions)
        if (definition.aiAllowed) definition,
    ];
    final ListDefinition? open = openListId == null
        ? null
        : catalog.definition(openListId);
    final bool sendOpen = open != null && open.aiAllowed;
    final List<ListItem> items = sendOpen
        ? ([...catalog.itemsOf(open.id)]
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)))
        : const [];
    return AiRequest(
      prompt: prompt,
      locale: locale,
      today: now,
      lists: [
        for (final ListDefinition definition in allowed)
          AiListSummary(
            id: definition.id,
            name: labels.listName(definition),
            description: labels.listDescription(definition),
            fields: [
              for (final FieldDefinition field in definition.fields)
                {
                  'key': field.key,
                  'type': field.type.wire,
                  'label': labels.field(field),
                  if (field.options.isNotEmpty)
                    'options': [
                      for (final FieldOption option in field.options)
                        option.value,
                    ],
                },
            ],
          ),
      ],
      openList: sendOpen ? open : null,
      openItems: items.take(maxItems).toList(),
      followUp: followUp,
    );
  }

  final String prompt;
  final String locale;
  // The device's date, so "on Friday" means the user's Friday.
  final DateTime today;
  final List<AiListSummary> lists;
  final ListDefinition? openList;
  final List<ListItem> openItems;
  final AiCorrection? correction;
  final AiFollowUp? followUp;

  AiRequest withCorrection(AiCorrection correction) => AiRequest(
    prompt: prompt,
    locale: locale,
    today: today,
    lists: lists,
    openList: openList,
    openItems: openItems,
    correction: correction,
    followUp: followUp,
  );

  // The same request with [listId] as the open list: the answer to the AI's
  // "which list?" (choose_list).
  AiRequest withOpenList(ListCatalog catalog, String listId) {
    final ListDefinition? open = catalog.definition(listId);
    if (open == null || !open.aiAllowed) {
      return this;
    }
    final List<ListItem> items = [...catalog.itemsOf(listId)]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return AiRequest(
      prompt: prompt,
      locale: locale,
      today: today,
      lists: lists,
      openList: open,
      openItems: items.take(maxItems).toList(),
      followUp: followUp,
    );
  }

  static String _date(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  Map<String, Object?> toJson() => {
    'prompt': prompt,
    'locale': locale,
    'today': _date(today),
    'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
    'lists': [for (final AiListSummary list in lists) list.toJson()],
    'openList': openList == null
        ? null
        : {
            'definition': openList!.toJson(),
            'items': [
              for (final ListItem item in openItems)
                {'id': item.id, 'values': item.values},
            ],
          },
    if (correction != null) 'correction': correction!.toJson(),
    if (followUp != null) 'followUp': followUp!.toJson(),
  };
}

class AiAnswer {
  const AiAnswer({
    required this.requestId,
    required this.toolCalls,
    this.declineReason,
    this.droppedTools = 0,
  });

  factory AiAnswer.fromJson(Map<Object?, Object?> json) {
    final Object? calls = json['toolCalls'];
    return AiAnswer(
      requestId: '${json['requestId'] ?? ''}',
      declineReason: json['outcome'] == 'declined'
          ? '${json['declineReason'] ?? 'offTopic'}'
          : null,
      droppedTools: switch (json['droppedTools']) {
        final int count when count > 0 => count,
        _ => 0,
      },
      toolCalls: [
        if (calls is List)
          for (final Object? call in calls)
            if (call is Map && call['name'] is String)
              AiToolCall(call['name'] as String, _plain(call['args'])),
      ],
    );
  }

  final String requestId;
  final List<AiToolCall> toolCalls;
  // offTopic, notSupported, providerRefusal or noValidTool; null when the
  // answer was not a decline.
  final String? declineReason;
  // Tool calls the function left out (invalid, or a list they may not
  // touch): the rest is only part of what was asked (L3).
  final int droppedTools;

  bool get declined => declineReason != null;

  // The same answer with [calls], for the phone's item matching (Q-39).
  AiAnswer withToolCalls(List<AiToolCall> calls) => AiAnswer(
    requestId: requestId,
    toolCalls: calls,
    declineReason: declineReason,
    droppedTools: droppedTools,
  );

  // The platform channel hands back Map<Object?, Object?>; ListInput reads
  // Map and List, so only the keys need to become strings.
  static Object? _plain(Object? value) {
    if (value is Map) {
      return {
        for (final MapEntry<Object?, Object?> entry in value.entries)
          '${entry.key}': _plain(entry.value),
      };
    }
    if (value is List) {
      return [for (final Object? element in value) _plain(element)];
    }
    return value;
  }
}

// Why the function refused (functions/src/errors.ts `details.reason`), or
// `unavailable` when it could not be reached at all. A `provider` refusal
// whose kind says the key or the balance is the problem becomes
// `providerAccount` (L4), so it is not shown as "try again later".
class AiRefusal implements Exception {
  const AiRefusal(this.reason);

  // From a FirebaseFunctionsException's details and code.
  factory AiRefusal.of(Object? details, String code) {
    final Object? reason = details is Map ? details['reason'] : null;
    final Object? kind = details is Map ? details['kind'] : null;
    if (reason == 'provider' && _accountKinds.contains(kind)) {
      return const AiRefusal('providerAccount');
    }
    return AiRefusal(reason is String ? reason : code);
  }

  final String reason;

  @override
  String toString() => 'AiRefusal($reason)';
}

// functions/src/provider/types.ts kinds that only the account's owner can fix.
const Set<String> _accountKinds = {'auth', 'billing', 'noKey'};

class FunctionsAiService implements AiService {
  FunctionsAiService([FirebaseFunctions? functions])
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFunctions _functions;

  @override
  Future<AiAnswer> send(AiRequest request) async {
    final HttpsCallable call = _functions.httpsCallable(
      'aiCommand',
      // The function's own timeout is 120 s (two provider calls).
      options: HttpsCallableOptions(timeout: const Duration(seconds: 130)),
    );
    try {
      final HttpsCallableResult<Object?> result = await call.call<Object?>(
        request.toJson(),
      );
      final Object? data = result.data;
      if (data is! Map) {
        throw const AiRefusal('badResponse');
      }
      return AiAnswer.fromJson(data);
    } on FirebaseFunctionsException catch (error) {
      throw AiRefusal.of(error.details, error.code);
    }
  }
}
