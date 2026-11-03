import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/launcher/dial_launcher.dart';
import 'package:hybrid_note/launcher/radial_launcher.dart';

const double _step = 12 * math.pi / 180;

List<LauncherNote> _notes(int count) {
  return [
    for (int i = 0; i < count; i++)
      LauncherNote(
        id: 'n$i',
        label: 'Note $i',
        icon: Icons.list,
        color: Colors.blue,
        semanticsLabel: 'Note $i',
      ),
  ];
}

Future<List<String>> _pump(
  WidgetTester tester, {
  int count = 4,
  bool inList = false,
  bool reduceMotion = false,
}) async {
  final List<String> log = [];
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(400, 800),
          disableAnimations: reduceMotion,
        ),
        child: Scaffold(
          body: DialLauncher(
            notes: _notes(count),
            onOpen: (note) => log.add('open ${note.id}'),
            onEdit: (note) => log.add('edit ${note.id}'),
            onNew: () => log.add('new'),
            onHome: inList ? () => log.add('home') : null,
            onHubMoved: (position) => log.add('moved'),
          ),
        ),
      ),
    ),
  );
  return log;
}

Offset _hub(WidgetTester tester) =>
    tester.getCenter(find.byKey(const ValueKey('launcher-hub')));

// A point at a frame angle (pi/2 straight up, pi towards the left edge; the
// hub's default corner is the bottom right) and distance from the hub.
Offset _at(WidgetTester tester, double angle, double radius) =>
    _hub(tester) + Offset(math.cos(angle), -math.sin(angle)) * radius;

// The screen diagonal from the hub to the far (top left) corner.
double _diagonal(WidgetTester tester) {
  final Offset hub = _hub(tester);
  return math.atan2(hub.dy, -hub.dx);
}

// Moves the finger in small steps, letting the dial follow.
Future<void> _moveTo(
  WidgetTester tester,
  TestGesture gesture,
  Offset from,
  Offset to,
) async {
  for (int i = 1; i <= 6; i++) {
    await gesture.moveTo(Offset.lerp(from, to, i / 6)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
}

// Turns the finger around the hub at one distance.
Future<void> _turn(
  WidgetTester tester,
  TestGesture gesture,
  double from,
  double to,
  double radius,
) async {
  for (int i = 1; i <= 8; i++) {
    await gesture.moveTo(_at(tester, from + (to - from) * i / 8, radius));
    await tester.pump(const Duration(milliseconds: 16));
  }
}

// Presses the hub and points along the diagonal, which picks the first list.
Future<TestGesture> _pickFirst(WidgetTester tester) async {
  final Offset hub = _hub(tester);
  final TestGesture gesture = await tester.startGesture(hub);
  await tester.pump(const Duration(milliseconds: 50));
  await _moveTo(tester, gesture, hub, _at(tester, _diagonal(tester), 160));
  await tester.pump(const Duration(milliseconds: 300));
  return gesture;
}

void main() {
  testWidgets('pointing along the diagonal picks the first list', (
    WidgetTester tester,
  ) async {
    final List<String> log = await _pump(tester);
    final TestGesture gesture = await _pickFirst(tester);
    await gesture.up();
    await tester.pump();
    expect(log, ['open n0']);
  });

  testWidgets('turning the thumb one step picks the next list', (
    WidgetTester tester,
  ) async {
    final List<String> log = await _pump(tester);
    final TestGesture gesture = await _pickFirst(tester);
    final double diagonal = _diagonal(tester);
    // Later lists lie towards the bottom edge (larger angles).
    await _turn(tester, gesture, diagonal, diagonal + 1.1 * _step, 160);
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pump();
    expect(log, ['open n1']);
  });

  testWidgets('holding at the bottom edge scrolls to the last list', (
    WidgetTester tester,
  ) async {
    final List<String> log = await _pump(tester, count: 12);
    final TestGesture gesture = await _pickFirst(tester);
    await _turn(tester, gesture, _diagonal(tester), math.pi - 0.05, 160);
    for (int i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    // No Edit while holding at an edge.
    expect(find.byKey(const ValueKey('dial-edit')), findsNothing);
    await gesture.up();
    await tester.pump();
    expect(log, ['open n11']);
  });

  testWidgets('inside a list, past the last list the bottom edge picks Home', (
    WidgetTester tester,
  ) async {
    final List<String> log = await _pump(tester, count: 3, inList: true);
    final TestGesture gesture = await _pickFirst(tester);
    await _turn(tester, gesture, _diagonal(tester), math.pi - 0.05, 160);
    for (int i = 0; i < 150; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await gesture.up();
    await tester.pump();
    expect(log, ['home']);
  });

  testWidgets('at the first list the side edge picks New list', (
    WidgetTester tester,
  ) async {
    final List<String> log = await _pump(tester);
    final TestGesture gesture = await _pickFirst(tester);
    await _turn(tester, gesture, _diagonal(tester), math.pi / 2 + 0.05, 160);
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump();
    expect(log, ['new']);
  });

  testWidgets('holding at the side edge scrolls back, then picks New list', (
    WidgetTester tester,
  ) async {
    final List<String> log = await _pump(tester, count: 8);
    final TestGesture gesture = await _pickFirst(tester);
    final double diagonal = _diagonal(tester);
    // Step out to the fourth list, then hold at the side edge.
    await _turn(tester, gesture, diagonal, diagonal + 3.2 * _step, 160);
    await tester.pump(const Duration(milliseconds: 300));
    await _turn(
      tester,
      gesture,
      diagonal + 3.2 * _step,
      math.pi / 2 + 0.05,
      160,
    );
    for (int i = 0; i < 150; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await gesture.up();
    await tester.pump();
    expect(log, ['new']);
  });

  testWidgets('resting shows Edit past the tab; a short swipe out picks it', (
    WidgetTester tester,
  ) async {
    final List<String> log = await _pump(tester);
    final TestGesture gesture = await _pickFirst(tester);
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(find.byKey(const ValueKey('dial-edit')), findsOneWidget);
    final double diagonal = _diagonal(tester);
    await _moveTo(
      tester,
      gesture,
      _at(tester, diagonal, 160),
      _at(tester, diagonal, 192),
    );
    await gesture.up();
    await tester.pump();
    expect(log, ['edit n0']);
  });

  testWidgets('resting on the hub offers Move; sliding onto it moves the hub', (
    WidgetTester tester,
  ) async {
    final List<String> log = await _pump(tester);
    final Offset hub = _hub(tester);
    final TestGesture gesture = await tester.startGesture(hub);
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    final Finder prompt = find.byKey(const ValueKey('launcher-move-prompt'));
    expect(prompt, findsOneWidget);
    // Reaching Move picks the hub up; it follows the finger from there.
    final Offset onPrompt = tester.getCenter(prompt);
    await _moveTo(tester, gesture, hub, onPrompt);
    await _moveTo(tester, gesture, onPrompt, const Offset(120, 300));
    await gesture.up();
    await tester.pump();
    expect(log, ['moved']);
    expect(_hub(tester).dy, lessThan(hub.dy - 100));
  });

  testWidgets('a quick tap opens tap mode; tapping a tab acts on it', (
    WidgetTester tester,
  ) async {
    final List<String> log = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('launcher-hub')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('launcher-note-n0')));
    await tester.pump();
    expect(log, ['open n0']);

    await tester.tap(find.byKey(const ValueKey('launcher-hub')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('launcher-add')));
    await tester.pump();
    expect(log, ['open n0', 'new']);
  });

  testWidgets('with reduced motion the tabs are full size at once', (
    WidgetTester tester,
  ) async {
    await _pump(tester, reduceMotion: true);
    final TestGesture gesture = await tester.startGesture(_hub(tester));
    await tester.pump();
    final Size first =
        tester.getSize(find.byKey(const ValueKey('dial-entry-1')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.getSize(find.byKey(const ValueKey('dial-entry-1'))),
      first,
    );
    await gesture.up();
  });
}
