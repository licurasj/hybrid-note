import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/app_colors.dart';
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
  double textScale = 1,
  Size size = const Size(400, 800),
  // To change the lists while the dial is open (as a sync would).
  ValueNotifier<List<LauncherNote>>? lists,
}) async {
  final ValueNotifier<List<LauncherNote>> notes =
      lists ?? ValueNotifier(_notes(count));
  final List<String> log = [];
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          disableAnimations: reduceMotion,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: ValueListenableBuilder<List<LauncherNote>>(
            valueListenable: notes,
            builder: (context, value, _) => DialLauncher(
              notes: value,
              onOpen: (note) => log.add('open ${note.id}'),
              onEdit: (note) => log.add('edit ${note.id}'),
              onNew: () => log.add('new'),
              onHome: inList ? () => log.add('home') : null,
              onHubMoved: (position) => log.add('moved'),
            ),
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

final Finder _movePill = find.descendant(
  of: find.byKey(const ValueKey('launcher-move-prompt')),
  matching: find.byType(Container),
);

// The app's theme in these tests is light.
final Color _dark = AppColors.neutrals(Brightness.light).promptDark;

Color _moveColor(WidgetTester tester) {
  final Container pill = tester.widget<Container>(_movePill);
  return (pill.decoration! as BoxDecoration).color!;
}

// Holds in small steps and stops on the frame Move first shows.
Future<void> _holdUntilMoveShows(WidgetTester tester) async {
  final Finder prompt = find.byKey(const ValueKey('launcher-move-prompt'));
  for (int i = 0; i < 200 && prompt.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(prompt, findsOneWidget);
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

  testWidgets('the tab under the finger is selected', (
    WidgetTester tester,
  ) async {
    final List<String> log = await _pump(tester);
    final TestGesture gesture = await _pickFirst(tester);
    final double diagonal = _diagonal(tester);
    // Later lists lie towards the bottom edge (larger angles).
    await _turn(tester, gesture, diagonal, diagonal + 1.1 * _step, 160);
    await tester.pump(const Duration(milliseconds: 300));
    // The dial does not turn under the finger: two steps on is n2, and
    // back to n1.
    await _turn(tester, gesture, diagonal + 1.1 * _step,
        diagonal + 2.1 * _step, 160);
    await tester.pump(const Duration(milliseconds: 300));
    await _turn(tester, gesture, diagonal + 2.1 * _step,
        diagonal + 1.1 * _step, 160);
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
    for (int i = 0; i < 70; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    // Scrolling, not resting: no Edit.
    expect(find.byKey(const ValueKey('dial-edit')), findsNothing);
    for (int i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await gesture.up();
    await tester.pump();
    expect(log, ['open n11']);
  });

  testWidgets('the outermost list in a scroll zone is never picked', (
    WidgetTester tester,
  ) async {
    final List<String> log = await _pump(tester, count: 12);
    final TestGesture gesture = await _pickFirst(tester);
    // Past the bottom end of the lists, then let go before any scrolling:
    // a list is picked, but a list further out is still shown (the
    // outermost one only scrolls).
    await _turn(tester, gesture, _diagonal(tester), math.pi + 0.12, 140);
    final List<int> shown = [
      for (int i = 1; i <= 12; i++)
        if (find.byKey(ValueKey('dial-entry-$i')).evaluate().isNotEmpty) i,
    ];
    await gesture.up();
    await tester.pump();
    expect(log, hasLength(1));
    final int picked = int.parse(log.single.substring('open n'.length));
    // Entry index = list index + 1.
    expect(shown.last, greaterThan(picked + 1));
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

  testWidgets('resting on the first list, next to New list, shows Edit too', (
    WidgetTester tester,
  ) async {
    for (final (int count, bool inList, Size size) in [
      (6, false, const Size(400, 800)),
      (12, false, const Size(400, 800)),
      (8, true, const Size(400, 800)),
      (8, false, const Size(411, 960)),
      (8, true, const Size(411, 960)),
      (3, false, const Size(411, 960)),
    ]) {
      final List<String> log = await _pump(
        tester,
        count: count,
        inList: inList,
        size: size,
      );
      final TestGesture gesture = await _pickFirst(tester);
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(
        find.byKey(const ValueKey('dial-edit')),
        findsOneWidget,
        reason: '$count lists, in a list: $inList, $size',
      );
      final double diagonal = _diagonal(tester);
      await _moveTo(
        tester,
        gesture,
        _at(tester, diagonal, 160),
        _at(tester, diagonal, 192),
      );
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        log,
        ['edit n0'],
        reason: '$count lists, in a list: $inList, $size',
      );
    }
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

  testWidgets('Move slides out from behind the hub, under it', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final Offset hub = _hub(tester);
    final TestGesture gesture = await tester.startGesture(hub);
    await _holdUntilMoveShows(tester);

    // It starts at the hub, small enough to be hidden by it.
    final Rect start = tester.getRect(_movePill);
    expect((start.center - hub).distance, lessThan(1));
    expect(start.width, lessThan(64));
    expect(start.height, lessThan(64));
    expect(_moveColor(tester), _dark);

    // It is painted before the hub, so the hub stays on top while it slides.
    final List<Element> stacked = [];
    void visit(Element element) {
      if (element.widget.key == const ValueKey('launcher-move-prompt') ||
          element.widget.key == const ValueKey('launcher-hub')) {
        stacked.add(element);
      }
      element.visitChildren(visit);
    }

    tester.binding.rootElement!.visitChildren(visit);
    expect(
      stacked.map((e) => e.widget.key),
      [
        const ValueKey('launcher-move-prompt'),
        const ValueKey('launcher-hub'),
      ],
    );

    // Halfway through it is on its way, and it ends further out and larger.
    await tester.pump(const Duration(milliseconds: 60));
    final Offset middle = tester.getRect(_movePill).center;
    await tester.pump(const Duration(milliseconds: 300));
    final Rect end = tester.getRect(_movePill);
    expect((middle - hub).distance, greaterThan(1));
    expect((middle - hub).distance, lessThan((end.center - hub).distance));
    expect(end.width, greaterThan(start.width));
    // Nothing has filled it: the finger has not moved.
    expect(_moveColor(tester), _dark);
    await gesture.up();
  });

  testWidgets('Move fills and grows as the finger nears, and lets go again', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final Offset hub = _hub(tester);
    final TestGesture gesture = await tester.startGesture(hub);
    await _holdUntilMoveShows(tester);
    await tester.pump(const Duration(milliseconds: 300));
    final Rect rest = tester.getRect(_movePill);
    final Offset target = rest.center;

    await _moveTo(tester, gesture, hub, Offset.lerp(hub, target, 0.5)!);
    final Color halfway = _moveColor(tester);
    expect(halfway, isNot(_dark));
    expect(halfway, isNot(AppColors.appBlue));
    expect(tester.getRect(_movePill).width, greaterThan(rest.width));

    await _moveTo(tester, gesture, Offset.lerp(hub, target, 0.5)!, hub);
    expect(_moveColor(tester), _dark);
    expect(tester.getRect(_movePill).width, rest.width);
    await gesture.up();
  });

  testWidgets('with reduced motion Move is in place at once and still fills', (
    WidgetTester tester,
  ) async {
    await _pump(tester, reduceMotion: true);
    final Offset hub = _hub(tester);
    final TestGesture gesture = await tester.startGesture(hub);
    await _holdUntilMoveShows(tester);

    final Rect first = tester.getRect(_movePill);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getRect(_movePill), first);
    expect((first.center - hub).distance, greaterThan(40));

    await _moveTo(tester, gesture, hub, Offset.lerp(hub, first.center, 0.5)!);
    expect(_moveColor(tester), isNot(_dark));
    await gesture.up();
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

  testWidgets('a list removed elsewhere during a hold keeps the pick on it', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<List<LauncherNote>> lists = ValueNotifier(_notes(4));
    final List<String> log = await _pump(tester, lists: lists);
    final TestGesture gesture = await _pickFirst(tester);
    final double diagonal = _diagonal(tester);
    await _turn(tester, gesture, diagonal, diagonal + 2.1 * _step, 160);
    await tester.pump(const Duration(milliseconds: 300));
    // n2 is selected; another device deletes n0.
    lists.value = _notes(4).sublist(1);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pump();
    expect(log, ['open n2']);
  });

  testWidgets('the selected list removed elsewhere is let go, not swapped', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<List<LauncherNote>> lists = ValueNotifier(_notes(4));
    final List<String> log = await _pump(tester, lists: lists);
    final TestGesture gesture = await _pickFirst(tester);
    final double diagonal = _diagonal(tester);
    await _turn(tester, gesture, diagonal, diagonal + 3.1 * _step, 160);
    await tester.pump(const Duration(milliseconds: 300));
    // n3, the last, is selected; it is deleted.
    lists.value = _notes(3);
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    await gesture.up();
    await tester.pump();
    expect(log, isEmpty);
  });

  testWidgets('dragging off the dial and letting go cancels', (
    WidgetTester tester,
  ) async {
    final List<String> log = await _pump(tester);
    TestGesture gesture = await _pickFirst(tester);
    // Far past the longest tab.
    await _moveTo(
      tester,
      gesture,
      _at(tester, _diagonal(tester), 160),
      const Offset(20, 20),
    );
    await gesture.up();
    await tester.pump();
    // Out past the side edge, beyond the quarter.
    gesture = await _pickFirst(tester);
    await _moveTo(
      tester,
      gesture,
      _at(tester, _diagonal(tester), 160),
      _at(tester, -0.6, 60),
    );
    await gesture.up();
    await tester.pump();
    expect(log, isEmpty);
  });

  testWidgets('tap mode reaches every list with the arrows and the keys', (
    WidgetTester tester,
  ) async {
    final List<String> log = await _pump(tester, count: 12);
    await tester.tap(find.byKey(const ValueKey('launcher-hub')));
    await tester.pumpAndSettle();
    for (int i = 0; i < 11; i++) {
      await tester.tap(find.byKey(const ValueKey('launcher-next')));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const ValueKey('launcher-note-n11')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(log, ['open n11']);

    // Keys: arrows step, E edits.
    await tester.tap(find.byKey(const ValueKey('launcher-hub')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();
    expect(log, ['open n11', 'edit n2']);

    // Enter on the closed dial opens tap mode; Esc closes it.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('launcher-barrier')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const ValueKey('launcher-barrier')), findsNothing);

    // A right-click on a tab edits it.
    await tester.tap(find.byKey(const ValueKey('launcher-hub')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('launcher-note-n0')),
      buttons: kSecondaryButton,
    );
    await tester.pump();
    expect(log, ['open n11', 'edit n2', 'edit n0']);
  });

  testWidgets('tap mode stops animating once settled', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('launcher-hub')));
    // pumpAndSettle would time out if the dial kept ticking.
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('screen readers can open the dial and each tab has its name', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    final List<String> log = await _pump(tester);
    final SemanticsNode hub =
        tester.getSemantics(find.bySemanticsLabel('Lists'));
    expect(hub.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    tester.semantics.tap(find.semantics.byLabel('Lists'));
    await tester.pumpAndSettle();

    final SemanticsNode note =
        tester.getSemantics(find.bySemanticsLabel('Note 1'));
    final SemanticsData data = note.getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.hasAction(SemanticsAction.longPress), isTrue);
    expect(find.bySemanticsLabel('New list'), findsOneWidget);
    tester.semantics.tap(find.semantics.byLabel('Note 1'));
    await tester.pump();
    expect(log, ['open n1']);
    handle.dispose();
  });

  testWidgets('at twice the text size the names fit their boxes', (
    WidgetTester tester,
  ) async {
    await _pump(tester, textScale: 2);
    await tester.tap(find.byKey(const ValueKey('launcher-hub')));
    await tester.pumpAndSettle();
    final Iterable<RenderParagraph> names = tester
        .renderObjectList<RenderParagraph>(find.textContaining('Note'));
    expect(names, isNotEmpty);
    for (final RenderParagraph name in names) {
      expect(
        name.getMaxIntrinsicHeight(double.infinity),
        lessThanOrEqualTo(name.size.height + 0.5),
      );
    }
  });

  testWidgets('New list and Home stay inside the lines of the hub edges', (
    WidgetTester tester,
  ) async {
    await _pump(tester, count: 12, inList: true);
    final Offset hub = _hub(tester);
    final TestGesture gesture = await tester.startGesture(hub);
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    // Scroll to the end so both New list and Home stop at their edges.
    await _moveTo(tester, gesture, hub, _at(tester, _diagonal(tester), 160));
    await _turn(tester, gesture, _diagonal(tester), math.pi - 0.05, 160);
    for (int i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    // The painted bounds are inflated by 2.
    final Rect add = tester.getRect(find.byKey(const ValueKey('dial-entry-0')));
    final Rect home =
        tester.getRect(find.byKey(const ValueKey('dial-entry-13')));
    expect(add.right, lessThanOrEqualTo(hub.dx + 32 + 2.5));
    expect(home.bottom, lessThanOrEqualTo(hub.dy + 32 + 2.5));
    await gesture.up();
  });

  testWidgets('selecting New list does not enlarge the list beside it', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final TestGesture gesture = await _pickFirst(tester);
    final double first =
        tester.getSize(find.byKey(const ValueKey('dial-entry-1'))).height;
    await _turn(tester, gesture, _diagonal(tester), math.pi / 2 + 0.05, 160);
    await tester.pump(const Duration(milliseconds: 400));
    final double beside =
        tester.getSize(find.byKey(const ValueKey('dial-entry-1'))).height;
    expect(beside, lessThan(first - 20));
    await gesture.up();
  });

  // The highest list entry shown on the dial.
  int shownMax(WidgetTester tester) => [
        for (int i = 1; i <= 12; i++)
          if (find.byKey(ValueKey('dial-entry-$i')).evaluate().isNotEmpty) i,
      ].last;

  testWidgets('scrolling starts as soon as the finger is in a zone', (
    WidgetTester tester,
  ) async {
    await _pump(tester, count: 12);
    final TestGesture gesture = await _pickFirst(tester);
    await tester.pump(const Duration(milliseconds: 100));
    final int before = shownMax(tester);
    await gesture.moveTo(_at(tester, math.pi - 0.05, 160));
    // Within 250 ms (the old delay alone was 300 ms) lists have come in.
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(shownMax(tester), greaterThan(before));
    await gesture.up();
  });

  testWidgets('a fast swipe towards an end reaches its zone sooner', (
    WidgetTester tester,
  ) async {
    await _pump(tester, count: 12);
    // Short of the bottom zone: turning slowly there does not scroll...
    TestGesture gesture = await _pickFirst(tester);
    final double diagonal = _diagonal(tester);
    const double short = math.pi - 0.45;
    // The dial reads the finger's speed from the events' time stamps.
    Duration clock = const Duration(seconds: 1);
    for (int i = 1; i <= 40; i++) {
      clock += const Duration(milliseconds: 60);
      await gesture.moveTo(
        _at(tester, diagonal + (short - diagonal) * i / 40, 160),
        timeStamp: clock,
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pump(const Duration(milliseconds: 100));
    final int slow = shownMax(tester);
    await gesture.moveTo(_hub(tester));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));

    // ...swiping there fast does.
    gesture = await _pickFirst(tester);
    clock += const Duration(seconds: 1);
    for (int i = 1; i <= 3; i++) {
      clock += const Duration(milliseconds: 16);
      await gesture.moveTo(
        _at(tester, diagonal + (short - diagonal) * i / 3, 160),
        timeStamp: clock,
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(shownMax(tester), greaterThan(slow));
    await gesture.up();
  });
}
