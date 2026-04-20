import 'package:flutter_test/flutter_test.dart';
import 'package:cue/models/stg_evidence.dart';

void main() {
  // ── fixtures ──────────────────────────────────────────────────────────────

  final baseJson = <String, dynamic>{
    'id': 'ev-001',
    'stg_id': 'stg-001',
    'session_id': 16, // bigint — matches sessions.id type
    'patient_id': '307e5de6-5ba3-4940-89e3-81b2bb74afea',
    'trials_attempted': 10,
    'trials_correct': 8,
    'accuracy_pct': 80.0, // generated column — present on read
    'cue_level_used': 'moderate',
    'context_this_session': 'Structured drill with picture cards',
    'clinician_observation': 'Client produced target 8/10 with moderate cues',
    'recommendation': 'Attempt minimal cue next session',
    'source': 'manual_entry',
    'ai_confidence': null,
    'clinician_verified': false,
    'created_at': '2026-04-19T10:00:00.000Z',
  };

  StgEvidence buildEvidence() => StgEvidence.fromJson(baseJson);

  // ── EvidenceSource enum ───────────────────────────────────────────────────

  group('EvidenceSource', () {
    test('all values round-trip through toJson / fromString', () {
      for (final s in EvidenceSource.values) {
        final str = s.toJson();
        expect(EvidenceSource.fromString(str), s,
            reason: '$s → "$str" did not round-trip');
      }
    });

    test('DB string values are correct', () {
      expect(EvidenceSource.manualEntry.toJson(), 'manual_entry');
      expect(EvidenceSource.aiExtractedNarrator.toJson(), 'ai_extracted_narrator');
      expect(EvidenceSource.aiExtractedNote.toJson(), 'ai_extracted_note');
    });

    test('unknown string defaults to manualEntry', () {
      expect(EvidenceSource.fromString('unknown'), EvidenceSource.manualEntry);
    });
  });

  // ── StgEvidence.fromJson ──────────────────────────────────────────────────

  group('StgEvidence.fromJson', () {
    test('parses all fields correctly', () {
      final ev = buildEvidence();
      expect(ev.id, 'ev-001');
      expect(ev.stgId, 'stg-001');
      expect(ev.sessionId, 16);
      expect(ev.sessionId, isA<int>());
      expect(ev.patientId, '307e5de6-5ba3-4940-89e3-81b2bb74afea');
      expect(ev.trialsAttempted, 10);
      expect(ev.trialsCorrect, 8);
      expect(ev.accuracyPct, 80.0);
      expect(ev.cueLevelUsed, 'moderate');
      expect(ev.contextThisSession, 'Structured drill with picture cards');
      expect(ev.clinicianObservation, isNotNull);
      expect(ev.recommendation, isNotNull);
      expect(ev.source, EvidenceSource.manualEntry);
      expect(ev.aiConfidence, isNull);
      expect(ev.clinicianVerified, isFalse);
      expect(ev.createdAt, DateTime.parse('2026-04-19T10:00:00.000Z'));
    });

    test('session_id coerces num to int', () {
      // Supabase may return bigint as num
      final json = Map<String, dynamic>.from(baseJson)..['session_id'] = 16.0;
      final ev = StgEvidence.fromJson(json);
      expect(ev.sessionId, 16);
      expect(ev.sessionId, isA<int>());
    });

    test('handles null optional fields', () {
      final json = Map<String, dynamic>.from(baseJson)
        ..['trials_attempted'] = null
        ..['trials_correct'] = null
        ..['accuracy_pct'] = null
        ..['cue_level_used'] = null
        ..['context_this_session'] = null
        ..['clinician_observation'] = null
        ..['recommendation'] = null
        ..['ai_confidence'] = null;
      final ev = StgEvidence.fromJson(json);
      expect(ev.trialsAttempted, isNull);
      expect(ev.trialsCorrect, isNull);
      expect(ev.accuracyPct, isNull);
      expect(ev.cueLevelUsed, isNull);
      expect(ev.aiConfidence, isNull);
    });

    test('parses ai_extracted_narrator source with confidence', () {
      final json = Map<String, dynamic>.from(baseJson)
        ..['source'] = 'ai_extracted_narrator'
        ..['ai_confidence'] = 0.87;
      final ev = StgEvidence.fromJson(json);
      expect(ev.source, EvidenceSource.aiExtractedNarrator);
      expect(ev.aiConfidence, 0.87);
    });

    test('defaults clinician_verified to false when absent', () {
      final json = Map<String, dynamic>.from(baseJson)
        ..remove('clinician_verified');
      final ev = StgEvidence.fromJson(json);
      expect(ev.clinicianVerified, isFalse);
    });
  });

  // ── StgEvidence.toJson ────────────────────────────────────────────────────

  group('StgEvidence.toJson', () {
    test('round-trips through fromJson → toJson', () {
      final ev = buildEvidence();
      final json = ev.toJson();
      final restored = StgEvidence.fromJson(json);
      expect(restored.id, ev.id);
      expect(restored.stgId, ev.stgId);
      expect(restored.sessionId, ev.sessionId);
      expect(restored.patientId, ev.patientId);
      expect(restored.source, ev.source);
      expect(restored.accuracyPct, ev.accuracyPct);
    });

    test('uses DB column names', () {
      final json = buildEvidence().toJson();
      expect(json.containsKey('stg_id'), isTrue);
      expect(json.containsKey('session_id'), isTrue);
      expect(json.containsKey('patient_id'), isTrue);
      expect(json.containsKey('cue_level_used'), isTrue);
      expect(json.containsKey('context_this_session'), isTrue);
      expect(json.containsKey('clinician_observation'), isTrue);
      expect(json.containsKey('clinician_verified'), isTrue);
      // Must NOT have camelCase keys
      expect(json.containsKey('stgId'), isFalse);
      expect(json.containsKey('sessionId'), isFalse);
    });

    test('source serialises to DB string', () {
      final json = buildEvidence().toJson();
      expect(json['source'], 'manual_entry');
    });
  });

  // ── StgEvidence.toInsertJson ──────────────────────────────────────────────

  group('StgEvidence.toInsertJson', () {
    test('omits id (server-generated)', () {
      final json = buildEvidence().toInsertJson();
      expect(json.containsKey('id'), isFalse);
    });

    test('omits accuracy_pct (generated column)', () {
      final json = buildEvidence().toInsertJson();
      expect(json.containsKey('accuracy_pct'), isFalse);
    });

    test('omits created_at (server-defaulted)', () {
      final json = buildEvidence().toInsertJson();
      expect(json.containsKey('created_at'), isFalse);
    });

    test('includes required fields', () {
      final json = buildEvidence().toInsertJson();
      expect(json['stg_id'], 'stg-001');
      expect(json['session_id'], 16);
      expect(json['patient_id'], '307e5de6-5ba3-4940-89e3-81b2bb74afea');
      expect(json['source'], 'manual_entry');
      expect(json['clinician_verified'], isFalse);
    });

    test('omits null optional fields', () {
      // Construct directly with null fields — copyWith(field: null)
      // means "keep existing" per Flutter convention, not "set to null".
      final sparse = StgEvidence(
        id: 'ev-sparse',
        stgId: 'stg-001',
        sessionId: 16,
        patientId: 'patient-001',
        source: EvidenceSource.manualEntry,
        createdAt: DateTime(2026, 4, 19),
        // all optional fields left null
      );
      final json = sparse.toInsertJson();
      expect(json.containsKey('cue_level_used'), isFalse);
      expect(json.containsKey('recommendation'), isFalse);
      expect(json.containsKey('context_this_session'), isFalse);
      expect(json.containsKey('clinician_observation'), isFalse);
      expect(json.containsKey('trials_attempted'), isFalse);
      expect(json.containsKey('ai_confidence'), isFalse);
    });
  });

  // ── StgEvidence.copyWith ──────────────────────────────────────────────────

  group('StgEvidence.copyWith', () {
    test('returns equivalent when no fields changed', () {
      final ev = buildEvidence();
      final copy = ev.copyWith();
      expect(copy.id, ev.id);
      expect(copy.source, ev.source);
      expect(copy.clinicianVerified, ev.clinicianVerified);
    });

    test('only mutates specified fields', () {
      final ev = buildEvidence();
      final verified = ev.copyWith(clinicianVerified: true);
      expect(verified.clinicianVerified, isTrue);
      expect(verified.id, ev.id);
      expect(verified.stgId, ev.stgId);
      expect(verified.sessionId, ev.sessionId);
    });
  });
}
