// test/services/assessment_bridge/ped_language_reader_review_fixes_test.dart
//
// The defects the completed adversarial review confirmed
// (docs/audit/2026-08-02-ped-language-reader-review.md), each pinned so it
// cannot come back:
//
//   A — an 'absent' row in a section that was never declared done is the
//       signature of a half-landed completion write. It must not read as a
//       clean affirmative judgement.
//   C — a row seeded AFTER the declaration is a question she was never shown,
//       not an unfinished fill. The reader half only; the controller half
//       needs PedLanguageMark to carry created_at and is NOT fixed.
//   D — a defective record must not become a draft payload.
//   G — marking present must not write a provenance value. Pinned as a WIDGET
//       test in test/widgets/ped_language_anomaly_render_test.dart (it needs
//       the capture surface); this file is the pure reader/assembler half.

import 'package:flutter_test/flutter_test.dart';

import 'package:cue/models/assessment_envelope.dart';
import 'package:cue/services/assessment_bridge/assessment_context_assembler.dart';
import 'package:cue/services/assessment_bridge/ped_language_assessment_reader.dart';

const _ref = 'ASHA milestones reference sentence';

Map<String, dynamic> row({
  required String id,
  String section = 'speech',
  required int order,
  String? status,
  String? evidence,
  String created = '2026-08-01T09:00:00Z',
}) =>
    {
      'id': id,
      'section': section,
      'milestone_order': order,
      'milestone_text': 'Milestone $order',
      'status': status,
      'evidence_source': evidence,
      'norm_reference': _ref,
      'library_version': '1.0.0',
      'created_at': created,
    };

Map<String, dynamic> parent({String? speechDoneAt}) => {
      'id': 'a-1',
      'speech_completed_at': speechDoneAt,
      'language_completed_at': null,
      'literacy_completed_at': null,
    };

AssessmentEnvelope read(
  Map<String, dynamic> p,
  List<Map<String, dynamic>> rows,
) =>
    PedLanguageAssessmentReader().read(assessment: p, milestoneRows: rows);

void main() {
  group('A — an absence nobody declared', () {
    test('absent rows in an UNDECLARED section are flagged, not served as '
        'clean findings', () {
      // Reachable: completeSection issues the row update and the parent stamp
      // as two non-transactional calls, and the controller's rollback reverts
      // only in-memory state. When the second call fails these rows stay
      // 'absent' forever — after she was told the save failed.
      final env = read(parent(speechDoneAt: null), [
        row(id: 'r1', order: 1, status: 'absent'),
        row(id: 'r2', order: 2, status: 'absent'),
        row(id: 'r3', order: 3, status: 'present', evidence: 'observed'),
      ]);

      final a = env.anomalies.single;
      expect(a.kind, 'absence_without_declaration');
      expect(a.sourceId, 'ped_language_assessments/a-1/speech');
      expect(a.detail, contains('2 milestones'));
      expect(a.detail, contains('never marked done'));
      expect(env.hasAnomalies, isTrue);
    });

    test('singular reads correctly', () {
      final env = read(parent(speechDoneAt: null), [
        row(id: 'r1', order: 1, status: 'absent'),
      ]);
      expect(env.anomalies.single.detail, contains('1 milestone recorded'));
    });

    test('the absent findings are STILL emitted — the anomaly blocks the '
        'draft, it does not delete her data', () {
      final env = read(parent(speechDoneAt: null), [
        row(id: 'r1', order: 1, status: 'absent'),
      ]);
      expect(env.findings.single.value, 'absent');
      expect(env.findings.single.sourceId,
          'ped_language_milestones/r1/status');
    });

    test('a DECLARED section full of absent rows is the normal, healthy '
        'case — no anomaly', () {
      final env = read(parent(speechDoneAt: '2026-08-01T10:00:00Z'), [
        row(id: 'r1', order: 1, status: 'absent'),
        row(id: 'r2', order: 2, status: 'absent'),
      ]);
      expect(env.anomalies, isEmpty);
    });

    test('an undeclared section with no absent rows is ordinary '
        'in-progress capture', () {
      final env = read(parent(speechDoneAt: null), [
        row(id: 'r1', order: 1, status: 'present', evidence: 'observed'),
        row(id: 'r2', order: 2), // simply not reached yet
      ]);
      expect(env.anomalies, isEmpty);
    });
  });

  group('C — a milestone she was never shown', () {
    test('a row seeded AFTER the declaration does not trip '
        'incomplete_completion_fill', () {
      final env = read(parent(speechDoneAt: '2026-08-01T10:00:00Z'), [
        row(id: 'r1', order: 1, status: 'present', evidence: 'observed'),
        // Self-heal inserted this weeks later, once the dataset grew.
        row(id: 'r2', order: 2, created: '2026-09-20T08:00:00Z'),
      ]);
      expect(env.anomalies, isEmpty,
          reason: 'calling this a failed write steers her at a repair that '
              'writes absent for a question never asked');
      // Coverage still tells the truth about what is unanswered.
      final c = env.coverage.single;
      expect(c.expected, 2);
      expect(c.recorded, 1);
      expect(c.declaredComplete, isTrue);
    });

    test('a row that existed AT declaration still trips it — the real '
        'failed-fill case is untouched', () {
      final env = read(parent(speechDoneAt: '2026-08-01T10:00:00Z'), [
        row(id: 'r1', order: 1, status: 'present', evidence: 'observed'),
        row(id: 'r2', order: 2, created: '2026-08-01T09:00:00Z'),
      ]);
      expect(env.anomalies.single.kind, 'incomplete_completion_fill');
      expect(env.anomalies.single.detail, contains('1 milestone is'));
    });

    test('a mixed section counts ONLY the rows that existed', () {
      final env = read(parent(speechDoneAt: '2026-08-01T10:00:00Z'), [
        row(id: 'r1', order: 1, status: 'present', evidence: 'observed'),
        row(id: 'r2', order: 2, created: '2026-08-01T09:00:00Z'), // counts
        row(id: 'r3', order: 3, created: '2026-09-20T08:00:00Z'), // does not
        row(id: 'r4', order: 4, created: '2026-09-20T08:00:00Z'), // does not
      ]);
      expect(env.anomalies.single.detail,
          'Speech is marked done but 1 milestone is unmarked.');
    });

    test('FAILS TOWARD REPORTING: an unparseable or missing created_at is '
        'treated as pre-existing, so a real defect is never excused', () {
      // The stamp is client-generated and created_at server-generated, so
      // the comparison can be skewed. Ambiguity must not silence a defect.
      final env = read(parent(speechDoneAt: '2026-08-01T10:00:00Z'), [
        row(id: 'r1', order: 1, status: 'present', evidence: 'observed'),
        {...row(id: 'r2', order: 2), 'created_at': null},
        {...row(id: 'r3', order: 3), 'created_at': 'not-a-timestamp'},
      ]);
      expect(env.anomalies.single.detail, contains('2 milestones are'));
    });
  });

  group('D — a defective record cannot become a draft payload', () {
    final assembler = AssessmentContextAssembler();

    AssessmentEnvelope withAnomaly() => const AssessmentEnvelope(
          protocol: 'pediatric-language',
          assessmentId: 'a-1',
          findings: [
            AssessmentFinding(
              sourceId: 'ped_language_milestones/r1/status',
              sourceTable: 'ped_language_milestones',
              fieldLabel: 'Uses 2-word phrases',
              value: 'absent',
              group: 'Speech',
              scale: FindingScale.threeStatePresence,
            ),
          ],
          anomalies: [
            AssessmentAnomaly(
              sourceId: 'ped_language_assessments/a-1/speech',
              kind: 'incomplete_completion_fill',
              detail: 'Speech is marked done but 2 milestones are unmarked.',
            ),
          ],
        );

    test('assembleFromEnvelope REFUSES rather than building the bundle', () {
      expect(
        () => assembler.assembleFromEnvelope(
            envelope: withAnomaly(), clientMeta: const {}),
        throwsA(isA<AssessmentRecordDefectException>()),
      );
    });

    test('the refusal carries the anomaly OWN sentence, which is written to '
        'be clinician-facing', () {
      try {
        assembler.assembleFromEnvelope(
            envelope: withAnomaly(), clientMeta: const {});
        fail('should have refused');
      } on AssessmentRecordDefectException catch (e) {
        expect(e.clinicianMessage,
            'Speech is marked done but 2 milestones are unmarked.');
      }
    });

    test('several defects are acknowledged, not hidden behind the first', () {
      const env = AssessmentEnvelope(
        protocol: 'pediatric-language',
        assessmentId: 'a-1',
        anomalies: [
          AssessmentAnomaly(sourceId: 's1', kind: 'k', detail: 'First.'),
          AssessmentAnomaly(sourceId: 's2', kind: 'k', detail: 'Second.'),
        ],
      );
      try {
        assembler.assembleFromEnvelope(envelope: env, clientMeta: const {});
        fail('should have refused');
      } on AssessmentRecordDefectException catch (e) {
        expect(e.clinicianMessage, contains('First.'));
        expect(e.clinicianMessage, contains('1 other problem'));
      }
    });

    test('THE SECOND HOLE: the defect sentence never reaches the payload, '
        'because the payload is never built', () {
      Object? built;
      try {
        built = assembler.assembleFromEnvelope(
            envelope: withAnomaly(), clientMeta: const {});
      } catch (_) {
        built = null;
      }
      expect(built, isNull,
          reason: 'canonical_data used to carry the anomaly detail to the '
              'drafter as sourced material');
    });

    test('a CLEAN record still assembles exactly as before — the refusal is '
        'the only behaviour change', () {
      const clean = AssessmentEnvelope(
        protocol: 'pediatric-language',
        assessmentId: 'a-1',
        findings: [
          AssessmentFinding(
            sourceId: 'ped_language_milestones/r1/status',
            sourceTable: 'ped_language_milestones',
            fieldLabel: 'Uses 2-word phrases',
            value: 'present',
            group: 'Speech',
            scale: FindingScale.threeStatePresence,
            provenance: FindingProvenance.observed,
          ),
        ],
      );
      final bundle = assembler
          .assembleFromEnvelope(envelope: clean, clientMeta: {'age': 3});
      expect(bundle['assessment'], isNotNull);
      expect((bundle['client_meta'] as Map)['age'], 3);
      expect(bundle['sessions'], isEmpty);
    });

    test('the two flat-column readers are unaffected — no anomalies means no '
        'refusal', () {
      const voice =
          AssessmentEnvelope(protocol: 'voice', assessmentId: 'v-1');
      expect(
        () => assembler.assembleFromEnvelope(
            envelope: voice, clientMeta: const {}),
        returnsNormally,
      );
    });
  });
}
