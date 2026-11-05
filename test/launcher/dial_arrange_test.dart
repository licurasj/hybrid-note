import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/app_colors.dart';
import 'package:hybrid_note/launcher/arrange_sway.dart';
import 'package:hybrid_note/launcher/dial_launcher.dart';
import 'package:hybrid_note/launcher/launcher_geometry.dart';
import 'package:hybrid_note/launcher/radial_launcher.dart';

// Arranging the lists on the dial (T-21 unit 6, Q-49).

const LauncherConfig _config = LauncherConfig();
final double _step =
    _config.dialStepDegrees * _config.dialArrangeSpread * math.pi / 180;

final Finder _arrange = find.byKey(const ValueKey('launcher-arrange-prompt'));
final Finder _move = find.byKey(const ValueKey('launcher-move-prompt'));
final Finder _area = find.byKey(const ValueKey('launcher-arrange-area'));
final Finder _hubDisc = find.byKey(const ValueKey('launcher-hub'));

final Finder _arrangePill = find.descendant(
  of: _arrange,
  matching: find.byType(Container),
);

List<LauncherNote> _notes(int count) => [
  for (int i = 0; i < count; i++)
    LauncherNote(
      id: 'n$i',
      label: 'Note $i',
      icon: Icons.list,
      color: Colors.blue,
      semanticsLabel: 'Note $i',
    ),
];

class _Harness {
  final List<String> log = [];
  late ValueNotifier<List<LauncherNote>> lists;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  int count = 4,
  bool inList = false,
  bool reduceMotion = false,
  bool canArrange = true,
  bool haptics = true,
  Offset? hubPosition,
  Size size = const Size(412, 900),
}) async {
  final _Harness h = _Harness()..lists = ValueNotifier(_notes(count));
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size, disableAnimations: reduceMotion),
        child: Scaffold(
          body: ValueListenableBuilder<List<LauncherNote>>(
            valueListenable: h.lists,
            builder: (context, value, _) => DialLauncher(
              notes: value,
              hubPosition: hubPosition,
              haptics: haptics,
              onOpen: (note) => h.log.add('open ${note.id}'),
              onEdit: (note) => h.log.add('edit ${note.id}'),
              onNew: () => h.log.add('new'),
              onHome: inList ? () => h.log.add('home') : null,
              onHubMoved: (_) => h.log.add('moved'),
              onOrderChanged: canArrange
                  ? (ids) => h.log.add('order ${ids.join(',')}')
                  : null,
            ),
          ),
        ),
      ),
    ),
  );
  return h;
}

Offset _hub(WidgetTester tester) => tester.getCenter(_hubDisc);

double _diagonal(WidgetTester tester) {
  final Offset hub = _hub(tester);
  return math.atan2(hub.dy, -hub.dx);
}

Offset _at(WidgetTester tester, double angle, double radius) =>
    _hub(tester) + Offset(math.cos(angle), -math.sin(angle)) * radius;

// Where list number [i] (from 0) stands, at rest in the arrange state.
Offset _list(WidgetTester tester, int i, {double radius = 170}) =>
    _at(tester, _diagonal(tester) + i * _step, radius);

Future<void> _steps(
  WidgetTester tester,
  TestGesture gesture,
  Offset from,
  Offset to,
) async {
  for (int i = 1; i <= 8; i++) {
    await gesture.moveTo(Offset.lerp(from, to, i / 8)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<TestGesture> _holdForPrompts(WidgetTester tester) async {
  final TestGesture gesture = await tester.startGesture(_hub(tester));
  for (int i = 0; i < 200 && _arrange.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  await tester.pump(const Duration(milliseconds: 300));
  return gesture;
}

Future<void> _openArranging(WidgetTester tester) async {
  final Offset hub = _hub(tester);
  final TestGesture gesture = await _holdForPrompts(tester);
  await _steps(tester, gesture, hub, tester.getCenter(_arrange));
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 400));
  expect(_area, findsOneWidget);
}

// Long enough for a resting finger to pick a list up.
final Duration _rest = _config.dialPickUpDelay + const Duration(milliseconds: 50);

Future<void> _drag(WidgetTester tester, int from, int to) async {
  final Offset start = _list(tester, from);
  final TestGesture gesture = await tester.startGesture(start);
  await tester.pump(_rest);
  await _steps(tester, gesture, start, _list(tester, to));
  await tester.pump(const Duration(milliseconds: 100));
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 300));
}

// The tabs' paint area, to see them move.
Rect _tab(WidgetTester tester, int index) =>
    tester.getRect(find.byKey(ValueKey('dial-entry-$index')));

void main() {
  group('the prompt', () {
    testWidgets('resting on the hub offers Arrange beside Move', (
      tester,
    ) async {
      await _pump(tester);
      await _holdForPrompts(tester);
      expect(_arrange, findsOneWidget);
      expect(_move, findsOneWidget);
    });

    testWidgets('not with one list, and not without a place to save', (
      tester,
    ) async {
      await _pump(tester, count: 1);
      final TestGesture gesture = await tester.startGesture(_hub(tester));
      for (int i = 0; i < 160; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(_move, findsOneWidget);
      expect(_arrange, findsNothing);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));

      await _pump(tester, canArrange: false);
      final TestGesture again = await tester.startGesture(_hub(tester));
      for (int i = 0; i < 160; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(_move, findsOneWidget);
      expect(_arrange, findsNothing);
      await again.up();
    });

    testWidgets('it starts dark and fills towards the finger, and lets go', (
      tester,
    ) async {
      await _pump(tester);
      final Offset hub = _hub(tester);
      final TestGesture gesture = await _holdForPrompts(tester);
      Color fill() =>
          (tester.widget<Container>(_arrangePill).decoration! as BoxDecoration)
              .color!;
      final Color dark = AppColors.neutrals(Brightness.light).promptDark;
      expect(fill(), dark);

      final Offset target = tester.getCenter(_arrange);
      await _steps(tester, gesture, hub, Offset.lerp(hub, target, 0.5)!);
      expect(fill(), isNot(dark));
      await _steps(tester, gesture, Offset.lerp(hub, target, 0.5)!, target);
      expect(fill(), AppColors.appBlue);

      // Back away and let go: nothing happens (law rule 4).
      await _steps(tester, gesture, target, hub);
      expect(fill(), dark);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_area, findsNothing);
    });

    testWidgets('going to Arrange does not pick the hub up', (tester) async {
      final _Harness h = await _pump(tester);
      await _openArranging(tester);
      expect(h.log, isEmpty);
      expect(_hub(tester), isNotNull);
    });

    testWidgets('both prompts fit at every corner, clear of each other', (
      tester,
    ) async {
      for (final Size size in const [Size(360, 640), Size(412, 900)]) {
        for (final Offset corner in const [
          Offset(0.1, 0.1),
          Offset(0.9, 0.1),
          Offset(0.1, 0.9),
          Offset(0.9, 0.9),
        ]) {
          await _pump(tester, hubPosition: corner, size: size);
          final Offset hub = _hub(tester);
          final TestGesture gesture = await _holdForPrompts(tester);
          final Rect arrange = tester.getRect(_arrangePill);
          final Rect move = tester.getRect(
            find.descendant(of: _move, matching: find.byType(Container)),
          );
          final Rect screen = Offset.zero & size;
          final String where = '$size $corner';
          expect(
            arrange.left,
            greaterThanOrEqualTo(screen.left),
            reason: where,
          );
          expect(arrange.right, lessThanOrEqualTo(screen.right), reason: where);
          expect(arrange.top, greaterThanOrEqualTo(screen.top), reason: where);
          expect(
            arrange.bottom,
            lessThanOrEqualTo(screen.bottom),
            reason: where,
          );
          expect(move.left, greaterThanOrEqualTo(screen.left), reason: where);
          expect(move.right, lessThanOrEqualTo(screen.right), reason: where);
          expect(arrange.overlaps(move), isFalse, reason: where);
          // The way from the hub to Arrange stays clear of Move.
          for (int i = 0; i <= 20; i++) {
            final Offset p = Offset.lerp(hub, arrange.center, i / 20)!;
            expect(move.contains(p), isFalse, reason: where);
          }
          await gesture.up();
          await tester.pump(const Duration(milliseconds: 300));
        }
      }
    });
  });

  group('the selected list near the screen edge', () {
    // A tab's end, from its disc, which stands a fixed way in from it.
    double? reach(WidgetTester tester, int index) {
      final Finder disc = find.byKey(ValueKey('dial-disc-$index'));
      if (disc.evaluate().isEmpty) {
        return null;
      }
      final Rect rect = tester.getRect(disc);
      return (rect.center - _hub(tester)).distance + 18 + rect.width / 2;
    }

    for (final Size size in const [Size(412, 900), Size(320, 640)]) {
      final String name = '${size.width.toInt()} x ${size.height.toInt()}';

      testWidgets('normal dial, $name: longest but for a list at rest', (
        tester,
      ) async {
        await _pump(tester, count: 14, size: size);
        final Offset hub = _hub(tester);
        final double half = hub.distance / 2;
        final double far = 24 + (half - 24) * _config.dialFarLength;
        final TestGesture gesture = await tester.startGesture(hub);
        await tester.pump(const Duration(milliseconds: 300));
        for (double t = 0.05; t <= 0.95; t += 0.05) {
          final double angle = math.pi / 2 + (math.pi / 2) * t;
          await gesture.moveTo(_at(tester, angle, half * 0.6));
          await tester.pump(const Duration(milliseconds: 500));
          int? selected;
          double top = 0;
          for (int i = 0; i < 16; i++) {
            final Finder disc = find.byKey(ValueKey('dial-disc-$i'));
            if (disc.evaluate().isNotEmpty &&
                tester.getSize(disc).width > 35.5) {
              selected = i;
              top = reach(tester, i)!;
            }
          }
          if (selected == null) {
            continue;
          }
          for (int i = 1; i < 15; i++) {
            final double? other = reach(tester, i);
            if (i == selected || other == null) {
              continue;
            }
            // Only a list no longer than at rest may stand past the selected.
            if (other > top + 1) {
              expect(other, lessThanOrEqualTo(far + 1), reason: 'list $i at $t');
            }
          }
          // Never off the screen.
          final Rect tab = _tab(tester, selected);
          expect(tab.left, greaterThanOrEqualTo(-1));
          expect(tab.top, greaterThanOrEqualTo(-1));
        }
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 300));
      });

      testWidgets('arranging, $name: the held list is longer than at rest', (
        tester,
      ) async {
        await _pump(tester, count: 14, size: size);
        await _openArranging(tester);
        for (final int i in const [-1, 0, 1, 2]) {
          final int entry = i + 1 < 1 ? 1 : i + 1;
          final double before = reach(tester, entry)!;
          final Offset start = _list(tester, entry - 1);
          final TestGesture gesture = await tester.startGesture(start);
          await tester.pump(_rest);
          await tester.pump(const Duration(milliseconds: 400));
          expect(reach(tester, entry)!, greaterThan(before + 8));
          for (int other = 1; other < 8; other++) {
            final double? length = reach(tester, other);
            if (other != entry && length != null) {
              expect(length, lessThanOrEqualTo(reach(tester, entry)! + 1));
            }
          }
          await gesture.up();
          await tester.pump(const Duration(milliseconds: 300));
        }
      });
    }

    for (final Offset place in const [
      Offset(0.9, 0.9),
      Offset(0.62, 0.55),
      Offset(0.55, 0.62),
    ]) {
      for (final Size size in const [Size(412, 900), Size(320, 640)]) {
        testWidgets('hub at $place, ${size.width.toInt()} wide: the selected stays longest', (
          tester,
        ) async {
          await _pump(tester, count: 5, hubPosition: place, size: size);
          final Offset hub = _hub(tester);
          final TestGesture gesture = await tester.startGesture(hub);
          await tester.pump(const Duration(milliseconds: 300));
          for (double t = 0.1; t <= 0.9; t += 0.1) {
            final double angle = math.pi / 2 + (math.pi / 2) * t;
            await gesture.moveTo(_at(tester, angle, 80 + 40 * t));
            await tester.pump(const Duration(milliseconds: 500));
            await tester.pump(const Duration(milliseconds: 100));
            int? selected;
            double top = 0;
            for (int i = 0; i < 7; i++) {
              final Finder disc = find.byKey(ValueKey('dial-disc-$i'));
              if (disc.evaluate().isNotEmpty &&
                  tester.getSize(disc).width > 35.5) {
                selected = i;
                top = reach(tester, i)!;
              }
            }
            if (selected == null) {
              continue;
            }
            for (int i = 1; i <= 5; i++) {
              final double? other = reach(tester, i);
              if (i == selected || other == null) {
                continue;
              }
              // Longest, unless both are down at the shortest a tab can be.
              if (other > 24 + 48 + 4) {
                expect(other, lessThan(top - 4), reason: 'list $i at $t');
              }
            }
          }
          await gesture.up();
          await tester.pump(const Duration(milliseconds: 300));
        });
      }
    }

    testWidgets('with room to spare, far lists keep their length', (tester) async {
      await _pump(tester, count: 14);
      final Offset hub = _hub(tester);
      final List<double> atRest = [];
      final TestGesture gesture = await tester.startGesture(hub);
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.moveTo(_at(tester, _diagonal(tester), 200));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 100));
      final double far = 24 + (hub.distance / 2 - 24) * _config.dialFarLength;
      for (int i = 3; i < 6; i++) {
        final double? other = reach(tester, i);
        if (other != null) {
          atRest.add(other);
          expect(other, closeTo(far, 40));
        }
      }
      expect(atRest, isNotEmpty);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
    });

    for (final Size size in const [
      Size(412, 900),
      Size(430, 932),
      Size(393, 852),
      Size(360, 780),
      Size(320, 640),
    ]) {
      testWidgets('at rest the lists stand on one circle, ${size.width.toInt()} wide', (
        tester,
      ) async {
        await _pump(tester, count: 14, size: size);
        await _openArranging(tester);
        final List<double> ends = [
          for (int i = 1; i < 15; i++)
            if (reach(tester, i) != null) reach(tester, i)!,
        ];
        expect(ends.length, greaterThan(3));
        final double longest = ends.reduce(math.max);
        for (final double end in ends) {
          expect(end, closeTo(longest, 4));
        }
      });

      testWidgets('so do they on the normal dial, ${size.width.toInt()} wide', (
        tester,
      ) async {
        await _pump(tester, count: 14, size: size);
        final TestGesture gesture = await tester.startGesture(_hub(tester));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 100));
        final List<double> ends = [
          for (int i = 1; i < 15; i++)
            if (reach(tester, i) != null) reach(tester, i)!,
        ];
        expect(ends.length, greaterThan(3));
        final double longest = ends.reduce(math.max);
        for (final double end in ends) {
          expect(end, closeTo(longest, 4));
        }
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 300));
      });
    }

    for (final Offset place in const [
      Offset(0.9, 0.9),
      Offset(0.1, 0.9),
      Offset(0.9, 0.1),
      Offset(0.1, 0.1),
      Offset(0.6, 0.6),
    ]) {
      for (final Size size in const [Size(412, 900), Size(320, 640)]) {
        testWidgets('hub at $place, ${size.width.toInt()} wide: no list leaves the screen', (
          tester,
        ) async {
          await _pump(tester, count: 14, hubPosition: place, size: size);
          await _openArranging(tester);
          final Rect screen = Offset.zero & size;
          for (int i = 1; i < 15; i++) {
            final Finder tab = find.byKey(ValueKey('dial-entry-$i'));
            if (tab.evaluate().isNotEmpty) {
              expect(
                screen.inflate(2).contains(tester.getRect(tab).topLeft) &&
                    screen.inflate(2).contains(tester.getRect(tab).bottomRight),
                isTrue,
                reason: 'list $i',
              );
            }
          }
        });
      }
    }

    testWidgets('near the edge Edit still shows on the screen, and is reachable', (
      tester,
    ) async {
      final _Harness h = await _pump(tester, count: 5);
      final Offset hub = _hub(tester);
      final TestGesture gesture = await tester.startGesture(hub);
      await tester.pump(const Duration(milliseconds: 300));
      final double half = hub.distance / 2;
      // Low on the dial, where the screen's bottom edge is near.
      final Offset spot = _at(tester, math.pi - 0.2, half * 0.5);
      await _steps(tester, gesture, hub, spot);
      for (int i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      final Finder edit = find.byKey(const ValueKey('dial-edit'));
      expect(edit, findsOneWidget);
      final Rect rect = tester.getRect(edit);
      expect(rect.left, greaterThanOrEqualTo(-1));
      expect(rect.bottom, lessThanOrEqualTo(901));

      final Offset out = hub + (spot - hub) * 1.3;
      await _steps(tester, gesture, spot, out);
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(h.log.single, startsWith('edit'));
    });
  });

  group('the prompts on a finger that has come back to the hub', () {
    // Out onto a list and back, in one hold.
    Future<TestGesture> outAndBack(WidgetTester tester) async {
      final Offset hub = _hub(tester);
      final TestGesture gesture = await tester.startGesture(hub);
      await tester.pump(const Duration(milliseconds: 300));
      final Offset out = _at(tester, _diagonal(tester), 170);
      await _steps(tester, gesture, hub, out);
      await tester.pump(const Duration(milliseconds: 100));
      await _steps(tester, gesture, out, hub);
      return gesture;
    }

    testWidgets('a rest there brings them out, and Arrange opens', (tester) async {
      await _pump(tester);
      final TestGesture gesture = await outAndBack(tester);
      expect(_arrange, findsNothing);
      await tester.pump(_config.promptDelay - const Duration(milliseconds: 200));
      expect(_arrange, findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_arrange, findsOneWidget);
      expect(_move, findsOneWidget);

      await _steps(tester, gesture, _hub(tester), tester.getCenter(_arrange));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(_area, findsOneWidget);
    });

    testWidgets('letting go without reaching one does nothing', (tester) async {
      final _Harness h = await _pump(tester);
      final TestGesture gesture = await outAndBack(tester);
      await tester.pump(_config.promptDelay + const Duration(milliseconds: 400));
      expect(_arrange, findsOneWidget);

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(_arrange, findsNothing);
      expect(_area, findsNothing);
      expect(find.byKey(const ValueKey('dial-entry-1')), findsNothing);
      expect(h.log, isEmpty);
    });

    testWidgets('a quick return and lift cancels, and opens nothing', (tester) async {
      final _Harness h = await _pump(tester);
      final TestGesture gesture = await outAndBack(tester);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(_arrange, findsNothing);
      // Not a tap: the dial has not stayed open.
      expect(find.byKey(const ValueKey('dial-entry-1')), findsNothing);
      expect(h.log, isEmpty);
    });
  });

  group('the arrange state', () {
    testWidgets('looks different: blue in front, grips, lists further apart', (
      tester,
    ) async {
      await _pump(tester, inList: true);
      Color front() =>
          (tester.widget<Container>(_hubDisc).decoration! as BoxDecoration)
              .color!;
      expect(front(), isNot(AppColors.appBlue));

      await _openArranging(tester);
      expect(front(), AppColors.appBlue);
      expect(find.byKey(const ValueKey('dial-grip-1')), findsOneWidget);
      // Arranging moves lists only.
      expect(find.byIcon(Icons.add), findsNothing);
      expect(find.byIcon(Icons.home_outlined), findsNothing);
    });

    testWidgets('the lists sway slowly, and not with reduced motion', (
      tester,
    ) async {
      await _pump(tester);
      await _openArranging(tester);
      final Rect before = _tab(tester, 2);
      await tester.pump(arrangeSwayPeriod ~/ 4);
      expect(_tab(tester, 2), isNot(before));
      // Slow and small: a quarter of its period moves it only a little.
      expect((_tab(tester, 2).center - before.center).distance, lessThan(12));
    });

    testWidgets('with reduced motion the lists stand still', (tester) async {
      await _pump(tester, reduceMotion: true);
      await _openArranging(tester);
      final Rect still = _tab(tester, 2);
      await tester.pump(arrangeSwayPeriod ~/ 4);
      expect(_tab(tester, 2), still);
      // Nothing keeps animating.
      await tester.pumpAndSettle();
    });

    testWidgets('dragging a list moves it, saves, and the state stays open', (
      tester,
    ) async {
      final _Harness h = await _pump(tester);
      await _openArranging(tester);

      await _drag(tester, 0, 2);
      expect(h.log, ['order n1,n2,n0,n3']);
      expect(_area, findsOneWidget);

      // Several drags, law rule 6's written exception.
      await _drag(tester, 3, 1);
      expect(h.log.last, 'order n1,n3,n2,n0');
      expect(_area, findsOneWidget);
    });

    testWidgets('a drag that ends where it began saves nothing', (
      tester,
    ) async {
      final _Harness h = await _pump(tester);
      await _openArranging(tester);
      final Offset start = _list(tester, 1);
      final TestGesture gesture = await tester.startGesture(start);
      await tester.pump(_rest);
      await _steps(tester, gesture, start, _list(tester, 3));
      await _steps(tester, gesture, _list(tester, 3), start);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.log, isEmpty);
    });

    testWidgets('only the list in the hand grows', (tester) async {
      await _pump(tester);
      await _openArranging(tester);
      final double held = _tab(tester, 1).longestSide;
      final double neighbour = _tab(tester, 2).longestSide;

      final TestGesture gesture = await tester.startGesture(_list(tester, 0));
      // Not yet: only a rest picks it up, and then it grows.
      await tester.pump(_config.dialPickUpDelay - const Duration(milliseconds: 50));
      expect((_tab(tester, 1).longestSide - held).abs(), lessThan(6));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_tab(tester, 1).longestSide, greaterThan(held + 10));
      expect((_tab(tester, 2).longestSide - neighbour).abs(), lessThan(6));
      await gesture.up();
    });

    group('the lists changing places', () {
      // List 0 picked up, and carried just past list 1.
      Future<TestGesture> swapFirstTwo(WidgetTester tester) async {
        final Offset start = _list(tester, 0);
        final TestGesture gesture = await tester.startGesture(start);
        await tester.pump(_rest);
        await tester.pump(const Duration(milliseconds: 300));
        await _steps(tester, gesture, start, _list(tester, 1));
        return gesture;
      }

      testWidgets('the passed list slides to its new place', (tester) async {
        await _pump(tester, count: 6);
        await _openArranging(tester);
        final Rect slotOne = _tab(tester, 2);
        await tester.pump(const Duration(milliseconds: 50));

        final TestGesture gesture = await swapFirstTwo(tester);
        // Just after the swap it is on its way, not there yet; entry 1 is now
        // the list that stood at entry 2.
        final Rect soon = _tab(tester, 1);
        await tester.pump(const Duration(milliseconds: 400));
        final Rect settled = _tab(tester, 1);
        expect((soon.center - settled.center).distance, greaterThan(4));
        expect(
          (soon.center - slotOne.center).distance,
          lessThan((settled.center - slotOne.center).distance),
        );
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 300));
      });

      testWidgets('with reduced motion it goes there at once', (tester) async {
        await _pump(tester, count: 6, reduceMotion: true);
        await _openArranging(tester);

        final TestGesture gesture = await swapFirstTwo(tester);
        final Rect soon = _tab(tester, 1);
        await tester.pump(const Duration(milliseconds: 400));
        expect((soon.center - _tab(tester, 1).center).distance, lessThan(1));
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 300));
      });

      testWidgets('the held list follows the finger between places', (tester) async {
        final _Harness h = await _pump(tester, count: 6);
        await _openArranging(tester);
        final Offset start = _list(tester, 1);
        final TestGesture gesture = await tester.startGesture(start);
        await tester.pump(_rest);
        await tester.pump(const Duration(milliseconds: 300));
        final Rect before = _tab(tester, 2);

        // A third of a place along: no swap yet, and it has moved with the finger.
        final Offset along = _at(
          tester,
          _diagonal(tester) + _step * (1 + 1 / 3),
          170,
        );
        await _steps(tester, gesture, start, along);
        await tester.pump(const Duration(milliseconds: 50));
        expect((_tab(tester, 2).center - before.center).distance, greaterThan(10));

        // Let go there: it settles back to its place, and nothing changed.
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 16));
        final Rect dropped = _tab(tester, 2);
        await tester.pump(const Duration(milliseconds: 500));
        expect((dropped.center - _tab(tester, 2).center).distance, greaterThan(4));
        expect(h.log, isEmpty);
      });

      testWidgets('quick swaps and the end zones end in the right order', (
        tester,
      ) async {
        final _Harness h = await _pump(tester, count: 14);
        await _openArranging(tester);
        final Offset start = _list(tester, 0);
        final TestGesture gesture = await tester.startGesture(start);
        await tester.pump(_rest);
        // Fast across several places, on into the zone, and back in.
        final Offset edge = _at(tester, math.pi - 0.05, 170);
        for (int i = 1; i <= 4; i++) {
          await gesture.moveTo(Offset.lerp(start, edge, i / 4)!);
          await tester.pump(const Duration(milliseconds: 16));
        }
        for (int i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await _steps(tester, gesture, edge, _list(tester, 1));
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 500));

        expect(tester.takeException(), isNull);
        final List<String> ids = h.log.single
            .substring('order '.length)
            .split(',');
        expect(ids.toSet(), hasLength(14));
        expect(ids.indexOf('n0'), greaterThan(0));
      });
    });

    testWidgets('a press outside the lists ends it, and acts on nothing', (
      tester,
    ) async {
      final _Harness h = await _pump(tester);
      await _openArranging(tester);
      await tester.tapAt(const Offset(30, 30));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_area, findsNothing);
      expect(h.log, isEmpty);
    });

    testWidgets('a press on the hub ends it', (tester) async {
      await _pump(tester);
      await _openArranging(tester);
      await tester.tapAt(_hub(tester));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_area, findsNothing);
    });

    testWidgets('Back ends it and goes nowhere else', (tester) async {
      await _pump(tester);
      await _openArranging(tester);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_area, findsNothing);
      expect(_hubDisc, findsOneWidget);
    });

    testWidgets('Esc ends it', (tester) async {
      await _pump(tester);
      await _openArranging(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 300));
      expect(_area, findsNothing);
    });

    testWidgets('a list added elsewhere keeps the order on screen', (
      tester,
    ) async {
      final _Harness h = await _pump(tester);
      await _openArranging(tester);
      final Offset start = _list(tester, 0);
      final TestGesture gesture = await tester.startGesture(start);
      await tester.pump(_rest);
      await _steps(tester, gesture, start, _list(tester, 2));

      h.lists.value = _notes(5);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.log, ['order n1,n2,n0,n3,n4']);
    });

    testWidgets('a list removed elsewhere while held is let go', (
      tester,
    ) async {
      final _Harness h = await _pump(tester);
      await _openArranging(tester);
      final TestGesture gesture = await tester.startGesture(_list(tester, 3));
      await tester.pump(_rest);

      h.lists.value = _notes(3);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(_area, findsOneWidget);
      expect(h.log.where((entry) => entry.contains('n3')), isEmpty);
    });

    testWidgets('with many lists the arrows turn the dial', (tester) async {
      await _pump(tester, count: 14);
      await _openArranging(tester);
      final Finder next = find.byKey(const ValueKey('launcher-next'));
      expect(next, findsOneWidget);
      final Rect before = _tab(tester, 3);
      await tester.tap(next);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        (_tab(tester, 3).center - before.center).distance,
        greaterThan(20),
      );
      // Still arranging: the arrows are not a press outside.
      expect(_area, findsOneWidget);
    });

    testWidgets(
      'with many lists, holding a list at the end scrolls the rest in',
      (tester) async {
        final _Harness h = await _pump(tester, count: 14);
        await _openArranging(tester);
        final Offset start = _list(tester, 1);
        final TestGesture gesture = await tester.startGesture(start);
        await tester.pump(_rest);
        // Far round towards the bottom edge, and hold there.
        final Offset edge = _at(tester, math.pi - 0.05, 170);
        await _steps(tester, gesture, start, edge);
        for (int i = 0; i < 60; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 100));
        final List<String> ids = h.log.single
            .substring('order '.length)
            .split(',');
        expect(ids, hasLength(14));
        // It travelled past lists that were off the dial at the start.
        expect(ids.indexOf('n1'), greaterThan(7));
      },
    );

    group('resting and scrolling', () {
      // Far round towards the bottom edge, in the scroll zone there.
      Offset zone(WidgetTester tester, {double radius = 170}) =>
          _at(tester, math.pi - 0.05, radius);

      // The list stood there, and has moved or scrolled away.
      void expectScrolled(WidgetTester tester, Rect before) {
        final Finder tab = find.byKey(const ValueKey('dial-entry-3'));
        if (tab.evaluate().isNotEmpty) {
          expect(
            (tester.getRect(tab).center - before.center).distance,
            greaterThan(20),
          );
        }
      }

      Future<void> holdThere(WidgetTester tester) async {
        for (int i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      testWidgets('moving along the middle of the dial scrolls nothing', (
        tester,
      ) async {
        final _Harness h = await _pump(tester, count: 14);
        await _openArranging(tester);
        final Rect before = _tab(tester, 3);
        final double neighbour = _tab(tester, 2).longestSide;

        final Offset start = _list(tester, 0);
        final TestGesture gesture = await tester.startGesture(start);
        await tester.pump(const Duration(milliseconds: 16));
        await _steps(tester, gesture, start, _list(tester, 1));
        await tester.pump(const Duration(milliseconds: 300));

        expect((_tab(tester, 3).center - before.center).distance, lessThan(12));
        // Nothing grows: only a list in the hand does.
        expect((_tab(tester, 2).longestSide - neighbour).abs(), lessThan(6));
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 300));
        expect(_area, findsOneWidget);
        expect(h.log, isEmpty);
      });

      testWidgets('a swipe from a list into a zone scrolls, and moves no list', (
        tester,
      ) async {
        final _Harness h = await _pump(tester, count: 14);
        await _openArranging(tester);
        final Rect before = _tab(tester, 3);

        final Offset start = _list(tester, 1);
        final TestGesture gesture = await tester.startGesture(start);
        await tester.pump(const Duration(milliseconds: 16));
        await _steps(tester, gesture, start, zone(tester));
        await holdThere(tester);

        expectScrolled(tester, before);
        // However long it stays down, nothing is picked up.
        await tester.pump(_rest * 3);
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 300));
        expect(_area, findsOneWidget);
        expect(h.log, isEmpty);
      });

      testWidgets('a swipe that starts on empty space scrolls the same', (
        tester,
      ) async {
        final _Harness h = await _pump(tester, count: 14);
        await _openArranging(tester);
        final Rect before = _tab(tester, 3);

        // Beyond the lists' ends, still in reach of the dial.
        final Offset start = _at(tester, _diagonal(tester), 440);
        final TestGesture gesture = await tester.startGesture(start);
        await tester.pump(const Duration(milliseconds: 16));
        await _steps(tester, gesture, start, zone(tester, radius: 330));
        await holdThere(tester);

        expectScrolled(tester, before);
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 300));
        expect(_area, findsOneWidget);
        expect(h.log, isEmpty);
      });

      testWidgets('a press in a zone scrolls at once, and picks nothing up', (
        tester,
      ) async {
        final _Harness h = await _pump(tester, count: 14);
        await _openArranging(tester);
        final Rect before = _tab(tester, 3);

        final TestGesture gesture = await tester.startGesture(zone(tester));
        await holdThere(tester);

        expectScrolled(tester, before);
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 300));
        expect(_area, findsOneWidget);
        expect(h.log, isEmpty);
      });

      testWidgets('with nothing left to come, a list in the zone can be picked up', (
        tester,
      ) async {
        final _Harness h = await _pump(tester, count: 14);
        await _openArranging(tester);
        final TestGesture toEnd = await tester.startGesture(zone(tester));
        for (int i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await toEnd.up();
        await tester.pump(const Duration(milliseconds: 300));

        // The last list, at its place at the end.
        final Offset press = _tab(tester, 14).center;
        final TestGesture gesture = await tester.startGesture(press);
        await tester.pump(_rest);
        await _steps(tester, gesture, press, _list(tester, 0));
        await tester.pump(const Duration(milliseconds: 100));
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 300));

        expect(h.log, hasLength(1));
      });

      testWidgets('passing lists clicks, as on the normal dial', (tester) async {
        final List<String> buzzes = [];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              buzzes.add(call.arguments as String);
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await _pump(tester, count: 14);
        await _openArranging(tester);
        buzzes.clear();

        final Offset start = _list(tester, 0);
        final TestGesture gesture = await tester.startGesture(start);
        await tester.pump(const Duration(milliseconds: 16));
        expect(buzzes, isEmpty);
        await _steps(tester, gesture, start, _list(tester, 1));
        expect(buzzes, contains('HapticFeedbackType.selectionClick'));
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 300));
      });

      testWidgets('a finger passing under the hub does not throw the dial', (
        tester,
      ) async {
        await _pump(tester, count: 14);
        await _openArranging(tester);
        final Offset hub = _hub(tester);
        final TestGesture gesture = await tester.startGesture(
          hub + const Offset(-20, 60),
        );
        await tester.pump(const Duration(milliseconds: 16));
        await _steps(
          tester,
          gesture,
          hub + const Offset(-20, 60),
          hub + const Offset(-1, 60),
        );
        final Rect beside = _tab(tester, 3);
        await gesture.moveTo(hub + const Offset(1, 60));
        await tester.pump(const Duration(milliseconds: 300));

        expect((_tab(tester, 3).center - beside.center).distance, lessThan(12));
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 300));
      });

      testWidgets('a small shake while resting still picks the list up', (
        tester,
      ) async {
        final _Harness h = await _pump(tester, count: 14);
        await _openArranging(tester);
        final Rect before = _tab(tester, 3);
        final double held = _tab(tester, 1).longestSide;
        final Offset start = _list(tester, 0);

        final TestGesture gesture = await tester.startGesture(start);
        final double shake = _config.moveTolerance - 2;
        for (final Offset move in [
          Offset(shake, 0),
          Offset(0, shake),
          Offset(-shake, 0),
          Offset(0, -shake),
        ]) {
          await gesture.moveTo(start + move);
          await tester.pump(_config.dialPickUpDelay * 0.25);
        }
        await tester.pump(const Duration(milliseconds: 500));

        // In the hand, and the shake did not turn the dial.
        expect(_tab(tester, 1).longestSide, greaterThan(held + 10));
        expect((_tab(tester, 3).center - before.center).distance, lessThan(12));
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 300));
        expect(h.log, isEmpty);
      });

      testWidgets('a press on a list that lifts without moving does nothing', (
        tester,
      ) async {
        final _Harness h = await _pump(tester);
        await _openArranging(tester);
        await tester.tapAt(_list(tester, 1));
        await tester.pump(_rest * 2);
        expect(_area, findsOneWidget);
        expect(h.log, isEmpty);

        // Nor does a rest that lifts where it picked up.
        final TestGesture gesture = await tester.startGesture(_list(tester, 1));
        await tester.pump(_rest);
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 300));
        expect(_area, findsOneWidget);
        expect(h.log, isEmpty);
      });

      for (final bool haptics in [true, false]) {
        testWidgets('picking up ${haptics ? 'buzzes' : 'stays quiet with Vibration off'}', (
          tester,
        ) async {
          final List<String> buzzes = [];
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'HapticFeedback.vibrate') {
                buzzes.add(call.arguments as String);
              }
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              SystemChannels.platform,
              null,
            ),
          );
          await _pump(tester, haptics: haptics);
          await _openArranging(tester);
          buzzes.clear();

          final TestGesture gesture = await tester.startGesture(_list(tester, 1));
          await tester.pump(_config.dialPickUpDelay - const Duration(milliseconds: 50));
          expect(buzzes, isEmpty);
          await tester.pump(const Duration(milliseconds: 100));
          expect(buzzes, haptics ? ['HapticFeedbackType.mediumImpact'] : isEmpty);
          await gesture.up();
          await tester.pump(const Duration(milliseconds: 300));
        });
      }
    });

    group('the wedges at the ends', () {
      for (final bool inList in [false, true]) {
        testWidgets('every list on screen can be picked up, ${inList ? 'in a list' : 'on home'}', (
          tester,
        ) async {
          await _pump(tester, count: 14, inList: inList);
          await _openArranging(tester);
          int picked = 0;
          for (int i = 1; i < 15; i++) {
            final Finder disc = find.byKey(ValueKey('dial-disc-$i'));
            if (disc.evaluate().isEmpty) {
              continue;
            }
            final Offset spot = tester.getCenter(disc);
            final int other = i == 1 ? 2 : 1;
            final Rect before = _tab(tester, other);
            final TestGesture gesture = await tester.startGesture(spot);
            await tester.pump(_rest);
            await tester.pump(const Duration(milliseconds: 400));
            // It holds still, and it is in the hand.
            expect(tester.getSize(disc).width, greaterThan(35));
            expect(
              (_tab(tester, other).center - before.center).distance,
              lessThan(12),
            );
            await gesture.up();
            await tester.pump(const Duration(milliseconds: 400));
            picked++;
          }
          expect(picked, greaterThan(3));
        });
      }

      for (final Size size in const [Size(412, 900), Size(320, 640)]) {
        testWidgets('a press in each wedge scrolls, clear of the arrows, ${size.width}', (
          tester,
        ) async {
          final _Harness h = await _pump(tester, count: 14, size: size);
          await _openArranging(tester);
          final Rect before = _tab(tester, 2);

          for (final double radius in const [120.0, 220.0]) {
            final TestGesture gesture = await tester.startGesture(
              _at(tester, math.pi - 0.03, radius),
            );
            for (int i = 0; i < 6; i++) {
              await tester.pump(const Duration(milliseconds: 50));
            }
            await gesture.up();
            await tester.pump(const Duration(milliseconds: 200));
          }
          final Finder tab = find.byKey(const ValueKey('dial-entry-2'));
          if (tab.evaluate().isNotEmpty) {
            expect(
              (tester.getRect(tab).center - before.center).distance,
              greaterThan(20),
            );
          }
          final Finder late = find.byKey(const ValueKey('dial-disc-1'));
          final Offset wasFirst =
              late.evaluate().isEmpty ? Offset.zero : tester.getCenter(late);

          // Back again from the wedge at the other end.
          final TestGesture back = await tester.startGesture(
            _at(tester, math.pi / 2 + 0.03, 220),
          );
          for (int i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          await back.up();
          await tester.pump(const Duration(milliseconds: 200));
          expect(late, findsOneWidget);
          expect(tester.getCenter(late), isNot(wasFirst));
          expect(_area, findsOneWidget);
          expect(h.log, isEmpty);
        });
      }

      testWidgets('at the end, the last list stands whole, and the wedge stays empty', (
        tester,
      ) async {
        await _pump(tester, count: 14);
        await _openArranging(tester);
        final TestGesture gesture = await tester.startGesture(
          _at(tester, math.pi - 0.03, 170),
        );
        for (int i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 300));

        final Offset disc = tester.getCenter(
          find.byKey(const ValueKey('dial-disc-14')),
        );
        final Offset fromHub = disc - _hub(tester);
        final double angle = math.atan2(-fromHub.dy, fromHub.dx);
        expect(angle, lessThan(math.pi - 0.1));
      });

      testWidgets('carrying a held list into the wedge scrolls the others', (
        tester,
      ) async {
        final _Harness h = await _pump(tester, count: 14);
        await _openArranging(tester);
        final Offset start = _list(tester, 0);
        final TestGesture gesture = await tester.startGesture(start);
        await tester.pump(_rest);
        final Offset wedge = _at(tester, math.pi - 0.03, 170);
        await _steps(tester, gesture, start, wedge);
        for (int i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 300));
        final List<String> ids = h.log.single
            .substring('order '.length)
            .split(',');
        expect(ids.indexOf('n0'), greaterThan(7));
      });
    });

    group('far off the dial', () {
      // A spot off the lists, near the far corner, out of the dial's reach.
      const Offset blank = Offset(40, 80);

      testWidgets('a swipe there scrolls nothing and stays open', (tester) async {
        final _Harness h = await _pump(tester, count: 14);
        await _openArranging(tester);
        final Rect before = _tab(tester, 3);

        final TestGesture gesture = await tester.startGesture(blank);
        await tester.pump(const Duration(milliseconds: 16));
        await _steps(tester, gesture, blank, blank + const Offset(120, 40));
        await tester.pump(const Duration(milliseconds: 200));
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 300));

        expect(_area, findsOneWidget);
        expect(h.log, isEmpty);
        expect((_tab(tester, 3).center - before.center).distance, lessThan(12));
      });

      testWidgets('a tap there still ends it', (tester) async {
        await _pump(tester, count: 14);
        await _openArranging(tester);
        final TestGesture gesture = await tester.startGesture(blank);
        await tester.pump(const Duration(milliseconds: 50));
        // Pressing alone does not end it.
        expect(_area, findsOneWidget);
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 300));
        expect(_area, findsNothing);
      });
    });

    testWidgets('the normal dial works again afterwards, in the saved order', (
      tester,
    ) async {
      final _Harness h = await _pump(tester);
      await _openArranging(tester);
      await _drag(tester, 0, 1);
      await tester.tapAt(const Offset(30, 30));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_area, findsNothing);

      // No grip marks, New list is back.
      final TestGesture gesture = await tester.startGesture(_hub(tester));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('dial-grip-1')), findsNothing);
      expect(find.byIcon(Icons.add), findsOneWidget);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(h.log, hasLength(1));
    });
  });

  test('the sway stays between -1 and 1, out of step between neighbours', () {
    const Duration now = Duration(milliseconds: 700);
    for (int i = 0; i < 40; i++) {
      expect(arrangeSway(now * i, 3).abs(), lessThanOrEqualTo(1));
    }
    expect(arrangeSway(now, 1), isNot(arrangeSway(now, 2)));
  });
}
