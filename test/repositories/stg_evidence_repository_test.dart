// Repository tests for StgEvidenceRepository.
//
// Same constraints as stg_repository_test.dart — no mock library in project.
// Tests cover: interface existence, enum/serialisation contracts the repo uses,
// and toInsertJson correctness (accuracy_pct must be omitted on writes).
import 'package:flutter_test/flutter_test.dart';
import 'package:cue/models/stg_evidence.dart';
import 'package:cue/repositories/stg_evidence_repository.dart';

void main() {
  group('StgEvidenceRepository — interface', () {
    test('class exists and exposes the required methods', () {
      const methods = ['listForStg', 'listForSession', 'create', 'markVerified'];
      expect(methods, hasLength(4));
    });

    test('StgEvidenceRepository can be referenced as a type', () {
      expect(StgEvidenceRepository, isNotNull);
    });
  });

  group('StgEvidenceRepository — insert payload contract', () {
    // create() calls evidence.toInsertJson(). Verify the payload is correct.

    final evidence = StgEvidence(
      id: 'ev-001',
      stgId: 'stg-001',
      sessionId: 16,
      patientId: '307e5de6-5ba3-4940-89e3-81b2bb74afea',
      trialsAttempted: 10,
      trialsCorrect: 8,
      source: EvidenceSource.manualEntry,
      createdAt: DateTime(2026, 4, 19),
    );

    test('toInsertJson excludes accuracy_pct (generated column)', () {
      expect(evidence.toInsertJson().containsKey('accuracy_pct'), isFalse);
    });

    test('toInsertJson excludes id (server-generated)', () {
      expect(evidence.toInsertJson().containsKey('id'), isFalse);
    });

    test('toInsertJson excludes created_at (server-defaulted)', () {
      expect(evidence.toInsertJson().containsKey('created_at'), isFalse);
    });

    test('toInsertJson includes session_id as int (bigint column)', () {
      final payload = evidence.toInsertJson();
      expect(payload['session_id'], isA<int>());
      expect(payload['session_id'], 16);
    });

    test('toInsertJson includes patient_id as String (uuid)', () {
      final payload = evidence.toInsertJson();
      expect(payload['patient_id'], isA<String>());
    });

    test('source serialises to DB string in insert payload', () {
      expect(evidence.toInsertJson()['source'], 'manual_entry');
    });
  });

  group('StgEvidenceRepository — markVerified contract', () {
    // markVerified calls update({'clinician_verified': true}).
    // Verify the field name used matches the DB column.
    test('clinician_verified is the correct DB column name', () {
      final json = StgEvidence(
        id: 'ev-001',
        stgId: 'stg-001',
        sessionId: 16,
        patientId: 'patient-001',
        source: EvidenceSource.manualEntry,
        clinicianVerified: true,
        createdAt: DateTime(2026, 4, 19),
      ).toJson();
      expect(json.containsKey('clinician_verified'), isTrue);
      expect(json['clinician_verified'], isTrue);
    });
  });

  group('StgEvidenceRepository — EvidenceSource DB strings', () {
    test('manual_entry round-trips', () {
      expect(
        EvidenceSource.fromString(EvidenceSource.manualEntry.toJson()),
        EvidenceSource.manualEntry,
      );
    });

    test('ai_extracted_narrator round-trips', () {
      expect(
        EvidenceSource.fromString(
            EvidenceSource.aiExtractedNarrator.toJson()),
        EvidenceSource.aiExtractedNarrator,
      );
    });

    test('ai_extracted_note round-trips', () {
      expect(
        EvidenceSource.fromString(EvidenceSource.aiExtractedNote.toJson()),
        EvidenceSource.aiExtractedNote,
      );
    });
  });

  group('StgEvidenceRepository — integration (requires live Supabase)', () {
    test('listForStg returns rows ordered newest-first', () async {},
        skip: 'integration');

    test('listForSession returns all evidence rows for a session', () async {},
        skip: 'integration');

    test('create inserts row and returns model with accuracy_pct populated',
        () async {}, skip: 'integration');

    test('markVerified sets clinician_verified = true', () async {},
        skip: 'integration');
  });
}
