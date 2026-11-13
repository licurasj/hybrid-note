import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hybrid_note/app/account_preferences.dart';
import 'package:hybrid_note/app/app_settings.dart';
import 'package:hybrid_note/lists/builtin_templates.dart';
import 'package:hybrid_note/lists/list_item.dart';
import 'package:hybrid_note/reminders/reminder_host.dart';
import 'package:hybrid_note/reminders/reminder_settings.dart';
import 'package:hybrid_note/reminders/ring_booker.dart';
import 'package:hybrid_note/reminders/ring_fence.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_auth.dart';
import '../support/firestore_store.dart';
import 'ring_booker_test.dart' show FakeRingPlatform;

// T-13 unit 10, F15: ReminderHost books this phone's rings from the lists
// and books again on resume and on a setting change; Ring on this phone off
// books nothing and takes back what was booked.
void main() {
  // A task three days ahead, stored as its UTC moment (F8).
  final DateTime due = DateTime.now()
      .toUtc()
      .add(const Duration(days: 3))
      .copyWith(second: 0, millisecond: 0, microsecond: 0);

  Future<FakeRingPlatform> pumpHost(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Asked before, so no permission sheet comes up.
    SharedPreferences.setMockInitialValues({
      AppSettingsCubit.remindersAskedKey: true,
    });
    final DateTime at = DateTime.utc(2026, 11, 1);
    final store = await widgetTestStore(
      tester,
      items: [
        ListItem(
          id: 'dentist',
          listId: BuiltinTemplates.tasksId,
          values: {
            'title': 'Dentist',
            'done': false,
            'reminderAt': due.toIso8601String(),
          },
          createdAt: at,
          updatedAt: at,
        ),
      ],
    );
    final FakeRingPlatform platform = FakeRingPlatform();
    await tester.pumpWidget(
      await testApp(
        auth: FakeAuthService(user: testUser),
        openStore: (_) => store,
        ringBooker: RingBooker(platform, fence: MemoryRingFence()),
      ),
    );
    await settle(tester);
    await waitForBooking(tester);
    return platform;
  }

  BuildContext host(WidgetTester tester) =>
      tester.element(find.byType(ReminderHost));

  testWidgets('books the reminder and starts the background check', (
    tester,
  ) async {
    final FakeRingPlatform platform = await pumpHost(tester);
    expect(platform.checking, isTrue);
    expect(platform.rings.values.map((r) => r.payload.itemId), ['dentist']);
    expect(platform.rings.values.single.at, due);
  });

  testWidgets('coming back to the front books what is missing again', (
    tester,
  ) async {
    final FakeRingPlatform platform = await pumpHost(tester);
    // The system dropped the ring meanwhile.
    platform.rings.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await waitForBooking(tester);
    expect(platform.rings.values.map((r) => r.payload.itemId), ['dentist']);
  });

  testWidgets('a reminder setting change books the new leads', (tester) async {
    final FakeRingPlatform platform = await pumpHost(tester);
    await host(tester).read<AccountPreferencesCubit>().setReminderLeads({
      ReminderLead.atTime,
      ReminderLead.minutes10,
    });
    await waitForBooking(tester);
    expect(platform.rings.values.map((r) => r.at).toSet(), {
      due,
      due.subtract(const Duration(minutes: 10)),
    });
  });

  testWidgets('Ring on this phone off books nothing and cancels', (
    tester,
  ) async {
    final FakeRingPlatform platform = await pumpHost(tester);
    expect(platform.rings, isNotEmpty);
    await host(tester).read<AppSettingsCubit>().setRingOnThisPhone(false);
    await waitForBooking(tester);
    expect(platform.rings, isEmpty);
    expect(platform.calls.last, startsWith('cancel'));

    // A list change while it is off still books nothing.
    platform.calls.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await waitForBooking(tester);
    expect(platform.calls.where((c) => c.startsWith('book')), isEmpty);

    await host(tester).read<AppSettingsCubit>().setRingOnThisPhone(true);
    await waitForBooking(tester);
    expect(platform.rings.values.map((r) => r.payload.itemId), ['dentist']);
  });
}

// The settle delay, then the booker's work.
Future<void> waitForBooking(WidgetTester tester) async {
  await tester.pump(ReminderHost.settle + const Duration(milliseconds: 50));
  await settle(tester);
}
