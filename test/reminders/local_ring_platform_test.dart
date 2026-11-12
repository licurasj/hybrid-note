import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Color;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hybrid_note/reminders/local_ring_platform.dart';
import 'package:hybrid_note/reminders/reminder_background.dart'
    show reminderDoneAction;
import 'package:hybrid_note/reminders/reminder_planner.dart';
import 'package:hybrid_note/reminders/reminder_settings.dart';
import 'package:hybrid_note/reminders/ring_booker.dart';
import 'package:hybrid_note/reminders/ring_logo.dart';

// T-13 unit 9: how a ring looks and sounds on Android.
void main() {
  const RingText text = (
    title: 'Call Ann',
    body: '15:30',
    subText: 'Tasks',
    color: 0xFF00A63E,
    done: 'Done',
  );

  test('a ring is tinted in its list colour, on the chime channel, with only '
      'Done', () {
    final Uint8List logo = Uint8List.fromList([1, 2, 3]);
    final AndroidNotificationDetails details = LocalRingPlatform.details(
      text,
      channelName: 'Reminders',
      logo: logo,
    );
    expect(details.channelId, 'reminders_chime');
    expect(details.channelName, 'Reminders');
    expect(details.color, const Color(0xFF00A63E));
    expect(details.subText, 'Tasks');
    expect(details.showWhen, isFalse);
    expect(details.category, AndroidNotificationCategory.reminder);
    expect(details.importance, Importance.high);
    final AndroidNotificationSound? sound = details.sound;
    expect(sound, isA<RawResourceAndroidNotificationSound>());
    expect(sound!.sound, 'reminder_chime');
    expect(details.largeIcon, isA<ByteArrayAndroidBitmap>());
    expect((details.largeIcon! as ByteArrayAndroidBitmap).data, logo);
    expect(details.actions, hasLength(1));
    expect(details.actions!.single.id, reminderDoneAction);
    expect(details.actions!.single.title, 'Done');
  });

  test('without a logo there is no large icon', () {
    expect(
      LocalRingPlatform.details(text, channelName: 'Reminders').largeIcon,
      isNull,
    );
  });

  test('a list with nothing to tick gets no Done (F9)', () {
    final AndroidNotificationDetails details = LocalRingPlatform.details((
      title: 'Read',
      body: '15:30',
      subText: 'Journal',
      color: 0xFF00A63E,
      done: null,
    ), channelName: 'Reminders');
    expect(details.actions, isEmpty);
  });

  test('Done cancels every lead of the occurrence by its id (F10)', () {
    const RingPayload payload = RingPayload(
      key: 'k',
      listId: 'tasks',
      itemId: 'a',
      itemDate: 'd',
      dueMs: 1000,
      fingerprint: 'f',
    );
    final List<int> ids = LocalRingPlatform.occurrenceIds(payload);
    for (final ReminderLead lead in ReminderLead.values) {
      expect(
        ids,
        contains(RingBooker.idOf(PlannedRing.keyOf('tasks', 'a', 1000, lead))),
      );
    }
    expect(
      ids,
      isNot(
        contains(
          RingBooker.idOf(
            PlannedRing.keyOf('tasks', 'a', 2000, ReminderLead.atTime),
          ),
        ),
      ),
    );
  });

  test('the old channel is deleted and the look names the new channel', () {
    expect(LocalRingPlatform.oldChannelIds, ['reminders']);
    expect(
      LocalRingPlatform.oldChannelIds,
      isNot(contains(LocalRingPlatform.channelId)),
    );
    expect(
      LocalRingPlatform(channelName: 'Reminders').look,
      LocalRingPlatform.channelId,
    );
  });

  test('the logo is a PNG of the mark in the list colour on a clear ground, '
      'one per colour', () async {
    final Uint8List png = await RingLogo.png(0xFF00A63E);
    expect(png.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(png.length, lessThan(40 * 1024));
    expect(identical(await RingLogo.png(0xFF00A63E), png), isTrue);

    final ui.Codec codec = await ui.instantiateImageCodec(png);
    final ui.Image image = (await codec.getNextFrame()).image;
    expect(image.width, RingLogo.size);
    final ByteData data = (await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    ))!;
    int at(int x, int y) => data.getUint32((y * RingLogo.size + x) * 4);
    // The logo's ground is clear; the note's middle is the list colour.
    expect(at(0, 0) & 0xFF, 0);
    expect(at(RingLogo.size ~/ 2, 8) & 0xFF, 0);
    expect(at(60, 130), 0x00A63EFF);
    // No white anywhere: every visible pixel, the logo's fade included, is
    // the list colour; only its alpha changes (owner, 1397344 on the phone).
    int faded = 0;
    for (int y = 0; y < RingLogo.size; y++) {
      for (int x = 0; x < RingLogo.size; x++) {
        final int pixel = at(x, y);
        final int alpha = pixel & 0xFF;
        if (alpha < 24) {
          continue;
        }
        if (alpha < 230) {
          faded++;
        }
        final List<int> rgb = [
          pixel >> 24 & 0xFF,
          pixel >> 16 & 0xFF,
          pixel >> 8 & 0xFF,
        ];
        expect(rgb, [
          for (final int c in [0x00, 0xA6, 0x3E])
            inInclusiveRange(c - 12, c + 12),
        ], reason: 'pixel $x,$y alpha $alpha');
      }
    }
    expect(faded, greaterThan(50));
  });
  // T-13 unit 12: the summary of rings missed while the phone was off goes
  // with its last ring.
  group('loneMissedSummary', () {
    const int summary = LocalRingPlatform.missedSummaryId;
    const String missed = LocalRingPlatform.missedGroup;

    test('a summary with no missed ring left is lone', () {
      expect(
        LocalRingPlatform.loneMissedSummary([
          (id: summary, group: missed),
          (id: 7, group: null), // a normal ring
        ]),
        isTrue,
      );
    });

    test('a summary with a missed ring left stays', () {
      expect(
        LocalRingPlatform.loneMissedSummary([
          (id: summary, group: missed),
          (id: 8, group: missed),
        ]),
        isFalse,
      );
    });

    test('no summary, nothing to drop', () {
      expect(
        LocalRingPlatform.loneMissedSummary([(id: 8, group: missed)]),
        isFalse,
      );
      expect(LocalRingPlatform.loneMissedSummary(const []), isFalse);
    });
  });
}
