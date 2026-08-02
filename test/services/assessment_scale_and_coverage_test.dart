// test/services/assessment_scale_and_coverage_test.dart
//
// The envelope's anti-overstatement guarantees, pinned on the two readers
// that exist:
//   * `emerging` survives verbatim — no reader may round it to present or
//     absent (it is clinically distinct from BOTH neighbours),
//   * declared-absent survives as a finding while not-captured is
//     suppressed — the distinction the whole change exists for,
//   * FindingScale is declared per finding and CAS is genuinely MIXED,
//   * coverage counts threeStatePresence fields only, so "3 of 12 recorded"
//     is computable rather than merely inferable.
//
// Both readers' read(...) are pure (rows in, envelope out), so this needs no
// Supabase.

import 'package:flutter_test/flutter_test.dart';

import 'package:cue/models/assessment_envelope.dart';
import 'package:cue/services/assessment_bridge/cas_assessment_reader.dart';
import 'package:cue/services/assessment_bridge/voice_assessment_reader.dart';

Map<String, dynamic> casRow(Map<String, dynamic> overrides) => {
      'id': 'cas-1',
      ...overrides,
    };

AssessmentFinding? findingFor(AssessmentEnvelope e, String columnSuffix) {
  for (final f in e.findings) {
    if (f.sourceId.endsWith('/$columnSuffix')) return f;
  }
  return null;
}

void main() {
  group('emerging is never rounded', () {
    test('CAS passes emerging through verbatim on every three-state field',
        () {
      final env = CasAssessmentReader().read(
        assessment: casRow({
          'marker_inconsistent_errors': 'emerging',
          'marker_disrupted_transitions': 'emerging',
          'marker_inappropriate_prosody': 'emerging',
          'groping_searching': 'emerging',
          'vowel_errors': 'emerging',
          'receptive_expressive_gap': 'emerging',
        }),
      );
      for (final col in [
        'marker_inconsistent_errors',
        'marker_disrupted_transitions',
        'marker_inappropriate_prosody',
        'groping_searching',
        'vowel_errors',
        'receptive_expressive_gap',
      ]) {
        final f = findingFor(env, col);
        expect(f, isNotNull, reason: col);
        expect(f!.value, 'emerging',
            reason: '$col must not be rounded to present or absent');
      }
    });

    test('no finding value in any envelope is silently normalised', () {
      final env = CasAssessmentReader().read(
        assessment: casRow({
          'marker_inconsistent_errors': 'present',
          'marker_disrupted_transitions': 'emerging',
          'marker_inappropriate_prosody': 'absent',
        }),
      );
      expect(
        env.findings.map((f) => f.value).toSet(),
        {'present', 'emerging', 'absent'},
        reason: 'all three recorded states survive as themselves',
      );
    });
  });

  group('declared-absent vs not-captured', () {
    test('a stored "absent" IS a finding; a null is suppressed', () {
      final env = CasAssessmentReader().read(
        assessment: casRow({
          'marker_inconsistent_errors': 'absent', // she looked; not there
          'marker_disrupted_transitions': null, // never assessed
        }),
      );
      final absent = findingFor(env, 'marker_inconsistent_errors');
      expect(absent, isNotNull);
      expect(absent!.value, 'absent');
      expect(findingFor(env, 'marker_disrupted_transitions'), isNull,
          reason: 'not-captured is expressed by absence from the list');
    });

    test('silence is interpretable only via the scale — coverage makes it '
        'computable', () {
      final env = CasAssessmentReader().read(
        assessment: casRow({'marker_inconsistent_errors': 'present'}),
      );
      final markers = env.coverage
          .firstWhere((c) => c.group == 'ASHA consensus markers');
      expect(markers.expected, 3);
      expect(markers.recorded, 1);
      expect(markers.notCaptured, 2);
      expect(markers.isComplete, isFalse);
    });
  });

  group('FindingScale is declared, and CAS is mixed', () {
    test('markers and differential evidence are threeStatePresence; notes, '
        'inventories, exam and capture notes are openValue', () {
      final env = CasAssessmentReader().read(
        assessment: casRow({
          'marker_inappropriate_prosody': 'present',
          'marker_prosody_notes': 'ran out of time on this one',
          'groping_searching': 'absent',
          'oral_mech_exam': 'unremarkable',
          'consonant_inventory': 'p b m',
          'capture_notes': 'tired at the end',
          'age_months': 54,
        }),
      );
      FindingScale scaleOf(String col) => findingFor(env, col)!.scale;
      expect(scaleOf('marker_inappropriate_prosody'),
          FindingScale.threeStatePresence);
      expect(scaleOf('groping_searching'), FindingScale.threeStatePresence);
      // A blank note means she wrote no note, never that the thing it
      // describes was absent.
      expect(scaleOf('marker_prosody_notes'), FindingScale.openValue);
      expect(scaleOf('oral_mech_exam'), FindingScale.openValue);
      expect(scaleOf('consonant_inventory'), FindingScale.openValue);
      expect(scaleOf('capture_notes'), FindingScale.openValue);
      expect(scaleOf('age_months'), FindingScale.openValue);
    });

    test('coverage counts three-state fields ONLY — prose has no '
        'denominator', () {
      final env = CasAssessmentReader().read(
        assessment: casRow({
          'marker_inconsistent_errors': 'present',
          'marker_disrupted_transitions': 'present',
          'marker_inappropriate_prosody': 'present',
          'marker_prosody_notes': 'a note',
          'consonant_inventory': 'p b m',
        }),
      );
      final markers = env.coverage
          .firstWhere((c) => c.group == 'ASHA consensus markers');
      // 6 fields sit in this group; only the 3 three-state ones count.
      expect(markers.expected, 3);
      expect(markers.recorded, 3);
      expect(markers.isComplete, isTrue);
      // A group with no three-state field gets no coverage entry at all.
      expect(env.coverage.where((c) => c.group == 'Phonetic inventory'),
          isEmpty);
      expect(env.coverage.where((c) => c.group == 'Notes'), isEmpty);
    });

    test('the differential group has its own denominator', () {
      final env = CasAssessmentReader().read(assessment: casRow({}));
      final diff = env.coverage
          .firstWhere((c) => c.group == 'Oral mechanism & evidence');
      expect(diff.expected, 3); // groping, vowel errors, rec-exp gap
      expect(diff.recorded, 0);
      expect(diff.notCaptured, 3);
    });
  });

  group('voice declares openValue throughout and claims no coverage', () {
    test('every voice finding is openValue', () {
      final env = VoiceAssessmentReader().read(
        assessment: {
          'id': 'voice-1',
          'rsi_total_score': 21,
          'voice_use_hours_per_day': 6,
        },
      );
      expect(env.findings, isNotEmpty);
      for (final f in env.findings) {
        expect(f.scale, FindingScale.openValue, reason: f.fieldLabel);
      }
    });

    test('voice carries no coverage — it has no three-state field, so it '
        'must not imply a denominator it does not have', () {
      final env = VoiceAssessmentReader().read(
        assessment: {'id': 'voice-1', 'rsi_total_score': 21},
      );
      expect(env.coverage, isEmpty);
    });

    test('neither reader emits anomalies — no completion contract exists in '
        'either capture model', () {
      expect(
          CasAssessmentReader()
              .read(assessment: casRow({'capture_notes': 'x'}))
              .anomalies,
          isEmpty);
      expect(
          VoiceAssessmentReader()
              .read(assessment: {'id': 'v', 'rsi_total_score': 1}).anomalies,
          isEmpty);
    });
  });

  group('envelope surfaces anomalies to its consumer', () {
    test('hasAnomalies drives the consumer refusal, and toJson carries '
        'scale / coverage / anomalies', () {
      const env = AssessmentEnvelope(
        protocol: 'pediatric-language',
        assessmentId: 'a-1',
        findings: [
          AssessmentFinding(
            sourceId: 'ped_language_milestones/r1/status',
            sourceTable: 'ped_language_milestones',
            fieldLabel: 'Coos',
            value: 'emerging',
            group: 'speech',
            scale: FindingScale.threeStatePresence,
          ),
        ],
        coverage: [
          AssessmentCoverage(group: 'speech', expected: 3, recorded: 1),
        ],
        anomalies: [
          AssessmentAnomaly(
            sourceId: 'ped_language_assessments/a-1/speech',
            kind: 'incomplete_completion_fill',
            detail: 'Speech is marked done but 2 milestones are unmarked.',
          ),
        ],
      );
      expect(env.hasAnomalies, isTrue);
      final json = env.toJson();
      expect((json['findings'] as List).first['scale'],
          'threeStatePresence');
      expect((json['coverage'] as List).first['expected'], 3);
      expect((json['anomalies'] as List).first['kind'],
          'incomplete_completion_fill');
    });

    test('an envelope with no anomalies reports none', () {
      const env =
          AssessmentEnvelope(protocol: 'voice', assessmentId: 'v-1');
      expect(env.hasAnomalies, isFalse);
      expect(env.coverage, isEmpty);
    });
  });
}
