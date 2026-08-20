import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/theme/app_colors.dart';
import 'package:prop_intelligence/widgets/prop_research_controls.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required bool open}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResearchToggle(open: open, onTap: () {}),
          ),
        ),
      );

  testWidgets('a closed card says what opening will show', (tester) async {
    // Two small gold words read as a caption rather than a control, so
    // people did not know the evidence was there at all.
    await pump(tester, open: false);

    expect(find.text('OPEN RESEARCH'), findsOneWidget);
    expect(find.text('projection, evidence, risk'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
  });

  testWidgets('an open card offers to put it away again', (tester) async {
    await pump(tester, open: true);

    expect(find.text('CLOSE RESEARCH'), findsOneWidget);
    expect(find.text('shorter card'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
  });

  testWidgets('it is announced as an expander, not a label', (tester) async {
    await pump(tester, open: false);

    final semantics = tester.getSemantics(find.byType(ResearchToggle));
    expect(semantics.label, contains('Open research'));
  });

  testWidgets('it carries the board gold', (tester) async {
    await pump(tester, open: false);

    final text = tester.widget<Text>(find.text('OPEN RESEARCH'));
    expect(text.style?.color, AppColors.gold);

    final icons = tester.widgetList<Icon>(find.byType(Icon));
    expect(icons.every((icon) => icon.color == AppColors.gold), isTrue);
  });

  testWidgets('the whole width is tappable', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: ResearchToggle(open: false, onTap: () => taps++),
          ),
        ),
      ),
    );

    // Far from the label, still inside the control.
    await tester.tapAt(
      tester.getTopLeft(find.byType(ResearchToggle)) + const Offset(20, 14),
    );
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('it survives a narrow card without overflowing', (tester) async {
    // Cards are capped at 270px and go narrower in a phone's single column.
    // The first version overflowed by 6.6px at 400.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 210,
            child: ResearchToggle(open: false, onTap: _noop),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('OPEN RESEARCH'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
  });
}

void _noop() {}
