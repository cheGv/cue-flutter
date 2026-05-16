// test/phase_4_1_9_reproduction_test.dart
//
// Phase 4.1.9 — dispose-side symmetric twin of Phase 4.1.6's
// setState-during-build. The chart screen's `dispose()` calls
// `cueHoldController.clearClientContext()` (and conditionally
// `c.toIdle()`) synchronously while the tree is being unmounted by
// the scheduler's persistent-callbacks phase. The controller's
// synchronous `notifyListeners()` marks the AnimatedBuilder inside
// the globally-mounted CueHold dirty, but the tree is locked for
// teardown — Flutter asserts.
//
// This test mounts a sibling that:
//   - sets client context post-frame (matches the 4.1.6 fix at the
//     initState side; safe; never throws)
//   - then on dispose calls clearClientContext() synchronously
//     (matches the production chart screen's dispose body)
//
// We then replace the widget tree so the sibling is unmounted —
// firing its dispose. With CueHold still listening, the synchronous
// notify during teardown is exactly the production failure.
//
// Gate: this test MUST FAIL before the Part 2 fix is applied
// (assertion captured by tester.takeException()), then PASS after
// the controller-side schedulerPhase-aware notify lands.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cue/widgets/cue_hold/cue_hold.dart';
import 'package:cue/widgets/cue_hold/cue_hold_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cueHoldController.toIdle();
    cueHoldController.clearClientContext();
  });

  testWidgets(
    'clearClientContext during dispose must not throw setState-during-build',
    (tester) async {
      // Mount with the sibling that holds client context.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              const Expanded(child: CueHold()),
              Expanded(child: _DisposeClearsContextSibling()),
            ],
          ),
        ),
      ));
      // Frame 1 runs initState (schedules post-frame). Frame 2 fires
      // the post-frame callback (setClientContext). Both are safe per
      // 4.1.6.
      await tester.pump();
      await tester.pump();

      // Drain any pre-existing exceptions so we only capture what
      // happens during the upcoming tree teardown.
      tester.takeException();

      // Tree replacement — the sibling unmounts (dispose called).
      // CueHold is still in the tree (still listening to the
      // controller). The sibling's dispose() body runs
      // clearClientContext() synchronously — exactly the production
      // chart screen pattern at client_profile_screen.dart:165–177.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              const Expanded(child: CueHold()),
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ),
      ));
      await tester.pump();

      final ex = tester.takeException();
      expect(
        ex,
        isNull,
        reason: 'Synchronous clearClientContext() in dispose must not '
            'fire notifyListeners while the tree is locked for teardown '
            '(this is the Phase 4.1.9 dispose-side twin of the 4.1.6 '
            'setState-during-build fix).',
      );
    },
  );
}

class _DisposeClearsContextSibling extends StatefulWidget {
  @override
  State<_DisposeClearsContextSibling> createState() =>
      _DisposeClearsContextSiblingState();
}

class _DisposeClearsContextSiblingState
    extends State<_DisposeClearsContextSibling> {
  @override
  void initState() {
    super.initState();
    // 4.1.6 — deferred set is safe.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      cueHoldController.setClientContext(
        clientId: 'test-client',
        clientName: 'Test Client',
      );
    });
  }

  @override
  void dispose() {
    // 4.1.9 — production pattern: synchronous clear inside dispose.
    // This is the buggy path the controller-side fix must neutralize.
    cueHoldController.clearClientContext();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
