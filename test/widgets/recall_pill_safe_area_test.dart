import 'package:cue/widgets/recall_assistant/recall_pill_safe_area.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('recall pill safe-area constants', () {
    test('reserved width clears footprint + corner margin', () {
      expect(
        kRecallPillReservedWidth,
        greaterThanOrEqualTo(
            kRecallPillFootprint.width + kRecallPillMargin),
      );
    });

    test('reserved height clears footprint + corner margin', () {
      expect(
        kRecallPillReservedHeight,
        greaterThanOrEqualTo(
            kRecallPillFootprint.height + kRecallPillMargin),
      );
    });

    test('safe-area Size mirrors the width/height constants', () {
      expect(kRecallPillSafeArea.width, kRecallPillReservedWidth);
      expect(kRecallPillSafeArea.height, kRecallPillReservedHeight);
    });
  });

  group('RecallPillSafeArea widget', () {
    // Pump inside a fixed-width box so the adaptive LayoutBuilder gets finite
    // constraints (mirrors a real bottom bar inside a sized scaffold).
    Future<EdgeInsets> insetsFor(WidgetTester tester, Widget w,
        {required double width}) async {
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, height: 200, child: w),
        ),
      ));
      final padding = tester.widget<Padding>(
        find.descendant(
            of: find.byType(RecallPillSafeArea),
            matching: find.byType(Padding)),
      );
      return padding.padding.resolve(TextDirection.ltr);
    }

    testWidgets('wide: reserves the right edge by default (full pill width)',
        (tester) async {
      final insets = await insetsFor(
          tester, const RecallPillSafeArea(child: SizedBox()),
          width: 1000);
      expect(insets.right, kRecallPillReservedWidth);
      expect(insets.bottom, 0);
    });

    testWidgets('narrow: falls back to a bottom reservation (no overflow)',
        (tester) async {
      // 420 − 200 = 220 < 360 min content width → lift instead of inset.
      final insets = await insetsFor(
          tester, const RecallPillSafeArea(child: SizedBox()),
          width: 420);
      expect(insets.right, 0);
      expect(insets.bottom, kRecallPillReservedHeight);
    });

    testWidgets('reserveBottom pads the bottom regardless of width',
        (tester) async {
      final insets = await insetsFor(
        tester,
        const RecallPillSafeArea(
            reserveRight: false, reserveBottom: true, child: SizedBox()),
        width: 1000,
      );
      expect(insets.bottom, kRecallPillReservedHeight);
      expect(insets.right, 0);
    });
  });
}
