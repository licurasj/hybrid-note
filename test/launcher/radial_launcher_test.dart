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

// The hold before a prompt, in milliseconds.
final int _promptMs = const LauncherConfig().promptDelay.inMilliseconds;

void main() {
  group('geometry', () {
    final LauncherGeometry geometry = _geometry(12);

    test('hub near the bottom-right corner; New list is the last wedge', () {
      expect(geometry.hubCenter, const Offset(400 - 56, 800 - 72));
      expect(geometry.addSides.$1, closeTo(geometry.listEndAngle, 1e-9));
      expect(geometry.addSides.$2, closeTo(geometry.endAngle, 1e-9));
      // Nearly straight up from the hub, at the side edge's end of the fan.
      expect(geometry.addCenter.dy, lessThan(geometry.hubCenter.dy - 50));
      expect(geometry.addCenter.dx, closeTo(geometry.hubCenter.dx, 20));
    });

    test('wedges share the whole quarter, from the bottom edge to the right edge', () {
      expect(geometry.startAngle, closeTo(3.14159265, 1e-6));
      expect(geometry.endAngle, closeTo(3.14159265 / 2, 1e-6));

      final Offset first = _tab(geometry, 0);
      final Offset last = _tab(geometry, geometry.slotCount - 1);
      // First tab points mostly left, the last mostly up; all stay on screen.
      // Neighbouring wedges meet without overlapping, the first along the
      // bottom, the last pointing straight up.
      expect(geometry.tabSides(0, 0)!.$1, closeTo(geometry.startAngle, 1e-9));
      expect(geometry.tabSides(3, 0)!.$2, closeTo(geometry.listEndAngle, 1e-9));
      for (int i = 0; i < geometry.slotCount - 1; i++) {
        expect(geometry.tabSides(i, 0)!.$2, closeTo(geometry.tabSides(i + 1, 0)!.$1, 1e-9));
      }
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
      // Tabs go right and down; New list, last, points down.
      expect(topLeft.addCenter.dy, greaterThan(topLeft.hubCenter.dy + 50));
      expect(_tab(topLeft, 2).dx, greaterThan(topLeft.hubCenter.dx));
      expect(_tab(topLeft, 2).dy, greaterThan(topLeft.hubCenter.dy));
      expect(topLeft.hitTest(_tab(topLeft, 2), 0),
          const LauncherTarget(LauncherTargetKind.note, 2));

      final LauncherGeometry bottomLeft = _geometry(12, hub: const Offset(56, 728));
      expect(_tab(bottomLeft, 2).dx, closeTo(400 - _tab(geometry, 2).dx, 1e-9));
    });

    test('a moved hub stays inside the screen margins', () {
      final LauncherGeometry outside = _geometry(4, hub: const Offset(-50, 900));
      // Room for the hub and the blue disc behind it; the Move prompt stays
      // on screen.
      expect(outside.hubCenter, const Offset(48, 800 - 48));
      expect(outside.movePromptCenter.dy + 18, lessThanOrEqualTo(800));
      expect(outside.movePromptCenter.dx - 36, greaterThanOrEqualTo(0));
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

    test('the selected tab widens and lengthens; its neighbours a little', () {
      final LauncherGeometry spread = LauncherGeometry(
        config: _config,
        size: const Size(400, 800),
        noteCount: 12,
        focus: 2,
      );
      double width(LauncherGeometry g, int i) {
        final (double, double) sides = g.tabSides(i, 0)!;
        return sides.$1 - sides.$2;
      }

      // The fan keeps its ends.
      expect(spread.tabSides(0, 0)!.$1, closeTo(spread.startAngle, 1e-9));
      expect(spread.tabSides(3, 0)!.$2, closeTo(spread.listEndAngle, 1e-9));
      expect(width(spread, 2) / width(spread, 0), closeTo(_config.selectedSpread, 0.05));
      expect(width(spread, 1), greaterThan(width(spread, 0)));
      expect(width(spread, 1), lessThan(width(spread, 2)));
      expect(width(spread, 2), greaterThan(width(geometry, 2)));
      // Hit testing follows the wedges as drawn: a point just inside the
      // widened tab 2 that used to be tab 1 is now tab 2.
      final double edge = spread.tabSides(2, 0)!.$1 - 0.01;
      expect(
        spread.hitTest(spread.pointAt(edge, _config.innerRadius + 60), 0),
        const LauncherTarget(LauncherTargetKind.note, 2),
      );
      expect(
        geometry.hitTest(geometry.pointAt(edge, _config.innerRadius + 60), 0),
        const LauncherTarget(LauncherTargetKind.note, 1),
      );

      expect(spread.tabScale(2), _config.selectedTabScale);
      expect(spread.tabScale(1), closeTo(_config.neighbourTabScale, 1e-9));
      expect(spread.tabScale(3), closeTo(_config.neighbourTabScale, 1e-9));
      expect(spread.tabScale(0), 1);
      expect(geometry.tabScale(2), 1);
    });

    test('Edit lies along its spoke, pulled in when the screen ends', () {
      for (int i = 0; i < geometry.slotCount; i++) {
        final double angle = geometry.slotAngle(i.toDouble());
        final Offset edit = geometry.editPromptCenter(angle);
        final Offset onSpoke = geometry.pointAt(
          angle,
          (edit - geometry.hubCenter).distance,
        );
        expect(edit, offsetMoreOrLessEquals(onSpoke, epsilon: 0.5));
        expect(
          (edit - geometry.hubCenter).distance,
          greaterThanOrEqualTo(geometry.selectedOuterRadius),
        );
      }
    });

    test('inside a list the fan starts with a Home wedge', () {
      final LauncherGeometry withHome = LauncherGeometry(
        config: _config,
        size: const Size(400, 800),
        noteCount: 12,
        showHome: true,
      );
      expect(withHome.homeSides.$1, closeTo(withHome.startAngle, 1e-9));
      expect(withHome.tabSides(0, 0)!.$1, closeTo(withHome.listStartAngle, 1e-9));
      expect(withHome.hitTest(withHome.homeCenter, 0), LauncherTarget.home);
      expect(withHome.hitTest(withHome.addCenter, 0), LauncherTarget.add);
      expect(withHome.hitTest(withHome.tabCenter(0, 0)!, 0),
          const LauncherTarget(LauncherTargetKind.note, 0));
      // Home never scrolls the lists; without it the same spot is the start
      // zone.
      expect(withHome.scrollVelocity(withHome.homeCenter), 0);
      expect(geometry.hitTest(withHome.homeCenter, 0), isNot(LauncherTarget.home));
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
      await rest(tester, _promptMs - 200);
      expect(find.byKey(const ValueKey('launcher-edit-prompt')), findsNothing);

      await rest(tester, 400);
      expect(find.byKey(const ValueKey('launcher-edit-prompt')), findsOneWidget);
      expect(find.text('Note 2'), findsOneWidget);
      await gesture.up();
    });

    testWidgets('the Edit prompt slides out from under the tab and is painted below it', (tester) async {
      await _pump(tester);
      final LauncherGeometry geometry = _geometry(4);
      // Edit is a further piece of the tab's wedge, moving out along its
      // spoke.
      double out() =>
          (tester.getCenter(find.byKey(const ValueKey('launcher-edit-prompt'))) -
                  geometry.hubCenter)
              .distance;

      final TestGesture gesture = await tester.startGesture(geometry.hubCenter);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(_tab(geometry, 2));
      await rest(tester, _promptMs + 100);
      final double early = out();
      await rest(tester, 300);
      final double later = out();
      expect(early, lessThan(later));
      expect(later, closeTo(geometry.editRadius, 8));
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

      // The segment deepens as the finger comes.
      double scale() {
        final Size size = tester.getSize(find.byKey(const ValueKey('launcher-edit-prompt')));
        return size.width * size.height;
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

    testWidgets('"+" is the last wedge: release on it for a new list', (tester) async {
      final _Log log = await _pump(tester);
      final LauncherGeometry geometry = _geometry(4);

      TestGesture gesture = await tester.startGesture(geometry.hubCenter);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('launcher-add-tab')), findsOneWidget);
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
    testWidgets('rest on the hub: Move comes out below; reaching it picks the hub up until release', (tester) async {
      final _Log log = await _pump(tester);
      final LauncherGeometry geometry = _geometry(4);

      final TestGesture gesture = await tester.startGesture(geometry.hubCenter);
      await rest(tester, _promptMs - 200);
      expect(find.byKey(const ValueKey('launcher-move-prompt')), findsNothing);
      await rest(tester, 600);
      expect(find.byKey(const ValueKey('launcher-move-prompt')), findsOneWidget);
      // Below the hub, and painted underneath it.
      expect(geometry.movePromptCenter.dy, greaterThan(geometry.hubCenter.dy));
      await moveInSteps(gesture, tester, geometry.hubCenter, geometry.movePromptCenter);
      // Picked up: the fan and the prompt are gone, the hub follows the
      // finger at the same distance in the same gesture.
      expect(find.byKey(const ValueKey('launcher-move-prompt')), findsNothing);
      expect(find.text('Note 0'), findsNothing);
      // Lift it clear of the bottom margin, then measure the grip.
      final Offset finger = geometry.movePromptCenter - const Offset(0, 100);
      await moveInSteps(gesture, tester, geometry.movePromptCenter, finger);
      final Offset grabbed = tester.getCenter(find.byKey(const ValueKey('launcher-hub')));
      expect(grabbed.dy, lessThan(geometry.hubCenter.dy));
      final Offset target = const Offset(100, 200) - (grabbed - finger);
      await moveInSteps(gesture, tester, finger, target);
      expect(
        tester.getCenter(find.byKey(const ValueKey('launcher-hub'))),
        offsetMoreOrLessEquals(const Offset(100, 200), epsilon: 0.5),
      );
      await gesture.up();
      await tester.pump();

      expect(log.events, ['moved 0.25,0.25']);
    });

    testWidgets('releasing short of the Move prompt does nothing', (tester) async {
      final _Log log = await _pump(tester);
      final LauncherGeometry geometry = _geometry(4);

      TestGesture gesture = await tester.startGesture(geometry.hubCenter);
      await rest(tester, 1600);
      await gesture.up();
      await tester.pump();

      gesture = await tester.startGesture(geometry.hubCenter);
      await rest(tester, 1600);
      await moveInSteps(
        gesture,
        tester,
        geometry.hubCenter,
        Offset.lerp(geometry.hubCenter, geometry.movePromptCenter, 0.3)!,
      );
      await gesture.up();
      await tester.pump();

      expect(log.events, isEmpty);
      expect(tester.getCenter(find.byKey(const ValueKey('launcher-hub'))), geometry.hubCenter);
    });

    testWidgets('a saved position is used, and the fan opens away from it', (tester) async {
      await _pump(tester, hubPosition: const Offset(0.2, 0.1));

      final Offset hub = tester.getCenter(find.byKey(const ValueKey('launcher-hub')));
      expect(hub, const Offset(80, 80));
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
      expect(add, findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byType(Opacity), findsNothing);

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
