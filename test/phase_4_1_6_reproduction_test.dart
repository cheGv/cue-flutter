// test/phase_4_1_6_reproduction_test.dart
//
// Phase 4.1.6 — reproduction tests for the two production exceptions
// observed in DevTools console after the 4.1.3/4.1.4 Hold refactor:
//
//   1. "setState() / markNeedsBuild() called during build" (fires
//      thousands of times — strongly suggests a controller is
//      notifying listeners synchronously while a widget that subscribes
//      to it is mid-build, OR while the framework is in build/dispose
//      phase from a parent.)
//
//   2. "RenderFlex children have non-zero flex but incoming height
//      constraints are unbounded" (a Column / Row with Expanded inside
//      a parent that gives unbounded main-axis space.)
//
// Each test below mounts the suspected site in isolation and asserts
// `tester.takeException()` returns null. Failing assertions print the
// full stack trace, which is the trace we'll quote in the report.
//
// These tests are STRUCTURAL — they don't need network, Supabase auth,
// or the headless 2px browser viewport. They run under `flutter test`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cue/widgets/chart/chart_goal_ladder.dart';
import 'package:cue/widgets/cue_hold/cue_hold.dart';
import 'package:cue/widgets/cue_hold/cue_hold_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cueHoldController.toIdle();
    cueHoldController.clearClientContext();
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Reproduction 1 — setState during build.
  //
  // Mount the global CueHold (which subscribes to cueHoldController via
  // AnimatedBuilder) alongside a sibling whose initState mutates the
  // controller. initState runs while the parent route is being built;
  // calling setClientContext → notifyListeners() then markNeedsBuild's
  // any AnimatedBuilder subscriber that's currently being laid out.
  // ───────────────────────────────────────────────────────────────────────────
  testWidgets('setState during build — setClientContext from initState',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 56,
          child: Row(
            children: [
              const Expanded(child: CueHold()),
              Expanded(child: _CallsSetClientContextInInitState()),
            ],
          ),
        ),
      ),
    ));
    // First pump runs initState (which schedules the post-frame
    // callback). Second pump fires the callback. takeException then
    // sees any setState-during-build leak.
    await tester.pump();
    await tester.pump();
    final ex = tester.takeException();
    expect(ex, isNull, reason: 'setClientContext deferred to post-frame '
        'should not throw setState-during-build');
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Reproduction 2 — RenderFlex with unbounded height.
  //
  // ChartGoalLadder's compact STG section uses a LayoutBuilder gate at
  // 1024px to switch between desktop (horizontal scroll inside
  // SizedBox(height: 120)) and tablet/mobile (vertical Column of
  // full-width cards). On the tablet/mobile branch, each _CompactStgCard
  // renders Container(width: null) with a Column inside that contains
  // an `Expanded(Text(...))`. When the LADDER is hosted inside a
  // SliverToBoxAdapter (the chart screen's actual layout), the Column
  // inherits unbounded vertical → Expanded throws.
  //
  // This test mounts ChartGoalLadder inside a CustomScrollView with 3+
  // active STGs, at a viewport width < 1024 so the tablet/mobile branch
  // fires. Sample data has one active LTG + a focused STG + several
  // compact siblings to exercise the compact list.
  // ───────────────────────────────────────────────────────────────────────────
  testWidgets('RenderFlex unbounded — compact STG card inside SliverAdapter',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1200); // tablet width < 1024
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: ChartGoalLadder(
                clientId: 'test-client',
                ltgs: _sampleLtgs(),
                stgs: _sampleStgs(),
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final ex = tester.takeException();
    expect(ex, isNull, reason: 'compact STG card inside SliverAdapter '
        'should not throw RenderFlex unbounded');
  });
}

class _CallsSetClientContextInInitState extends StatefulWidget {
  @override
  State<_CallsSetClientContextInInitState> createState() =>
      _CallsSetClientContextInInitStateState();
}

class _CallsSetClientContextInInitStateState
    extends State<_CallsSetClientContextInInitState> {
  @override
  void initState() {
    super.initState();
    // Phase 4.1.6 — production fix: defer setClientContext to
    // post-frame so notifyListeners() doesn't mark mounted listeners
    // dirty mid-build. This mirrors the patched client_profile_screen
    // initState exactly.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      cueHoldController.setClientContext(
        clientId: 'test-client',
        clientName: 'Test Client',
      );
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

List<Map<String, dynamic>> _sampleLtgs() {
  return [
    {
      'id': 'ltg-1',
      'client_id': 'test-client',
      'goal_text': 'Improve swallow safety across PO trials.',
      'domain': 'DYSPH',
      'status': 'active',
      'sequence_num': 1,
    },
  ];
}

List<Map<String, dynamic>> _sampleStgs() {
  return [
    {
      'id': 'stg-focused',
      'client_id': 'test-client',
      'long_term_goal_id': 'ltg-1',
      'target_behavior': 'Initiate CTAR exercise 3 sets of 10 daily',
      'domain': 'DYSPH',
      'status': 'active',
      'sequence_num': 1,
      'updated_at': '2026-05-10T00:00:00Z',
    },
    {
      'id': 'stg-compact-1',
      'client_id': 'test-client',
      'long_term_goal_id': 'ltg-1',
      'target_behavior': 'Maintain head-of-bed >30deg during PO intake',
      'domain': 'DYSPH',
      'status': 'active',
      'sequence_num': 2,
      'updated_at': '2026-05-08T00:00:00Z',
    },
    {
      'id': 'stg-compact-2',
      'client_id': 'test-client',
      'long_term_goal_id': 'ltg-1',
      'target_behavior': 'Chin tuck on every bolus, 80% accuracy',
      'domain': 'DYSPH',
      'status': 'active',
      'sequence_num': 3,
      'updated_at': '2026-05-06T00:00:00Z',
    },
  ];
}
