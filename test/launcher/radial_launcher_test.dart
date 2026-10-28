import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/launcher/launcher_geometry.dart';
import 'package:hybrid_note/launcher/radial_launcher.dart';

const LauncherConfig _config = LauncherConfig();

List<LauncherNote> _notes(int count) {
  return [
    for (int i = 0; i < count; i++)
      LauncherNote(
        id: 'n$i',
        label: 'Note $i',
        icon: Icons.list,
        color: Colors.blue,
        semanticsLabel: 'Note $i, $i',
      ),
  ];
}

class _Log {
  final List<String> events = [];
}

Future<_Log> _pump(
  WidgetTester tester, {
  int count = 4,
  bool withNew = true,
  Offset? hubPosition,
}) async {
  final _Log log = _Log();
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RadialLauncher(
          notes: _notes(count),
          onOpen: (note) => log.events.add('open ${note.id}'),
          onEdit: (note) => log.events.add('edit ${note.id}'),
          onNew: withNew ? () => log.events.add('new') : null,
          hubPosition: hubPosition,
          onHubMoved: (position) => log.events.add(
            'moved ${position.dx.toStringAsFixed(2)},${position.dy.toStringAsFixed(2)}',
          ),
        ),
      ),
    ),
  );
  return log;
}

LauncherGeometry _geometry(int count, {Offset? hub}) {
  return LauncherGeometry(
    config: _config,
    size: const Size(400, 800),
    noteCount: count,
    hubPosition: hub,
  );
}

Offset _tab(LauncherGeometry geometry, int index, [double offset = 0]) {
  return geometry.tabCenter(index, offset)!;
}

void main() {
  group('geometry', () {
    final LauncherGeometry geometry = _geometry(12);

    test('hub near the bottom-right corner, "+" right next to it', () {
      expect(geometry.hubCenter, const Offset(400 - 88, 800 - 110));
      expect(geometry.addCenter.dy, geometry.hubCenter.dy);
      expect(geometry.addCenter.dx, greaterThan(geometry.hubCenter.dx));
      expect(geometry.addCenter.dx + _config.addRadius, lessThanOrEqualTo(400));
    });

    test('tabs fan from 20 degrees above the bottom to 20 before the right edge', () {
      expect(geometry.startAngle, closeTo(160 * 3.14159265 / 180, 1e-6));
      expect(geometry.endAngle, closeTo(110 * 3.14159265 / 180, 1e-6));

      final Offset first = _tab(geometry, 0);
      final Offset last = _tab(geometry, geometry.slotCount - 1);
      // First tab points mostly left, the last mostly up; all stay on screen.
      // Neighbouring tabs overlap near the hub.
      expect(
        (geometry.pointAt(geometry.slotAngle(0), _config.innerRadius) -
                geometry.pointAt(geometry.slotAngle(1), _config.innerRadius))
            .distance,
        lessThan(_config.tabThickness),
      );
      expect(first.dx < last.dx && first.dy > last.dy, isTrue);
      for (int i = 0; i < geometry.slotCount; i++) {
        final Offset outer = geometry.pointAt(geometry.slotAngle(i.toDouble()), _config.outerRadius);
        expect(outer.dx, inInclusiveRange(0, 400));
        expect(outer.dy, inInclusiveRange(0, 800));
      }
    });

    test('hit testing finds tabs, "+", the hub and nothing', () {
      expect(geometry.hitTest(_tab(geometry, 2), 0),
          const LauncherTarget(LauncherTargetKind.note, 2));
      // Anywhere along a tab counts, not only its centre.
      expect(
        geometry.hitTest(geometry.pointAt(geometry.slotAngle(1), _config.innerRadius + 10), 0),
        const LauncherTarget(LauncherTargetKind.note, 1),
      );
      expect(geometry.hitTest(geometry.addCenter, 0), LauncherTarget.add);
      expect(geometry.hitTest(geometry.hubCenter, 0), LauncherTarget.hub);
      expect(geometry.hitTest(const Offset(20, 20), 0), LauncherTarget.none);
    });

    test('scrolling shifts which tab is under a slot', () {
      final Offset slot0 = _tab(geometry, 0);
      expect(geometry.hitTest(slot0, 3), const LauncherTarget(LauncherTargetKind.note, 3));
      expect(geometry.tabCenter(0, 3), isNull);
    });

    test('ends of the fan scroll back and forward; the middle does not', () {
      final double mid = _config.innerRadius + _config.tabLength / 2;
      final Offset start = geometry.pointAt(geometry.slotAngle(-0.4), mid);
      final Offset end = geometry.pointAt(geometry.slotAngle(geometry.slotCount - 0.6), mid);
      final Offset middle = geometry.pointAt(geometry.slotAngle((geometry.slotCount - 1) / 2), mid);

      expect(geometry.scrollVelocity(start), lessThan(0));
      expect(geometry.scrollVelocity(end), greaterThan(0));
      expect(geometry.scrollVelocity(middle), 0);
    });

    test('the fan opens away from whichever corner the hub is nearest', () {
      final LauncherGeometry topLeft = _geometry(12, hub: const Offset(60, 80));

      expect(topLeft.flipX && topLeft.flipY, isTrue);
      // "+" stays on the corner side; tabs go right and down.
      expect(topLeft.addCenter.dx, lessThan(topLeft.hubCenter.dx));
      expect(_tab(topLeft, 2).dx, greaterThan(topLeft.hubCenter.dx));
      expect(_tab(topLeft, 2).dy, greaterThan(topLeft.hubCenter.dy));
      expect(topLeft.hitTest(_tab(topLeft, 2), 0),
          const LauncherTarget(LauncherTargetKind.note, 2));

      final LauncherGeometry bottomLeft = _geometry(12, hub: const Offset(88, 690));
      expect(_tab(bottomLeft, 2).dx, closeTo(400 - _tab(geometry, 2).dx, 1e-9));
    });

    test('a moved hub stays inside the screen margins', () {
      final LauncherGeometry outside = _geometry(4, hub: const Offset(-50, 900));
      // Room for "+" beside it and the Move prompt below it.
      expect(outside.hubCenter, const Offset(86, 800 - 84));
      expect(outside.addCenter.dx - _config.addRadius, greaterThanOrEqualTo(0));
      expect(outside.movePromptCenter.dy + 18, lessThanOrEqualTo(800));
    });

    test('tab text is never upside down', () {
      for (final Offset hub in const [
        Offset(312, 736),
        Offset(60, 80),
        Offset(88, 736),
        Offset(340, 90),
      ]) {
        final LauncherGeometry g = _geometry(5, hub: hub);
        for (int i = 0; i < g.slotCount; i++) {
          final double rotation = g.tabRotation(g.slotAngle(i.toDouble()));
          expect(rotation.abs(), lessThanOrEqualTo(3.14159265 / 2 + 1e-9));
        }
      }
    });

    test('no scrolling when every tab fits', () {
      final LauncherGeometry few = _geometry(2);
      expect(few.maxScrollOffset, 0);
    });
  });

  // Rests the finger long enough for a prompt (promptDelay) in small steps.
  Future<void> rest(WidgetTester tester, [int ms = 1400]) async {
    for (int i = 0; i < ms ~/ 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> moveInSteps(TestGesture gesture, WidgetTester tester, Offset from, Offset to) async {
    for (int i = 1; i <= 6; i++) {
      await gesture.moveTo(Offset.lerp(from, to, i / 6)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  // How far a prompt has slid from behind its element towards its place,
  // 0 to 1 (prompts slide out; nothing fades, Q-17 A).
  double promptOut(WidgetTester tester, String key, Offset from, Offset to) {
    final Offset now = tester.getCenter(find.byKey(ValueKey(key)));
    return 1 - (now - to).distance / (from - to).distance;
  }

  group('hold mode', () {
    testWidgets('drag onto a tab and release opens it', (tester) async {
      final _Log log = await _pump(tester);
      final LauncherGeometry geometry = _geometry(4);

      final TestGesture gesture = await tester.startGesture(geometry.hubCenter);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(_tab(geometry, 1));
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pump();

      expect(log.events, ['open n1']);
      expect(find.text('Note 1'), findsNothing);
    });

    testWidgets('no Edit prompt before the hold delay; the tab label never changes', (tester) async {
      await _pump(tester);
      final LauncherGeometry geometry = _geometry(4);

      final TestGesture gesture = await tester.startGesture(geometry.hubCenter);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(_tab(geometry, 2));
      await rest(tester, 1000);
      expect(find.byKey(const ValueKey('launcher-edit-prompt')), findsNothing);

      await rest(tester, 400);
      expect(find.byKey(const ValueKey('launcher-edit-prompt')), findsOneWidget);
      expect(find.text('Note 2'), findsOneWidget);
      await gesture.up();
    });

    testWidgets('the Edit prompt slides out from under the tab and is painted below it', (tester) async {
      await _pump(tester);
      final LauncherGeometry geometry = _geometry(4);
      final Offset from = geometry.pointAt(geometry.slotAngle(2), geometry.selectedOuterRadius - 30);
      final Offset to = geometry.editPromptCenter(geometry.slotAngle(2));

      final TestGesture gesture = await tester.startGesture(geometry.hubCenter);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(_tab(geometry, 2));
      await rest(tester, 1300);
      final double early = promptOut(tester, 'launcher-edit-prompt', from, to);
      await rest(tester, 300);
      final double later = promptOut(tester, 'launcher-edit-prompt', from, to);
      expect(early, lessThan(later));
      expect(later, closeTo(1, 1e-6));
      expect(find.byType(Opacity), findsNothing);

      final Stack stack = tester.widget<Stack>(
        find.ancestor(of: find.byKey(const ValueKey('launcher-tab-n2')), matching: find.byType(Stack)).first,
      );
      final List<Key?> order = stack.children.map((child) => child.key).toList();
      expect(
        order.indexOf(const ValueKey('launcher-edit-prompt')),
        lessThan(order.indexOf(const ValueKey('launcher-tab-n2'))),
      );
      await gesture.up();
    });

    testWidgets('slide onto Edit and release edits; release without reaching it opens', (tester) async {
      final _Log log = await _pump(tester);
      final LauncherGeometry geometry = _geometry(4);
      final Offset tab = _tab(geometry, 2);
      final Offset edit = geometry.editPromptCenter(geometry.slotAngle(2));

      TestGesture gesture = await tester.startGesture(geometry.hubCenter);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(tab);
      await rest(tester);
      await moveInSteps(gesture, tester, tab, edit);
      await gesture.up();
      await tester.pump();

      gesture = await tester.startGesture(geometry.hubCenter);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(tab);
      await rest(tester);
      await gesture.up();
      await tester.pump();

      expect(log.events, ['edit n2', 'open n2']);
    });

    testWidgets('the prompt lights up with progress, and sliding back cancels edit', (tester) async {
      final _Log log = await _pump(tester);
      final LauncherGeometry geometry = _geometry(4);
      final Offset tab = _tab(geometry, 2);
      final Offset edit = geometry.editPromptCenter(geometry.slotAngle(2));

      final TestGesture gesture = await tester.startGesture(geometry.hubCenter);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(tab);
      await rest(tester);

      double scale() {
        return tester.widget<Transform>(
          find.descendant(
            of: find.byKey(const ValueKey('launcher-edit-prompt')),
            matching: find.byType(Transform),
          ).first,
        ).transform.getMaxScaleOnAxis();
      }

      final double atStart = scale();
      await gesture.moveTo(Offset.lerp(tab, edit, 0.5)!);
      await tester.pump();
      final double halfway = scale();
      await moveInSteps(gesture, tester, Offset.lerp(tab, edit, 0.5)!, edit);
      final double reached = scale();
      expect(atStart < halfway && halfway < reached, isTrue);

      await moveInSteps(gesture, tester, edit, tab);
      await gesture.up();
      await tester.pump();
      expect(log.events, ['open n2']);
    });

    testWidgets('with Edit shown, release on the hub or off the fan cancels', (tester) async {
      final _Log log = await _pump(tester);
      final LauncherGeometry geometry = _geometry(4);
      final Offset tab = _tab(geometry, 2);

      for (final Offset away in [geometry.hubCenter, const Offset(20, 20)]) {
        final TestGesture gesture = await tester.startGesture(geometry.hubCenter);
        await tester.pump(const Duration(milliseconds: 50));
        await gesture.moveTo(tab);
        await rest(tester);
        expect(find.byKey(const ValueKey('launcher-edit-prompt')), findsOneWidget);
        await moveInSteps(gesture, tester, tab, away);
        await gesture.up();
        await tester.pump();
      }

      expect(log.events, isEmpty);
      expect(find.text('Note 2'), findsNothing);
    });

    testWidgets('moving to another tab lets the prompt go', (tester) async {
      final _Log log = await _pump(tester);
      final LauncherGeometry geometry = _geometry(4);

      final TestGesture gesture = await tester.startGesture(geometry.hubCenter);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(_tab(geometry, 2));
      await rest(tester);
      expect(find.byKey(const ValueKey('launcher-edit-prompt')), findsOneWidget);
      await gesture.moveTo(_tab(geometry, 0));
      await tester.pump();
      expect(find.byKey(const ValueKey('launcher-edit-prompt')), findsNothing);
      await gesture.up();
      await tester.pump();

      expect(log.events, ['open n0']);
    });

    testWidgets('"+" comes out from under the hub and fills as the finger nears', (tester) async {
      final _Log log = await _pump(tester);
      final LauncherGeometry geometry = _geometry(4);

      TestGesture gesture = await tester.startGesture(geometry.hubCenter);
      await tester.pump(const Duration(milliseconds: 10));
      final double early =
          promptOut(tester, 'launcher-add-prompt', geometry.hubCenter, geometry.addCenter);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        early,
        lessThan(promptOut(tester, 'launcher-add-prompt', geometry.hubCenter, geometry.addCenter)),
      );
      await moveInSteps(gesture, tester, geometry.hubCenter, geometry.addCenter);
      await gesture.up();
      await tester.pump();

      gesture = await tester.startGesture(geometry.hubCenter);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(_tab(geometry, 0));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveTo(geometry.hubCenter);
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.up();
      await tester.pump();

      expect(log.events, ['new']);
    });

    testWidgets('resting at the right end scrolls; the tab there then opens', (tester) async {
      final _Log log = await _pump(tester, count: 12);
      final LauncherGeometry geometry = _geometry(12);
      final Offset rightEnd = geometry.pointAt(
        geometry.slotAngle(geometry.slotCount - 0.55),
        _config.innerRadius + _config.tabLength / 2,
      );

      final TestGesture gesture = await tester.startGesture(geometry.hubCenter);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(rightEnd);
      for (int i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await gesture.up();
      await tester.pump();

      // A prompt may have come up once scrolling stopped, but the finger
      // never went to it, so release is a plain open.
      expect(log.events, ['open n11']);
    });
  });

  group('moving the hub', () {
    testWidgets('rest on the hub: Move comes out below; release on it, then drag the hub', (tester) async {
      final _Log log = await _pump(tester);
      final LauncherGeometry geometry = _geometry(4);

      TestGesture gesture = await tester.startGesture(geometry.hubCenter);
      await rest(tester, 1000);
      expect(find.byKey(const ValueKey('launcher-move-prompt')), findsNothing);
      await rest(tester, 600);
      expect(find.byKey(const ValueKey('launcher-move-prompt')), findsOneWidget);
      // Below the hub, and painted underneath it.
      expect(geometry.movePromptCenter.dy, greaterThan(geometry.hubCenter.dy));
      await moveInSteps(gesture, tester, geometry.hubCenter, geometry.movePromptCenter);
      await gesture.up();
      await tester.pump();
      expect(find.byKey(const ValueKey('launcher-move-armed')), findsOneWidget);

      // The next drag moves the hub, then move mode ends by itself.
      gesture = await tester.startGesture(geometry.hubCenter);
      await gesture.moveTo(const Offset(100, 200));
      await tester.pump();
      expect(
        tester.getCenter(find.byKey(const ValueKey('launcher-hub'))),
        const Offset(100, 200),
      );
      await gesture.up();
      await tester.pump();

      expect(log.events, ['moved 0.25,0.25']);
      expect(find.byKey(const ValueKey('launcher-move-armed')), findsNothing);
    });

    testWidgets('releasing short of the Move prompt does nothing; tapping away cancels move mode', (tester) async {
      final _Log log = await _pump(tester);
      final LauncherGeometry geometry = _geometry(4);

      TestGesture gesture = await tester.startGesture(geometry.hubCenter);
      await rest(tester, 1600);
      await gesture.up();
      await tester.pump();
      expect(find.byKey(const ValueKey('launcher-move-armed')), findsNothing);

      gesture = await tester.startGesture(geometry.hubCenter);
      await rest(tester, 1600);
      await moveInSteps(gesture, tester, geometry.hubCenter, geometry.movePromptCenter);
      await gesture.up();
      await tester.pump();
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();

      expect(find.byKey(const ValueKey('launcher-move-armed')), findsNothing);
      expect(log.events, isEmpty);
    });

    testWidgets('a saved position is used, and the fan opens away from it', (tester) async {
      await _pump(tester, hubPosition: const Offset(0.2, 0.1));

      final Offset hub = tester.getCenter(find.byKey(const ValueKey('launcher-hub')));
      expect(hub, const Offset(86, 84));
      await tester.tap(find.byKey(const ValueKey('launcher-hub')));
      await tester.pump();
      expect(tester.getCenter(find.text('Note 2')).dy, greaterThan(hub.dy));
    });
  });

  group('overlap', () {
    testWidgets('the tab under the finger is painted on top', (tester) async {
      await _pump(tester);
      final LauncherGeometry geometry = _geometry(4);

      final TestGesture gesture = await tester.startGesture(geometry.hubCenter);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(_tab(geometry, 1));
      await tester.pump(const Duration(milliseconds: 50));

      final Stack stack = tester.widget<Stack>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('launcher-tab-n0')),
              matching: find.byType(Stack),
            )
            .first,
      );
      final List<Key?> order = stack.children.map((child) => child.key).toList();
      final int top = order.indexOf(const ValueKey('launcher-tab-n1'));
      for (final String other in ['n0', 'n2', 'n3']) {
        expect(order.indexOf(ValueKey('launcher-tab-$other')), lessThan(top));
      }
      await gesture.up();
    });
  });

  group('tap mode', () {
    testWidgets('tap the hub, tap a note to open; long-press to edit', (tester) async {
      final _Log log = await _pump(tester);

      await tester.tap(find.byKey(const ValueKey('launcher-hub')));
      await tester.pump();
      expect(find.text('Note 0'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('launcher-note-n3')));
      await tester.pump();
      expect(log.events, ['open n3']);
      expect(find.text('Note 0'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('launcher-hub')));
      await tester.pump();
      await tester.longPress(find.byKey(const ValueKey('launcher-note-n1')));
      await tester.pump();
      expect(log.events, ['open n3', 'edit n1']);
    });

    testWidgets('"+" is visible in tap mode and starts a new list', (tester) async {
      final _Log log = await _pump(tester);

      await tester.tap(find.byKey(const ValueKey('launcher-hub')));
      await tester.pump();

      final Finder add = find.byKey(const ValueKey('launcher-add'));
      final Finder icon = find.descendant(of: add, matching: find.byIcon(Icons.add));
      expect(icon, findsOneWidget);
      expect(tester.getCenter(icon), _geometry(4).addCenter);
      expect(find.byType(Opacity), findsNothing);
      expect(tester.getSize(find.ancestor(of: icon, matching: find.byType(Container)).first).width,
          greaterThan(0));

      await tester.tap(add);
      await tester.pump();
      expect(log.events, ['new']);
    });

    testWidgets('tap outside closes; "+" is inactive without onNew', (tester) async {
      final _Log log = await _pump(tester, withNew: false);

      await tester.tap(find.byKey(const ValueKey('launcher-hub')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('launcher-add')));
      await tester.pump();
      expect(log.events, isEmpty);
      expect(find.text('Note 0'), findsOneWidget);

      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      expect(find.text('Note 0'), findsNothing);
    });

    testWidgets('arrows page through many notes', (tester) async {
      await _pump(tester, count: 12);

      await tester.tap(find.byKey(const ValueKey('launcher-hub')));
      await tester.pump();
      expect(find.text('Note 0'), findsOneWidget);
      expect(find.text('Note 11'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('launcher-next')));
      await tester.pump();
      expect(find.text('Note 0'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('launcher-next')));
      await tester.pump();
      expect(find.text('Note 11'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('launcher-prev')));
      await tester.pump();
      expect(find.text('Note 11'), findsNothing);
    });

    testWidgets('keyboard: arrows move focus, Enter opens, E edits, Esc closes', (tester) async {
      final _Log log = await _pump(tester);

      await tester.tap(find.byKey(const ValueKey('launcher-hub')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(log.events, ['open n2']);

      await tester.tap(find.byKey(const ValueKey('launcher-hub')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await tester.pump();
      expect(log.events, ['open n2', 'edit n0']);

      await tester.tap(find.byKey(const ValueKey('launcher-hub')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('Note 0'), findsNothing);
    });

    testWidgets('notes have screen-reader labels', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pump(tester);

      await tester.tap(find.byKey(const ValueKey('launcher-hub')));
      await tester.pump();

      expect(find.bySemanticsLabel('Note 2, 2'), findsOneWidget);
      handle.dispose();
    });
  });
}
