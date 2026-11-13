import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lists/list_definition.dart';
import '../reminders/reminder_settings.dart';
import 'home_cards.dart';

// How the home and launcher order the lists (Q-49).
enum ListOrder {
  lastUsed('lastUsed'),
  myOrder('myOrder'),
  alphabetical('az');

  const ListOrder(this.wire);

  final String wire;

  static ListOrder of(Object? wire) => values.firstWhere(
    (order) => order.wire == wire,
    orElse: () => ListOrder.lastUsed,
  );
}

// The order of home's pinned cards (Q-108): the dial's, its own sort, or its
// own dragged order.
enum HomeListOrder {
  sameAsDial('sameAsDial'),
  lastUsed('lastUsed'),
  myOrder('myOrder'),
  alphabetical('az');

  const HomeListOrder(this.wire);

  final String wire;

  // Home's own choice that matches the dial's [order].
  static HomeListOrder ofDial(ListOrder order) => switch (order) {
    ListOrder.lastUsed => lastUsed,
    ListOrder.alphabetical => alphabetical,
    ListOrder.myOrder => myOrder,
  };

  // Null for a missing or unknown value.
  static HomeListOrder? maybeOf(Object? wire) {
    for (final HomeListOrder order in values) {
      if (order.wire == wire) {
        return order;
      }
    }
    return null;
  }
}

// What the app opens on (Q-50 a).
enum StartScreen {
  home('home'),
  lastOpenList('lastOpenList');

  const StartScreen(this.wire);

  final String wire;

  static StartScreen of(Object? wire) => values.firstWhere(
    (screen) => screen.wire == wire,
    orElse: () => StartScreen.home,
  );
}

// Where ticked items go in a list (Q-50 b).
enum TickedItems {
  moveToDone('moveToDone'),
  stayInPlace('stayInPlace'),
  hide('hide'),
  // Ticking clears the item at once, with Undo (Q-119). A phone on an older
  // build reads it as moveToDone.
  clearAtOnce('clearAtOnce');

  const TickedItems(this.wire);

  final String wire;

  static TickedItems of(Object? wire) => values.firstWhere(
    (ticked) => ticked.wire == wire,
    orElse: () => TickedItems.moveToDone,
  );
}

// How often the AI asks before acting (Q-43); the wire value goes with
// each request. Wording rules apply at balanced only.
enum AiAskLevel {
  more('more'),
  balanced('balanced'),
  less('less');

  const AiAskLevel(this.wire);

  final String wire;

  static AiAskLevel of(Object? wire) => values.firstWhere(
    (level) => level.wire == wire,
    orElse: () => AiAskLevel.balanced,
  );
}

// 12 or 24 hour times (Q-50 e).
enum TimeFormat {
  followLanguage('followLanguage'),
  h12('h12'),
  h24('h24');

  const TimeFormat(this.wire);

  final String wire;

  static TimeFormat of(Object? wire) => values.firstWhere(
    (format) => format.wire == wire,
    orElse: () => TimeFormat.followLanguage,
  );
}

// The first day of the week (Q-50 f).
enum WeekStart {
  followLanguage('followLanguage'),
  monday('monday'),
  sunday('sunday');

  const WeekStart(this.wire);

  final String wire;

  static WeekStart of(Object? wire) => values.firstWhere(
    (start) => start.wire == wire,
    orElse: () => WeekStart.followLanguage,
  );
}

// What home shows under its header (Q-73).
enum HomeContent {
  both('both'),
  cards('cards'),
  dueToday('dueToday');

  const HomeContent(this.wire);

  final String wire;

  bool get showsCards => this != dueToday;
  bool get showsDue => this != cards;

  static HomeContent of(Object? wire) => values.firstWhere(
    (content) => content.wire == wire,
    orElse: () => HomeContent.both,
  );
}

// Choices that follow the account to every phone (Q-48 A). Choices that
// belong to one phone are in AppSettings.
@immutable
class AccountPreferences {
  const AccountPreferences({
    this.listOrder = ListOrder.lastUsed,
    this.myListOrder = const [],
    this.startScreen = StartScreen.home,
    this.tickedItems = TickedItems.moveToDone,
    this.confirmDelete = false,
    this.showAiBar = true,
    this.aiAutoApply = false,
    this.aiAskLevel = AiAskLevel.balanced,
    this.aiAutoApplyOffered = false,
    this.aiNoticeSeen,
    this.vibration = true,
    this.timeFormat = TimeFormat.followLanguage,
    this.weekStart = WeekStart.followLanguage,
    this.homeContent = HomeContent.both,
    this.homeSuggestions = true,
    this.homePins = const [],
    this.homeRemoved = const [],
    this.homeOrder = const [],
    this.homeListOrder = HomeListOrder.sameAsDial,
    this.listsOwnTickedItems = true,
    this.listsOwnConfirmDelete = true,
    this.reminderLeads = ReminderLead.defaults,
    this.reminderMorning = ReminderSettings.defaultMorningMinutes,
    this.listsOwnReminderLeads = true,
  });

  static const String listOrderKey = 'listOrder';
  static const String myListOrderKey = 'myListOrder';
  static const String startScreenKey = 'startScreen';
  static const String tickedItemsKey = 'tickedItems';
  static const String confirmDeleteKey = 'confirmDelete';
  static const String showAiBarKey = 'showAiBar';
  static const String aiAutoApplyKey = 'aiAutoApply';
  static const String aiAskLevelKey = 'aiAskLevel';
  static const String aiAutoApplyOfferedKey = 'aiAutoApplyOffered';
  static const String aiNoticeSeenKey = 'aiNoticeSeen';
  static const String vibrationKey = 'vibration';
  static const String timeFormatKey = 'timeFormat';
  static const String weekStartKey = 'weekStart';
  static const String homeContentKey = 'homeContent';
  static const String homeSuggestionsKey = 'homeSuggestions';
  static const String homePinsKey = 'homePins';
  static const String homeRemovedKey = 'homeRemoved';
  static const String homeOrderKey = 'homeOrder';
  static const String homeListOrderKey = 'homeListOrder';
  static const String listsOwnTickedItemsKey = 'listsOwnTickedItems';
  static const String listsOwnConfirmDeleteKey = 'listsOwnConfirmDelete';
  // T-13: how early reminders ring (a list of ReminderLead wire values; empty
  // means no rings), the morning time of a day with no time ("HH:mm"), and
  // whether a list's own how early counts (Q-117, Q-118).
  static const String reminderLeadsKey = 'reminderLeads';
  static const String reminderMorningKey = 'reminderMorning';
  static const String listsOwnReminderLeadsKey = 'listsOwnReminderLeads';
  // Before Q-108: which orders had been arranged by hand (Q-75). Read only to
  // work out homeListOrder on an account that has none yet.
  static const String homeArrangedKey = 'homeArranged';
  static const String dialArrangedKey = 'dialArranged';

  final ListOrder listOrder;
  // List ids in the user's own order; a list that is not here goes after
  // them, and an id with no list is skipped (Q-49 A).
  final List<String> myListOrder;
  final StartScreen startScreen;
  final TickedItems tickedItems;
  final bool confirmDelete;
  final bool showAiBar;
  // The prompt bar applies every change at once, with Undo, instead of
  // showing Apply and Cancel (Q-40 A).
  final bool aiAutoApply;
  final AiAskLevel aiAskLevel;
  // The one-time offer of [aiAutoApply] was made.
  final bool aiAutoApplyOffered;
  // The id of the AI notice the user accepted; a new notice asks again.
  final String? aiNoticeSeen;
  final bool vibration;
  final TimeFormat timeFormat;
  final WeekStart weekStart;
  final HomeContent homeContent;
  // Suggestions among the cards, when cards show (Q-73).
  final bool homeSuggestions;
  // Pinned list ids, with no limit (Q-70).
  final List<String> homePins;
  // Lists taken off home's suggestions for good; a pin brings one back (Q-79).
  final List<String> homeRemoved;
  // The pinned lists as dragged on home, used on My order; other ids here mean
  // nothing (Q-75).
  final List<String> homeOrder;
  // Home list order (Q-108). The dial's is [listOrder].
  final HomeListOrder homeListOrder;
  // Whether a list's own Ticked items and Confirm before deleting count
  // (Q-117). Off, every list follows the general one; the lists keep their
  // own choices for when it is on again.
  final bool listsOwnTickedItems;
  final bool listsOwnConfirmDelete;
  final Set<ReminderLead> reminderLeads;
  // Minutes after midnight.
  final int reminderMorning;
  final bool listsOwnReminderLeads;

  ReminderSettings get reminders => ReminderSettings(
    leads: reminderLeads,
    morningMinutes: reminderMorning,
    listsOwnLeads: listsOwnReminderLeads,
  );

  // "HH:mm" for [minutes] after midnight, and back; null for anything else.
  static String morningWire(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  static int? morningOf(Object? wire) {
    if (wire is! String) {
      return null;
    }
    final RegExpMatch? match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(wire);
    if (match == null) {
      return null;
    }
    final int hour = int.parse(match.group(1)!);
    final int minute = int.parse(match.group(2)!);
    return hour < 24 && minute < 60 ? hour * 60 + minute : null;
  }

  // What [list] uses: its own choice while lists may have their own, else the
  // general one (Q-117).
  TickedItems tickedItemsFor(ListDefinition? list) {
    final String? own = list?.ownTickedItems;
    return listsOwnTickedItems && own != null
        ? TickedItems.of(own)
        : tickedItems;
  }

  bool confirmDeleteFor(ListDefinition? list) {
    final bool? own = list?.ownConfirmDelete;
    return listsOwnConfirmDelete && own != null ? own : confirmDelete;
  }

  // The order setting that sorts home's cards, or null on home's own My order.
  ListOrder? get homeSortedBy => switch (homeListOrder) {
    HomeListOrder.sameAsDial => listOrder,
    HomeListOrder.lastUsed => ListOrder.lastUsed,
    HomeListOrder.alphabetical => ListOrder.alphabetical,
    HomeListOrder.myOrder => null,
  };

  // A missing or malformed value gets its default, and a value of a newer
  // build is ignored, so a bad document never stops the app.
  factory AccountPreferences.fromJson(Map<String, Object?> json) {
    bool flag(String key, bool fallback) {
      final Object? value = json[key];
      return value is bool ? value : fallback;
    }

    List<String> ids(String key) {
      final Object? value = json[key];
      return value is List
          ? List.unmodifiable(value.whereType<String>())
          : const [];
    }

    final Object? notice = json[aiNoticeSeenKey];
    // An account from before Q-108: home had its own order when both had been
    // arranged (Q-75's split), and followed the dial otherwise.
    final HomeListOrder homeListOrder =
        HomeListOrder.maybeOf(json[homeListOrderKey]) ??
        (flag(homeArrangedKey, false) && flag(dialArrangedKey, false)
            ? HomeListOrder.myOrder
            : HomeListOrder.sameAsDial);
    return AccountPreferences(
      listOrder: ListOrder.of(json[listOrderKey]),
      myListOrder: ids(myListOrderKey),
      startScreen: StartScreen.of(json[startScreenKey]),
      tickedItems: TickedItems.of(json[tickedItemsKey]),
      confirmDelete: flag(confirmDeleteKey, false),
      showAiBar: flag(showAiBarKey, true),
      aiAutoApply: flag(aiAutoApplyKey, false),
      aiAskLevel: AiAskLevel.of(json[aiAskLevelKey]),
      aiAutoApplyOffered: flag(aiAutoApplyOfferedKey, false),
      aiNoticeSeen: notice is String ? notice : null,
      vibration: flag(vibrationKey, true),
      timeFormat: TimeFormat.of(json[timeFormatKey]),
      weekStart: WeekStart.of(json[weekStartKey]),
      homeContent: HomeContent.of(json[homeContentKey]),
      homeSuggestions: flag(homeSuggestionsKey, true),
      homePins: ids(homePinsKey),
      homeRemoved: ids(homeRemovedKey),
      homeOrder: ids(homeOrderKey),
      homeListOrder: homeListOrder,
      listsOwnTickedItems: flag(listsOwnTickedItemsKey, true),
      listsOwnConfirmDelete: flag(listsOwnConfirmDeleteKey, true),
      reminderLeads: Set.unmodifiable(
        ReminderLead.setOf(json[reminderLeadsKey]) ?? ReminderLead.defaults,
      ),
      reminderMorning:
          morningOf(json[reminderMorningKey]) ??
          ReminderSettings.defaultMorningMinutes,
      listsOwnReminderLeads: flag(listsOwnReminderLeadsKey, true),
    );
  }

  Map<String, Object?> toJson() => {
    listOrderKey: listOrder.wire,
    myListOrderKey: myListOrder,
    startScreenKey: startScreen.wire,
    tickedItemsKey: tickedItems.wire,
    confirmDeleteKey: confirmDelete,
    showAiBarKey: showAiBar,
    aiAutoApplyKey: aiAutoApply,
    aiAskLevelKey: aiAskLevel.wire,
    aiAutoApplyOfferedKey: aiAutoApplyOffered,
    aiNoticeSeenKey: ?aiNoticeSeen,
    vibrationKey: vibration,
    timeFormatKey: timeFormat.wire,
    weekStartKey: weekStart.wire,
    homeContentKey: homeContent.wire,
    homeSuggestionsKey: homeSuggestions,
    homePinsKey: homePins,
    homeRemovedKey: homeRemoved,
    homeOrderKey: homeOrder,
    homeListOrderKey: homeListOrder.wire,
    listsOwnTickedItemsKey: listsOwnTickedItems,
    listsOwnConfirmDeleteKey: listsOwnConfirmDelete,
    reminderLeadsKey: ReminderLead.wiresOf(reminderLeads),
    reminderMorningKey: morningWire(reminderMorning),
    listsOwnReminderLeadsKey: listsOwnReminderLeads,
  };

  @override
  bool operator ==(Object other) =>
      other is AccountPreferences &&
      other.listOrder == listOrder &&
      listEquals(other.myListOrder, myListOrder) &&
      other.startScreen == startScreen &&
      other.tickedItems == tickedItems &&
      other.confirmDelete == confirmDelete &&
      other.showAiBar == showAiBar &&
      other.aiAutoApply == aiAutoApply &&
      other.aiAskLevel == aiAskLevel &&
      other.aiAutoApplyOffered == aiAutoApplyOffered &&
      other.aiNoticeSeen == aiNoticeSeen &&
      other.vibration == vibration &&
      other.timeFormat == timeFormat &&
      other.weekStart == weekStart &&
      other.homeContent == homeContent &&
      other.homeSuggestions == homeSuggestions &&
      listEquals(other.homePins, homePins) &&
      listEquals(other.homeRemoved, homeRemoved) &&
      listEquals(other.homeOrder, homeOrder) &&
      other.homeListOrder == homeListOrder &&
      other.listsOwnTickedItems == listsOwnTickedItems &&
      other.listsOwnConfirmDelete == listsOwnConfirmDelete &&
      setEquals(other.reminderLeads, reminderLeads) &&
      other.reminderMorning == reminderMorning &&
      other.listsOwnReminderLeads == listsOwnReminderLeads;

  @override
  int get hashCode => Object.hashAll([
    listOrder,
    Object.hashAll(myListOrder),
    startScreen,
    tickedItems,
    confirmDelete,
    showAiBar,
    aiAutoApply,
    aiAskLevel,
    aiAutoApplyOffered,
    aiNoticeSeen,
    vibration,
    timeFormat,
    weekStart,
    homeContent,
    homeSuggestions,
    Object.hashAll(homePins),
    Object.hashAll(homeRemoved),
    Object.hashAll(homeOrder),
    homeListOrder,
    listsOwnTickedItems,
    listsOwnConfirmDelete,
    Object.hashAllUnordered(reminderLeads),
    reminderMorning,
    listsOwnReminderLeads,
  ]);
}

extension AccountPreferencesOf on BuildContext {
  // For handlers: the values now. Parts tested without the gate get the
  // defaults.
  AccountPreferences get accountPreferences =>
      read<AccountPreferencesCubit?>()?.state ?? const AccountPreferences();

  // For build methods: rebuilds when a value changes.
  AccountPreferences get watchAccountPreferences =>
      watch<AccountPreferencesCubit?>()?.state ?? const AccountPreferences();
}

// The account's stored preferences as the listener saw them: [data] is null
// when there is no document, and [fromCache] says the server has not
// confirmed it yet.
typedef AccountPreferencesSnapshot = ({
  Map<String, Object?>? data,
  bool fromCache,
});

// A change to one entry of a list kept as a set (homePins, homeRemoved),
// written as the entry alone (Firestore's arrayUnion or arrayRemove), so a pin
// or removal made on one phone while another was offline is not lost when the
// other's change arrives (T-22 unit 4, R2).
class PreferenceEntry {
  const PreferenceEntry(this.id, {required this.added});

  final String id;
  // Added if absent (arrayUnion), or taken out (arrayRemove).
  final bool added;

  // [ids] with these changes made, as the server makes them.
  static List<String> apply(Object? ids, Map<String, bool> changes) {
    final List<String> result = ids is List
        ? [
            for (final Object? id in ids)
              if (id is String) id,
          ]
        : [];
    changes.forEach((id, added) {
      if (!added) {
        result.removeWhere((each) => each == id);
      } else if (!result.contains(id)) {
        result.add(id);
      }
    });
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is PreferenceEntry && other.id == id && other.added == added;

  @override
  int get hashCode => Object.hash(id, added);

  @override
  String toString() => '${added ? '+' : '-'}$id';
}

// Where the account's preferences are kept (firestore_preferences.dart in
// the app).
abstract class AccountPreferencesSync {
  Stream<AccountPreferencesSnapshot> watch();

  // Stores [values] unless the account has preferences already; fails when
  // the server cannot be reached.
  Future<void> seed(Map<String, Object?> values);

  // Stores [changes] next to the other values; a [PreferenceEntry] value
  // adds or removes that one entry of the key's list. Completes when the server
  // has them, so offline it stays open while the change waits; fails when the
  // server refuses them.
  Future<void> write(Map<String, Object?> changes);
}

// Holds one user's account preferences (Q-48 A). A copy in shared_preferences
// is there on the first frame and offline. A phone that has not seen the
// account yet keeps its changes aside, so they neither hide the account's
// other values nor stop a seeding: once the server has answered, the account's
// values win over what the phone had, except for those changes. An account
// without a document is seeded once from the phone, which carries over the
// AI settings it kept before they synced.
//
// A change stays on top of the account's values until the server has confirmed
// it. Firestore takes a refused write back through the listener, which would
// silently undo the choice, and could turn auto-apply back on after it was turned
// off. So a refused change stays in force on this phone, is tried again at the
// next open, and [saveFailures] tells the app to say so.
//
// A listener error ends Firestore's stream for good, as when the rules or sign-in
// have a passing problem, and other phones' changes would stop arriving. So it
// listens again after each of [relistenDelays], quietly, and sends what is still
// unconfirmed once the server answers. Being offline is not such an error.
class AccountPreferencesCubit extends Cubit<AccountPreferences> {
  AccountPreferencesCubit(
    this.preferences,
    this.uid, {
    this.sync,
    this.relistenDelays = const [
      Duration(seconds: 5),
      Duration(seconds: 30),
      Duration(minutes: 2),
      Duration(minutes: 10),
    ],
  }) : _known = preferences.containsKey(mirrorKey(uid)),
       _pending = _readMap(preferences, pendingKey(uid)),
       _pendingEntries = _readEntries(preferences, uid),
       super(_read(preferences, uid)) {
    _listen();
    if (_known) {
      _resend();
    }
  }

  final SharedPreferences preferences;
  final String uid;
  final AccountPreferencesSync? sync;
  final List<Duration> relistenDelays;

  // These were per phone until T-21; the first account to see them takes them.
  static const String legacyAutoApplyKey = 'settings.aiAutoApply';
  static const String legacyAskLevelKey = 'settings.aiAskLevel';
  static const String legacyAutoApplyOfferedKey = 'ai.autoApplyAsked';
  static const String legacyNoticeSeenKey = 'ai.noticeSeen';

  static String mirrorKey(String uid) => 'preferences.$uid';
  static String pendingKey(String uid) => 'preferences.$uid.pending';
  static String pendingEntriesKey(String uid) =>
      'preferences.$uid.pendingEntries';

  StreamSubscription<AccountPreferencesSnapshot>? _subscription;
  Timer? _relisten;
  // Retries used since the server last answered.
  int _relistens = 0;
  // The listener has failed, and the server has not answered since.
  bool _listenFailed = false;
  // This phone has seen the account's values; changes go straight to it.
  bool _known;
  // Changes the server has not confirmed: made before that, on their way, or
  // refused.
  final Map<String, Object?> _pending;
  // The same for entries of set-like lists: key, then id and whether added, in
  // the order made.
  final Map<String, Map<String, bool>> _pendingEntries;
  bool _seeding = false;
  final StreamController<void> _saveFailures =
      StreamController<void>.broadcast();

  // The server refused a change. Offline is not a failure: the write waits.
  Stream<void> get saveFailures => _saveFailures.stream;

  // Sign-out clears the Firestore cache (Q-25 A); this copy goes with it. The
  // account's own document stays.
  static Future<void> forget(SharedPreferences preferences, String uid) async {
    await preferences.remove(mirrorKey(uid));
    await preferences.remove(pendingKey(uid));
    await preferences.remove(pendingEntriesKey(uid));
  }

  // [values] with the entry changes made on top, as the server will have them.
  static Map<String, Object?> _withEntries(
    Map<String, Object?> values,
    Map<String, Map<String, bool>> entries,
  ) => {
    ...values,
    for (final MapEntry<String, Map<String, bool>> key in entries.entries)
      key.key: PreferenceEntry.apply(values[key.key], key.value),
  };

  static Map<String, Map<String, bool>> _readEntries(
    SharedPreferences preferences,
    String uid,
  ) => {
    for (final MapEntry<String, Object?> key in _readMap(
      preferences,
      pendingEntriesKey(uid),
    ).entries)
      if (key.value case final Map<Object?, Object?> entries)
        key.key: {
          for (final MapEntry<Object?, Object?> entry in entries.entries)
            if ((entry.key, entry.value) case (
              final String id,
              final bool added,
            ))
              id: added,
        },
  };

  static AccountPreferences _read(SharedPreferences preferences, String uid) {
    final Map<String, Map<String, bool>> entries = _readEntries(
      preferences,
      uid,
    );
    if (preferences.containsKey(mirrorKey(uid))) {
      return AccountPreferences.fromJson(
        _withEntries({
          ..._readMap(preferences, mirrorKey(uid)),
          ..._readMap(preferences, pendingKey(uid)),
        }, entries),
      );
    }
    return AccountPreferences.fromJson(
      _withEntries({
        AccountPreferences.aiAutoApplyKey: preferences.getBool(
          legacyAutoApplyKey,
        ),
        AccountPreferences.aiAskLevelKey: preferences.getString(
          legacyAskLevelKey,
        ),
        AccountPreferences.aiAutoApplyOfferedKey: preferences.getBool(
          legacyAutoApplyOfferedKey,
        ),
        AccountPreferences.aiNoticeSeenKey: preferences.getString(
          legacyNoticeSeenKey,
        ),
        ..._readMap(preferences, pendingKey(uid)),
      }, entries),
    );
  }

  static Map<String, Object?> _readMap(
    SharedPreferences preferences,
    String key,
  ) {
    final String? stored = preferences.getString(key);
    if (stored == null) {
      return {};
    }
    try {
      final Object? decoded = jsonDecode(stored);
      return decoded is Map<String, dynamic> ? decoded : {};
    } on FormatException {
      return {};
    }
  }

  static void _log(String what, Object error) {
    developer.log('$what: $error', name: 'AccountPreferences');
  }

  void _listen() {
    _subscription = sync?.watch().listen(
      _onSnapshot,
      onError: _onListenError,
      cancelOnError: true,
    );
  }

  void _onListenError(Object error) {
    _log('listener', error);
    _listenFailed = true;
    if (_relistens < relistenDelays.length) {
      _relisten = Timer(relistenDelays[_relistens], _listen);
      _relistens++;
    }
  }

  void _onSnapshot(AccountPreferencesSnapshot snapshot) {
    // A copy from the cache can come just before the same error again.
    final bool recovered = _listenFailed && !snapshot.fromCache;
    if (!snapshot.fromCache) {
      _relistens = 0;
      _listenFailed = false;
    }
    final Map<String, Object?>? data = snapshot.data;
    if (data != null) {
      unawaited(_onAccountValues(data, recovered: recovered));
    } else if (!snapshot.fromCache) {
      unawaited(_seed());
    }
  }

  Future<void> _onAccountValues(
    Map<String, Object?> data, {
    required bool recovered,
  }) async {
    final bool firstSeen = !_known;
    _known = true;
    if (!isClosed) {
      emit(
        AccountPreferences.fromJson(
          _withEntries({...data, ..._pending}, _pendingEntries),
        ),
      );
    }
    if (firstSeen || recovered) {
      _resend();
    }
    await _saveMirror();
    await preferences.remove(legacyAutoApplyKey);
    await preferences.remove(legacyAskLevelKey);
    await preferences.remove(legacyAutoApplyOfferedKey);
    await preferences.remove(legacyNoticeSeenKey);
  }

  // The listener reports the stored document when this has written it. A
  // failure tries again at the next open, like the starter lists.
  Future<void> _seed() async {
    if (_seeding) {
      return;
    }
    _seeding = true;
    try {
      await sync?.seed(state.toJson());
    } on Object catch (error) {
      _log('seed', error);
    } finally {
      _seeding = false;
    }
  }

  // Key by key, so one the server refuses does not hold back the others.
  void _resend() {
    for (final MapEntry<String, Object?> change in _pending.entries) {
      _send({change.key: change.value});
    }
    _pendingEntries.forEach((key, entries) {
      entries.forEach((id, added) {
        _send({key: PreferenceEntry(id, added: added)});
      });
    });
  }

  void _send(Map<String, Object?> changes) {
    unawaited(
      sync
          ?.write(changes)
          .then(
            (_) => _onConfirmed(changes),
            onError: (Object error) => _onRefused(changes, error),
          ),
    );
  }

  // Unless the person has chosen again since. Compared as JSON, since a value
  // can be a list.
  bool _isPending(String key, Object? value) {
    if (value is PreferenceEntry) {
      final Map<String, bool>? entries = _pendingEntries[key];
      return entries != null && entries[value.id] == value.added;
    }
    return _pending.containsKey(key) &&
        jsonEncode(_pending[key]) == jsonEncode(value);
  }

  Future<void> _onConfirmed(Map<String, Object?> changes) async {
    if (isClosed) {
      return;
    }
    changes.forEach((key, value) {
      if (!_isPending(key, value)) {
        return;
      }
      if (value is PreferenceEntry) {
        final Map<String, bool> entries = _pendingEntries[key]!
          ..remove(value.id);
        if (entries.isEmpty) {
          _pendingEntries.remove(key);
        }
      } else {
        _pending.remove(key);
      }
    });
    await _savePending();
  }

  void _onRefused(Map<String, Object?> changes, Object error) {
    _log('write', error);
    if (!isClosed && changes.keys.any((k) => _isPending(k, changes[k]))) {
      _saveFailures.add(null);
    }
  }

  Future<void> _savePending() async {
    if (_pending.isEmpty) {
      await preferences.remove(pendingKey(uid));
    } else {
      await preferences.setString(pendingKey(uid), jsonEncode(_pending));
    }
    if (_pendingEntries.isEmpty) {
      await preferences.remove(pendingEntriesKey(uid));
    } else {
      await preferences.setString(
        pendingEntriesKey(uid),
        jsonEncode(_pendingEntries),
      );
    }
  }

  Future<void> _saveMirror() async {
    await preferences.setString(mirrorKey(uid), jsonEncode(state.toJson()));
  }

  Future<void> _change(String key, Object value) async {
    if (isClosed) {
      return;
    }
    emit(AccountPreferences.fromJson({...state.toJson(), key: value}));
    _pending[key] = value;
    final bool send = _known && sync != null;
    if (send) {
      _send({key: value});
    }
    await _savePending();
    if (send) {
      await _saveMirror();
    }
  }

  // Adds or removes entries of a set-like list, each written on its own.
  Future<void> _changeEntries(String key, List<PreferenceEntry> changes) async {
    if (isClosed || changes.isEmpty) {
      return;
    }
    final Map<String, bool> pending = _pendingEntries.putIfAbsent(
      key,
      () => {},
    );
    for (final PreferenceEntry change in changes) {
      // Latest last, so an id added again goes to the end.
      pending
        ..remove(change.id)
        ..[change.id] = change.added;
    }
    final Map<String, Object?> now = state.toJson();
    emit(
      AccountPreferences.fromJson({
        ...now,
        key: PreferenceEntry.apply(now[key], {
          for (final PreferenceEntry change in changes) change.id: change.added,
        }),
      }),
    );
    final bool send = _known && sync != null;
    if (send) {
      for (final PreferenceEntry change in changes) {
        _send({key: change});
      }
    }
    await _savePending();
    if (send) {
      await _saveMirror();
    }
  }

  // Ids in [ids] whose list is gone, to take out with a change.
  static List<PreferenceEntry> _gone(
    List<String> ids,
    Iterable<String> existing,
  ) {
    final Set<String> lists = existing.toSet();
    return [
      for (final String id in ids)
        if (!lists.contains(id)) PreferenceEntry(id, added: false),
    ];
  }

  // Dial list order (Q-108; was List order).
  Future<void> setListOrder(ListOrder order) =>
      _change(AccountPreferences.listOrderKey, order.wire);

  // Home list order (Q-108). My order shows home's last dragged order, any
  // pinned list not in it after.
  Future<void> setHomeListOrder(HomeListOrder order) =>
      _change(AccountPreferences.homeListOrderKey, order.wire);

  // The Same as dial switch (Q-108, a switch since the owner's note of
  // 2026-11-09). Off, home starts from what it showed: the dial's choice, and
  // on the dial's My order a copy of [dialOrder], every list in the dial's
  // order, as home's own.
  Future<void> setHomeFollowsDial(
    bool follow, {
    List<String> dialOrder = const [],
  }) async {
    if (follow) {
      return setHomeListOrder(HomeListOrder.sameAsDial);
    }
    if (state.listOrder == ListOrder.myOrder) {
      await _change(AccountPreferences.homeOrderKey, dialOrder);
    }
    await setHomeListOrder(HomeListOrder.ofDial(state.listOrder));
  }

  Future<void> setMyListOrder(List<String> listIds) =>
      _change(AccountPreferences.myListOrderKey, listIds);

  Future<void> setStartScreen(StartScreen screen) =>
      _change(AccountPreferences.startScreenKey, screen.wire);

  Future<void> setTickedItems(TickedItems ticked) =>
      _change(AccountPreferences.tickedItemsKey, ticked.wire);

  Future<void> setConfirmDelete(bool value) =>
      _change(AccountPreferences.confirmDeleteKey, value);

  Future<void> setReminderLeads(Set<ReminderLead> leads) => _change(
    AccountPreferences.reminderLeadsKey,
    ReminderLead.wiresOf(leads),
  );

  Future<void> setReminderMorning(int minutes) => _change(
    AccountPreferences.reminderMorningKey,
    AccountPreferences.morningWire(minutes),
  );

  Future<void> setListsOwnReminderLeads(bool value) =>
      _change(AccountPreferences.listsOwnReminderLeadsKey, value);

  Future<void> setListsOwnTickedItems(bool value) =>
      _change(AccountPreferences.listsOwnTickedItemsKey, value);

  Future<void> setListsOwnConfirmDelete(bool value) =>
      _change(AccountPreferences.listsOwnConfirmDeleteKey, value);

  Future<void> setShowAiBar(bool value) =>
      _change(AccountPreferences.showAiBarKey, value);

  Future<void> setAiAutoApply(bool value) =>
      _change(AccountPreferences.aiAutoApplyKey, value);

  Future<void> setAiAskLevel(AiAskLevel level) =>
      _change(AccountPreferences.aiAskLevelKey, level.wire);

  Future<void> setAiAutoApplyOffered() =>
      _change(AccountPreferences.aiAutoApplyOfferedKey, true);

  Future<void> setAiNoticeSeen(String noticeId) =>
      _change(AccountPreferences.aiNoticeSeenKey, noticeId);

  Future<void> setVibration(bool value) =>
      _change(AccountPreferences.vibrationKey, value);

  Future<void> setTimeFormat(TimeFormat format) =>
      _change(AccountPreferences.timeFormatKey, format.wire);

  Future<void> setWeekStart(WeekStart start) =>
      _change(AccountPreferences.weekStartKey, start.wire);

  Future<void> setHomeContent(HomeContent content) =>
      _change(AccountPreferences.homeContentKey, content.wire);

  Future<void> setHomeSuggestions(bool value) =>
      _change(AccountPreferences.homeSuggestionsKey, value);

  // A pin also undoes a removal (Q-79). It changes no setting: the new card
  // takes its place in Home list order, last on My order (Q-108). [keepPlace]
  // is for tapping an unfilled pin again, which puts the card back where it
  // was (Q-65). [existing] is every list's id.
  Future<void> pinToHome(
    String listId, {
    required Iterable<String> existing,
    bool keepPlace = false,
  }) async {
    final AccountPreferences before = state;
    await _changeEntries(AccountPreferences.homePinsKey, [
      ..._gone(before.homePins, existing),
      if (!before.homePins.contains(listId))
        PreferenceEntry(listId, added: true),
    ]);
    if (before.homeRemoved.contains(listId)) {
      await _changeEntries(AccountPreferences.homeRemovedKey, [
        ..._gone(before.homeRemoved, existing),
        PreferenceEntry(listId, added: false),
      ]);
    }
    if (!keepPlace && before.homeOrder.contains(listId)) {
      await _change(
        AccountPreferences.homeOrderKey,
        keepExistingIds(
          before.homeOrder,
          existing,
        ).where((id) => id != listId).toList(),
      );
    }
  }

  // Its place in homeOrder stays until the next pin or drag, for [pinToHome]'s
  // keepPlace.
  Future<void> unpinFromHome(String listId) => _changeEntries(
    AccountPreferences.homePinsKey,
    [PreferenceEntry(listId, added: false)],
  );

  Future<void> removeFromHome(
    String listId, {
    required Iterable<String> existing,
  }) => _changeEntries(AccountPreferences.homeRemovedKey, [
    ..._gone(state.homeRemoved, existing),
    if (!state.homeRemoved.contains(listId))
      PreferenceEntry(listId, added: true),
  ]);

  Future<void> undoRemoveFromHome(String listId) => _changeEntries(
    AccountPreferences.homeRemovedKey,
    [PreferenceEntry(listId, added: false)],
  );

  // A drag on home (Q-108, choice A): [pinnedIds] is the new order of the
  // pinned lists. Home list order becomes My order; the dial stays as it is.
  Future<void> arrangedOnHome(List<String> pinnedIds) async {
    await _change(AccountPreferences.homeOrderKey, pinnedIds);
    await _change(
      AccountPreferences.homeListOrderKey,
      HomeListOrder.myOrder.wire,
    );
  }

  // A drag on the dial (Q-49): Dial list order is My order from the first
  // drag. Home follows it only on Same as dial.
  Future<void> arrangedOnDial(List<String> listIds) async {
    await _change(AccountPreferences.myListOrderKey, listIds);
    await _change(AccountPreferences.listOrderKey, ListOrder.myOrder.wire);
  }

  @override
  Future<void> close() async {
    _relisten?.cancel();
    await _subscription?.cancel();
    await _saveFailures.close();
    return super.close();
  }
}
