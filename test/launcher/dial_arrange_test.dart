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

Future<void> _drag(WidgetTester tester, int from, int to) async {
  final Offset start = _list(tester, from);
  final TestGesture gesture = await tester.startGesture(start);
  await tester.pump(const Duration(milliseconds: 100));
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
      await tester.pump(const Duration(milliseconds: 100));
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
      await tester.pump(const Duration(milliseconds: 400));
      expect(_tab(tester, 1).longestSide, greaterThan(held + 10));
      expect((_tab(tester, 2).longestSide - neighbour).abs(), lessThan(6));
      await gesture.up();
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
      await tester.pump(const Duration(milliseconds: 100));
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
      await tester.pump(const Duration(milliseconds: 100));

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
        await tester.pump(const Duration(milliseconds: 100));
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
