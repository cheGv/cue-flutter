// test/protocols/draft_gate_test.dart
//
// The four refusals must stay DISTINCT — they differ in who can act and
// on what, and collapsing any pair sends the clinician at the wrong
// problem. These tests pin that, plus the anomaly refusal's precedence
// and its wording (it must NAME the section and offer the repair).
//
// evaluateDraftGate is pure, so the decision is testable without mounting
// a screen — and there is exactly one place it is computed.

import 'package:flutter_test/flutter_test.dart';

import 'package:cue/protocols/draft_gate.dart';
import 'package:cue/protocols/protocol_manifest.dart';
import 'package:cue/widgets/assessment/sectional_capture.dart';

const _labels = {
  'speech': 'Speech',
  'language': 'Language',
  'literacy': 'Literacy',
};

/// An area with a capture surface but NO reader — the input that produces
/// DraftRefusal.noReader.
///
/// This used to be 'pediatric-language', until its reader landed on
/// 2026-08-02 and these tests went red. That was the suite working: the gate
/// really does read the manifest. Guarded below so the next reader to land
/// fails with an explanatory message rather than a bare enum mismatch.
const _readerlessArea = 'pediatric-dysarthria';

SectionalCompletionAnomaly anomaly(String section, List<String> rows) =>
    SectionalCompletionAnomaly(sectionId: section, unmarkedRowIds: rows);

void main() {
  group('the fixtures these tests depend on', () {
    test('the readerless exemplar really has a surface and really has no '
        'reader — if this fails, a reader landed and the noReader cases '
        'below need a new exemplar', () {
      final entry = protocolsForArea(_readerlessArea);
      expect(entry, isNotEmpty,
          reason: '$_readerlessArea must still have a capture surface');
      expect(entry.any((p) => p.isDraftable), isFalse,
          reason: '$_readerlessArea gained a reader; pick another '
              'readerless area for _readerlessArea');
    });

    test('pediatric-language now drafts — the reader landed 2026-08-02', () {
      final d = evaluateDraftGate(
          clinicalArea: 'pediatric-language', anomalies: const []);
      expect(d.canDraft, isTrue);
      expect(d.refusal, isNull);
      expect(d.entry?.code, 'ped-language');
    });
  });

  group('reason 4 — record anomaly', () {
    test('refuses, names the section, states the count, offers repair', () {
      final d = evaluateDraftGate(
        clinicalArea: 'pediatric-language',
        anomalies: [anomaly('speech', ['r1', 'r2'])],
        sectionLabels: _labels,
      );
      expect(d.canDraft, isFalse);
      expect(d.refusal, DraftRefusal.recordAnomaly);
      expect(d.reason, contains('Speech')); // the LABEL, not 'speech'
      expect(d.reason, contains('2 items'));
      expect(d.reason, contains('Repair'));
      expect(d.entry, isNull);
    });

    test('singular reads correctly', () {
      final d = evaluateDraftGate(
        clinicalArea: 'pediatric-language',
        anomalies: [anomaly('literacy', ['r9'])],
        sectionLabels: _labels,
      );
      expect(d.reason, contains('1 item in it never saved'));
      expect(d.reason, isNot(contains('items')));
    });

    test('the SHARED gate uses a protocol-neutral noun — "milestones" is '
        'ped-language vocabulary and belongs in its surface, not here', () {
      final d = evaluateDraftGate(
        clinicalArea: 'pediatric-cas',
        anomalies: [anomaly('speech', ['a'])],
        sectionLabels: _labels,
      );
      expect(d.reason, isNot(contains('milestone')));
      expect(d.reason, contains('item'));
    });

    test('multiple anomalous sections are acknowledged, not hidden', () {
      final d = evaluateDraftGate(
        clinicalArea: 'pediatric-language',
        anomalies: [
          anomaly('speech', ['a']),
          anomaly('language', ['b', 'c']),
        ],
        sectionLabels: _labels,
      );
      expect(d.reason, contains('Speech'));
      expect(d.reason, contains('1 other section'));
    });

    test('falls back to the raw id when no label is supplied — never an '
        'empty name', () {
      final d = evaluateDraftGate(
        clinicalArea: 'pediatric-language',
        anomalies: [anomaly('speech', ['a'])],
      );
      expect(d.reason, contains('speech'));
    });

    test('PRECEDENCE: the anomaly wins over "no reader", because it is the '
        'one she can act on', () {
      // The exemplar has a surface but NO reader — reason 1 would otherwise
      // fire and mask the defect entirely.
      final withAnomaly = evaluateDraftGate(
        clinicalArea: _readerlessArea,
        anomalies: [anomaly('speech', ['a'])],
        sectionLabels: _labels,
      );
      expect(withAnomaly.refusal, DraftRefusal.recordAnomaly);

      final without = evaluateDraftGate(
        clinicalArea: _readerlessArea,
        anomalies: const [],
      );
      expect(without.refusal, DraftRefusal.noReader);
    });

    test('an anomaly blocks a protocol that CAN draft, too', () {
      final d = evaluateDraftGate(
        clinicalArea: 'pediatric-cas', // has a reader
        anomalies: [anomaly('speech', ['a'])],
        sectionLabels: _labels,
      );
      expect(d.canDraft, isFalse);
      expect(d.refusal, DraftRefusal.recordAnomaly);
    });
  });

  group('the four refusals stay distinct', () {
    test('no area / no protocol / no reader / anomaly each have their own '
        'refusal and their own words', () {
      final noArea = evaluateDraftGate(clinicalArea: '', anomalies: const []);
      final noProtocol =
          evaluateDraftGate(clinicalArea: 'fluency', anomalies: const []);
      final noReader = evaluateDraftGate(
          clinicalArea: _readerlessArea, anomalies: const []);
      final anomalous = evaluateDraftGate(
        clinicalArea: _readerlessArea,
        anomalies: [anomaly('speech', ['a'])],
        sectionLabels: _labels,
      );

      expect(noArea.refusal, DraftRefusal.noArea);
      expect(noProtocol.refusal, DraftRefusal.noProtocol);
      expect(noReader.refusal, DraftRefusal.noReader);
      expect(anomalous.refusal, DraftRefusal.recordAnomaly);

      final reasons = {
        noArea.reason,
        noProtocol.reason,
        noReader.reason,
        anomalous.reason,
      };
      expect(reasons.length, 4, reason: 'no two refusals share wording');

      // The record-defect refusal must never read like the capability
      // refusal — that would send her at the wrong problem.
      expect(anomalous.reason, isNot(contains('does not draft')));
      expect(noReader.reason, isNot(contains('never saved')));
    });

    test('a clean draftable case passes and carries its entry', () {
      final d = evaluateDraftGate(
          clinicalArea: 'pediatric-cas', anomalies: const []);
      expect(d.canDraft, isTrue);
      expect(d.refusal, isNull);
      expect(d.reason, isNull);
      expect(d.entry?.code, 'ped-cas');
      expect(d.entry?.isDraftable, isTrue);
    });

    test('null clinical area behaves as no area', () {
      final d = evaluateDraftGate(clinicalArea: null, anomalies: const []);
      expect(d.refusal, DraftRefusal.noArea);
    });
  });

  group('the anomaly never reaches a document', () {
    test('a refused gate yields NO entry, so the drafter — and therefore '
        'the proxy — is never reachable', () {
      final d = evaluateDraftGate(
        clinicalArea: 'pediatric-cas',
        anomalies: [anomaly('speech', ['a'])],
        sectionLabels: _labels,
      );
      // _draftInMyFormat early-returns when entry is null; with no entry
      // there is no reader binding, no assessment id, and no
      // requestAssessmentDraft call.
      expect(d.entry, isNull);
      expect(d.canDraft, isFalse);
    });

    test('the refusal text is clinician-facing UI, not report content — it '
        'names a repair action, which no drafted prose would', () {
      final d = evaluateDraftGate(
        clinicalArea: 'pediatric-language',
        anomalies: [anomaly('speech', ['a'])],
        sectionLabels: _labels,
      );
      expect(d.reason, contains('Repair it above'));
    });
  });
}
