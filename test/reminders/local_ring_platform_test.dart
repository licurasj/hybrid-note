import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Color;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hybrid_note/reminders/local_ring_platform.dart';
import 'package:hybrid_note/reminders/reminder_background.dart'
    show reminderDoneAction;
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

  test('the logo is a PNG in the list colour, white mark kept, one per '
      'colour', () async {
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
    // A corner is outside the disc; the ground near the edge is the list
    // colour; the note's middle is the logo's white.
    expect(at(0, 0) & 0xFF, 0);
    expect(at(RingLogo.size ~/ 2, 8), 0x00A63EFF);
    expect(at(60, 130) >> 8, 0xFFFFFF);
  });
}
