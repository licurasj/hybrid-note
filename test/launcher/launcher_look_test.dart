import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hybrid_note/app/app_theme.dart';
import 'package:hybrid_note/app_colors.dart';
import 'package:hybrid_note/launcher/launcher_geometry.dart';
import 'package:hybrid_note/launcher/radial_launcher.dart';

// The launcher's look and motion in direction A "Eclipse" (T-16 unit 5):
// eclipse hub, pill tabs with the list's colour disc, the selected tab
// biggest, tabs growing out from under the hub, prompts sliding out and
// filling with colour, nothing fading, nothing moving with reduced motion.

const LauncherConfig _config = LauncherConfig();
const Color _orange = Color(0xFFFF4D12);
const Color _orangeDark = Color(0xFFFF6A3D);

List<LauncherNote> _notes(int count) {
  return [
    for (int i = 0; i < count; i++)
      LauncherNote(
        id: 'n$i',
        label: 'Note $i',
        icon: Icons.list,
        color: _orange,
        semanticsLabel: 'Note $i',
      ),
  ];
}

Future<void> _pump(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(400, 800),
          disableAnimations: reduceMotion,
        ),
        child: Scaffold(
          body: RadialLauncher(
            notes: _notes(5),
            onOpen: (_) {},
            onEdit: (_) {},
            onNew: () {},
            onHubMoved: (_) {},
          ),
        ),
      ),
    ),
  );
}

final LauncherGeometry _geometry = LauncherGeometry(
  config: _config,
  size: const Size(400, 800),
  noteCount: 5,
);

Color _fill(WidgetTester tester, String key) {
  final Container pill = tester.widget(find.byKey(ValueKey('$key-fill')));
  return (pill.decoration! as BoxDecoration).color!;
}

double _tabScale(WidgetTester tester, String id) {
  return tester
      .widget<AnimatedScale>(find.byKey(ValueKey('launcher-tab-scale-$id')))
      .scale;
}

Future<void> _rest(WidgetTester tester, [int ms = 1400]) async {
  for (int i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('the hub is a text-colour disc over a blue one, offset towards the fan', (
    tester,
  ) async {
    await _pump(tester);

    final Container front = tester.widget(find.byKey(const ValueKey('launcher-hub')));
    expect((front.decoration! as BoxDecoration).color, AppNeutrals.light.text);
    final DecoratedBox back =
        tester.widget(find.byKey(const ValueKey('launcher-hub-back')));
    expect((back.decoration as BoxDecoration).color, AppColors.appBlue);
    // Hub near the bottom-right corner: the blue disc peeks out up and left.
    final Offset hub = tester.getCenter(find.byKey(const ValueKey('launcher-hub')));
    final Offset blue = tester.getCenter(find.byKey(const ValueKey('launcher-hub-back')));
    expect(hub, _geometry.hubCenter);
    expect(blue.dx, lessThan(hub.dx));
    expect(blue.dy, lessThan(hub.dy));
  });

  testWidgets('tabs grow out from under the hub, one slightly after another', (
    tester,
  ) async {
    await _pump(tester);
    final TestGesture gesture = await tester.startGesture(_geometry.hubCenter);
    await tester.pump(const Duration(milliseconds: 40));

    double out(String id) =>
        (tester.getCenter(find.byKey(ValueKey('launcher-tab-$id'))) -
                _geometry.hubCenter)
            .distance;
    final double full = _config.innerRadius + _config.tabLength / 2;
    final double first = out('n0');
    final double last = out('n4');
    expect(first, lessThan(full));
    // Later tabs start later (16 ms stagger), so they are further behind.
    expect(last, lessThan(first));

    await tester.pump(const Duration(milliseconds: 300));
    expect(out('n0'), closeTo(full, 0.5));
    expect(out('n4'), closeTo(full, 0.5));
    expect(find.byType(Opacity), findsNothing);
    expect(find.byType(FadeTransition), findsNothing);
    await gesture.up();
  });

  testWidgets('the tab under the finger is biggest, its neighbours a little bigger', (
    tester,
  ) async {
    await _pump(tester);
    final TestGesture gesture = await tester.startGesture(_geometry.hubCenter);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(_geometry.tabCenter(2, 0)!);
    await tester.pump(const Duration(milliseconds: 300));

    expect(_tabScale(tester, 'n2'), _config.selectedTabScale);
    expect(_tabScale(tester, 'n1'), _config.neighbourTabScale);
    expect(_tabScale(tester, 'n3'), _config.neighbourTabScale);
    expect(_tabScale(tester, 'n0'), 1);
    expect(_tabScale(tester, 'n4'), 1);
    expect(_config.selectedTabScale, 1.22);
    expect(_config.neighbourTabScale, 1.08);
    await gesture.up();
  });

  testWidgets('Edit starts dark and fills with the list colour as the finger nears', (
    tester,
  ) async {
    await _pump(tester);
    final Offset tab = _geometry.tabCenter(2, 0)!;
    final Offset edit = _geometry.editPromptCenter(_geometry.slotAngle(2));
    final TestGesture gesture = await tester.startGesture(_geometry.hubCenter);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(tab);
    await _rest(tester);

    expect(_fill(tester, 'launcher-edit-prompt'), AppNeutrals.light.promptDark);
    for (int i = 1; i <= 6; i++) {
      await gesture.moveTo(Offset.lerp(tab, edit, i / 6)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(_fill(tester, 'launcher-edit-prompt'), _orange);
    await gesture.up();
  });

  testWidgets('"+" fills with the app blue; in dark the tab disc is the dark variant', (
    tester,
  ) async {
    await _pump(tester, brightness: Brightness.dark);
    final TestGesture gesture = await tester.startGesture(_geometry.hubCenter);
    await tester.pump(const Duration(milliseconds: 300));
    expect(_fill(tester, 'launcher-add-prompt'), AppNeutrals.dark.promptDark);

    final Iterable<Color?> discs = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byKey(const ValueKey('launcher-tab-n0')),
            matching: find.byType(Container),
          ),
        )
        .map((c) => (c.decoration as BoxDecoration?)?.color);
    expect(discs, contains(_orangeDark));
    expect(discs, isNot(contains(_orange)));

    for (int i = 1; i <= 6; i++) {
      await gesture.moveTo(
        Offset.lerp(_geometry.hubCenter, _geometry.addCenter, i / 6)!,
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(_fill(tester, 'launcher-add-prompt'), AppColors.appBlue);
    await gesture.up();
  });

  testWidgets('with reduced motion, tabs and prompts are in place at once', (
    tester,
  ) async {
    await _pump(tester, reduceMotion: true);
    final TestGesture gesture = await tester.startGesture(_geometry.hubCenter);
    await tester.pump();

    expect(
      tester.getCenter(find.byKey(const ValueKey('launcher-tab-n4'))),
      offsetMoreOrLessEquals(_geometry.tabCenter(4, 0)!, epsilon: 0.5),
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('launcher-add-prompt'))),
      offsetMoreOrLessEquals(_geometry.addCenter, epsilon: 0.5),
    );

    // The Move prompt is already out the frame it appears.
    await _rest(tester, 1300);
    expect(
      tester.getCenter(find.byKey(const ValueKey('launcher-move-prompt'))),
      offsetMoreOrLessEquals(_geometry.movePromptCenter, epsilon: 0.5),
    );
    await gesture.up();
  });
}
