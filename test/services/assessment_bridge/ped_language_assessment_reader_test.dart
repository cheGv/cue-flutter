// test/services/assessment_bridge/ped_language_assessment_reader_test.dart
//
// The first row-shaped reader. What these tests exist to stop, in order of how
// badly each would hurt a real report:
//
//   1. a NULL milestone becoming an "absent" claim she never made,
//   2. a missing evidence source rendering as "observed in session",
//   3. a section that is declared done but under-filled reading as complete,
//   4. a record seeded across two dataset versions picking one silently,
//   5. 'emerging' being rounded to either neighbour.
//
// read() is pure, so every one of these is checked with no Supabase anywhere.
//
// FIXTURE PROVENANCE — read this before trusting the green. The CAS and voice
// readers were each gated on REAL captured sandbox rows. That gate cannot be
// applied here: as of 2026-08-02 the sandbox holds ZERO ped_language_assessments
// and ZERO ped_language_milestones (the surface has never been driven against
// it), while its two siblings hold 3 assessments each. So these fixtures are
// synthetic.
//
// What was done instead: every fixture key below was verified column-for-column
// against the LIVE sandbox catalog on 2026-08-02 — all 12 parent columns and
// all 12 milestone columns, matching names, types and nullability. In
// particular status and evidence_source are nullable (so NULL is a real input),
// while milestone_text, norm_reference and library_version are NOT NULL (so
// their "blank" case is '' and never null, which is what the blank-value tests
// below use). This is faithfulness to the schema, NOT verification against real
// clinical data — the real-data gate stays open until the surface is driven
// against the sandbox at least once.

import 'package:flutter_test/flutter_test.dart';

import 'package:cue/models/assessment_envelope.dart';
import 'package:cue/services/assessment_bridge/ped_language_assessment_reader.dart';

const _kReference =
    'Milestones sourced verbatim from ASHA Communication Milestones '
    '(asha.org/public/developmental-milestones). Examples authored by Cue in '
    'Indian English for familiarity. This is a structured developmental '
    'reference informing clinical judgment, not a standalone diagnostic tool.';

/// One ped_language_milestones row, shaped exactly as Postgres returns it.
Map<String, dynamic> row({
  required String id,
  required String section,
  required int order,
  String? text,
  String? status,
  String? evidence,
  String reference = _kReference,
  String version = '1.0.0',
}) =>
    {
      'id': id,
      'ped_language_assessment_id': 'a-1',
      'section': section,
      'milestone_order': order,
      'milestone_text': text ?? 'Milestone $order in $section',
      'example_text': 'An example the clinician did not write',
      'status': status,
      'evidence_source': evidence,
      'norm_reference': reference,
      'library_version': version,
      'created_at': '2026-08-01T00:00:00Z',
      'updated_at': '2026-08-01T00:00:00Z',
    };

/// One ped_language_assessments row. [done] names the declared sections.
Map<String, dynamic> parent({Set<String> done = const {}}) => {
      'id': 'a-1',
      'client_id': 'c-1',
      'clinician_id': 'u-1',
      'band_key': '2_to_3y',
      'derived_age_months': 30,
      'age_source': 'dob',
      'capture_notes': 'a note nobody writes',
      'speech_completed_at':
          done.contains('speech') ? '2026-08-01T10:00:00Z' : null,
      'language_completed_at':
          done.contains('language') ? '2026-08-01T10:00:00Z' : null,
      'literacy_completed_at':
          done.contains('literacy') ? '2026-08-01T10:00:00Z' : null,
      'created_at': '2026-08-01T00:00:00Z',
      'updated_at': '2026-08-01T00:00:00Z',
    };

AssessmentEnvelope readIt(
  List<Map<String, dynamic>> rows, {
  Set<String> done = const {},
}) =>
    PedLanguageAssessmentReader()
        .read(assessment: parent(done: done), milestoneRows: rows);

AssessmentCoverage coverageFor(AssessmentEnvelope e, String group) =>
    e.coverage.firstWhere((c) => c.group == group);

void main() {
  group('NULL never becomes a finding', () {
    test('an unmarked milestone emits nothing at all — silence plus the '
        'scale is what says "not captured"', () {
      final env = readIt([
        row(id: 'r1', section: 'speech', order: 1, status: 'present',
            evidence: 'observed'),
        row(id: 'r2', section: 'speech', order: 2), // never touched
      ]);
      expect(env.findings.length, 1);
      expect(env.findings.single.sourceId,
          'ped_language_milestones/r1/status');
      // The one thing that must never appear:
      expect(env.findings.map((f) => f.value), isNot(contains('absent')));
    });

    test('an explicitly declared absence IS a finding — it is a judgement '
        'she made, not a blank', () {
      final env = readIt([
        row(id: 'r1', section: 'speech', order: 1, status: 'absent'),
      ]);
      expect(env.findings.single.value, 'absent');
      expect(env.findings.single.scale, FindingScale.threeStatePresence);
    });

    test('every milestone finding declares threeStatePresence, so its '
        'silence is interpretable', () {
      final env = readIt([
        row(id: 'r1', section: 'speech', order: 1, status: 'present',
            evidence: 'observed'),
        row(id: 'r2', section: 'language', order: 1, status: 'emerging',
            evidence: 'parent_reported'),
        row(id: 'r3', section: 'literacy', order: 1, status: 'absent'),
      ]);
      expect(env.findings.every((f) => f.scale ==
          FindingScale.threeStatePresence), isTrue);
    });

    test('emerging passes through verbatim — never rounded to either '
        'neighbour', () {
      final env = readIt([
        row(id: 'r1', section: 'speech', order: 1, status: 'emerging',
            evidence: 'observed'),
      ]);
      expect(env.findings.single.value, 'emerging');
    });
  });

  group('provenance keeps three states apart', () {
    test('observed and parent_reported carry through distinctly', () {
      final env = readIt([
        row(id: 'r1', section: 'speech', order: 1, status: 'present',
            evidence: 'observed'),
        row(id: 'r2', section: 'speech', order: 2, status: 'present',
            evidence: 'parent_reported'),
      ]);
      expect(env.findings[0].provenance, FindingProvenance.observed);
      expect(env.findings[1].provenance, FindingProvenance.parentReported);
    });

    test('THE ONE THAT MATTERS: an affirmative row with no stored source '
        'is notRecorded — never observed', () {
      // Legal in the schema: the CHECK forbids a source on a negative row,
      // not the converse. Today's UI always writes one, so this row means
      // something went wrong — and "observed" would invent a session event.
      final env = readIt([
        row(id: 'r1', section: 'speech', order: 1, status: 'present'),
        row(id: 'r2', section: 'speech', order: 2, status: 'emerging'),
      ]);
      expect(env.findings[0].provenance, FindingProvenance.notRecorded);
      expect(env.findings[1].provenance, FindingProvenance.notRecorded);
      expect(env.findings.map((f) => f.provenance),
          isNot(contains(FindingProvenance.observed)));
    });

    test('an absent row is notApplicable, not notRecorded — the constraint '
        'forbids a source there, so nothing is missing', () {
      final env = readIt([
        row(id: 'r1', section: 'speech', order: 1, status: 'absent'),
      ]);
      expect(env.findings.single.provenance,
          FindingProvenance.notApplicable);
    });

    test('an unrenderable source token reads as notRecorded AND raises an '
        'anomaly — never quietly upgraded', () {
      final env = readIt([
        row(id: 'r1', section: 'speech', order: 1, status: 'present',
            evidence: 'teacher_said_so'),
      ]);
      expect(env.findings.single.provenance, FindingProvenance.notRecorded);
      expect(env.anomalies.single.kind, 'unknown_vocabulary');
      expect(env.anomalies.single.detail, contains('teacher_said_so'));
    });

    test('the four states serialise distinctly', () {
      final env = readIt([
        row(id: 'r1', section: 'speech', order: 1, status: 'present',
            evidence: 'observed'),
        row(id: 'r2', section: 'speech', order: 2, status: 'present',
            evidence: 'parent_reported'),
        row(id: 'r3', section: 'speech', order: 3, status: 'present'),
        row(id: 'r4', section: 'language', order: 1, status: 'absent'),
      ]);
      final json = env.toJson()['findings'] as List;
      expect(json.map((f) => (f as Map)['provenance']).toList(),
          ['observed', 'parentReported', 'notRecorded', 'notApplicable']);
    });
  });

  group('coverage counts rows, and completion is READ not inferred', () {
    test('expected counts every seeded row; recorded counts marked ones', () {
      final env = readIt([
        row(id: 'r1', section: 'speech', order: 1, status: 'present',
            evidence: 'observed'),
        row(id: 'r2', section: 'speech', order: 2),
        row(id: 'r3', section: 'speech', order: 3),
        row(id: 'r4', section: 'language', order: 1, status: 'absent'),
      ]);
      final speech = coverageFor(env, 'Speech');
      expect(speech.expected, 3);
      expect(speech.recorded, 1);
      expect(speech.notCaptured, 2);
      expect(coverageFor(env, 'Language').expected, 1);
    });

    test('declaredComplete comes from the STAMP, and is independent of how '
        'much is recorded', () {
      // Fully recorded but never declared: she is still working.
      final env = readIt([
        row(id: 'r1', section: 'speech', order: 1, status: 'present',
            evidence: 'observed'),
      ]);
      final speech = coverageFor(env, 'Speech');
      expect(speech.isComplete, isTrue, reason: 'all rows recorded');
      expect(speech.declaredComplete, isFalse, reason: 'she never said done');
      expect(env.anomalies, isEmpty);
    });

    test('a partially completed assessment is reported honestly — declared '
        'sections and undeclared ones sit side by side', () {
      final env = readIt([
        row(id: 'r1', section: 'speech', order: 1, status: 'present',
            evidence: 'observed'),
        row(id: 'r2', section: 'language', order: 1, status: 'emerging',
            evidence: 'observed'),
        row(id: 'r3', section: 'language', order: 2),
      ], done: {'speech'});
      expect(coverageFor(env, 'Speech').declaredComplete, isTrue);
      expect(coverageFor(env, 'Language').declaredComplete, isFalse);
      // Language is under-recorded but NOT declared, so it is ordinary
      // in-progress capture, not a defect.
      expect(env.anomalies, isEmpty);
    });

    test('declared done + unmarked rows = incomplete_completion_fill', () {
      final env = readIt([
        row(id: 'r1', section: 'speech', order: 1, status: 'present',
            evidence: 'observed'),
        row(id: 'r2', section: 'speech', order: 2),
        row(id: 'r3', section: 'speech', order: 3),
      ], done: {'speech'});
      final a = env.anomalies.single;
      expect(a.kind, 'incomplete_completion_fill');
      expect(a.sourceId, 'ped_language_assessments/a-1/speech');
      expect(a.detail, 'Speech is marked done but 2 milestones are unmarked.');
      expect(env.hasAnomalies, isTrue);
      // The unmarked rows are STILL not emitted as absent.
      expect(env.findings.length, 1);
    });

    test('singular reads correctly', () {
      final env = readIt([
        row(id: 'r1', section: 'speech', order: 1, status: 'present',
            evidence: 'observed'),
        row(id: 'r2', section: 'speech', order: 2),
      ], done: {'speech'});
      expect(env.anomalies.single.detail,
          'Speech is marked done but 1 milestone is unmarked.');
    });

    test('the WORST case — declared done with NOTHING recorded — is still '
        'caught, and still emits no findings', () {
      // recorded == 0 is the most severe instance and the easiest for a
      // sloppy guard (rec > 0 && rec < exp) to skip, which would let a
      // wholly empty section read as a completed one.
      final env = readIt([
        row(id: 'r1', section: 'speech', order: 1),
        row(id: 'r2', section: 'speech', order: 2),
      ], done: {'speech'});
      expect(env.findings, isEmpty);
      expect(env.anomalies.single.kind, 'incomplete_completion_fill');
      expect(env.anomalies.single.detail,
          'Speech is marked done but 2 milestones are unmarked.');
      expect(coverageFor(env, 'Speech').recorded, 0);
      expect(coverageFor(env, 'Speech').declaredComplete, isTrue);
    });

    test('coverage groups follow dataset order, not row arrival order', () {
      final env = readIt([
        row(id: 'r9', section: 'literacy', order: 1, status: 'present',
            evidence: 'observed'),
        row(id: 'r1', section: 'language', order: 1, status: 'present',
            evidence: 'observed'),
        row(id: 'r5', section: 'speech', order: 1, status: 'present',
            evidence: 'observed'),
      ]);
      expect(env.coverage.map((c) => c.group).toList(),
          ['Speech', 'Language', 'Literacy']);
    });
  });

  group('the norm statement is one fact about the record', () {
    test('agreed rows produce a typed statement carried verbatim', () {
      final env = readIt([
        row(id: 'r1', section: 'speech', order: 1, status: 'present',
            evidence: 'observed'),
        row(id: 'r2', section: 'language', order: 1, status: 'absent'),
      ]);
      expect(env.normStatement, isNotNull);
      expect(env.normStatement!.reference, _kReference);
      expect(env.normStatement!.libraryVersion, '1.0.0');
      // Reaches the drafter as a named member, not prose inside a note.
      final json = env.toJson()['norm_statement'] as Map;
      expect(json['library_version'], '1.0.0');
      expect(json['reference'], contains('not a standalone diagnostic tool'));
    });

    test('DISAGREEMENT is an anomaly, not a value to pick from — the real '
        'case is a record seeded across a dataset version bump', () {
      final env = readIt([
        row(id: 'r1', section: 'speech', order: 1, status: 'present',
            evidence: 'observed', version: '1.0.0'),
        // Self-heal inserted this one later, after the bump.
        row(id: 'r2', section: 'speech', order: 2, status: 'present',
            evidence: 'observed', version: '1.1.0'),
      ]);
      expect(env.normStatement, isNull, reason: 'no winner is picked');
      final a = env.anomalies.single;
      expect(a.kind, 'norm_provenance_disagreement');
      expect(a.sourceId, 'ped_language_assessments/a-1/norm_provenance');
    });

    test('disagreement on the reference sentence counts too', () {
      final env = readIt([
        row(id: 'r1', section: 'speech', order: 1, status: 'present',
            evidence: 'observed'),
        row(id: 'r2', section: 'speech', order: 2, status: 'present',
            evidence: 'observed', reference: 'Some other reference set'),
      ]);
      expect(env.normStatement, isNull);
      expect(env.anomalies.single.kind, 'norm_provenance_disagreement');
    });

    test('an UNMARKED row from a later seed does not strip the caveat — it '
        'makes no claim, so it does not get to veto the statement', () {
      // The live sequence: record seeded at 1.0.0 and captured; dataset gains
      // a milestone; she reopens; self-heal inserts the new row at 1.1.0; she
      // has not marked it yet. Every FINDING here is still a 1.0.0 finding.
      final env = readIt([
        row(id: 'r1', section: 'speech', order: 1, status: 'present',
            evidence: 'observed', version: '1.0.0'),
        row(id: 'r2', section: 'speech', order: 2, version: '1.1.0'),
      ]);
      expect(env.normStatement, isNotNull,
          reason: 'the report must not silently lose its ASHA caveat');
      expect(env.normStatement!.libraryVersion, '1.0.0');
      expect(env.anomalies, isEmpty,
          reason: 'nothing here is a defect she could repair');
    });

    test('but once she MARKS that row, the record really does span two '
        'versions and the anomaly returns', () {
      final env = readIt([
        row(id: 'r1', section: 'speech', order: 1, status: 'present',
            evidence: 'observed', version: '1.0.0'),
        row(id: 'r2', section: 'speech', order: 2, status: 'absent',
            version: '1.1.0'),
      ]);
      expect(env.normStatement, isNull);
      expect(env.anomalies.single.kind, 'norm_provenance_disagreement');
    });

    test('a blank statement is not published — under-claim instead', () {
      final env = readIt([
        row(id: 'r1', section: 'speech', order: 1, status: 'present',
            evidence: 'observed', reference: '', version: ''),
      ]);
      expect(env.normStatement, isNull);
      expect(env.anomalies, isEmpty, reason: 'agreed-but-blank is not a '
          'disagreement');
    });
  });

  group('the label is data, and data can be blank', () {
    test('milestone text becomes the label verbatim', () {
      final env = readIt([
        row(id: 'r1', section: 'speech', order: 1,
            text: 'Uses 2-word phrases', status: 'present',
            evidence: 'observed'),
      ]);
      expect(env.findings.single.fieldLabel, 'Uses 2-word phrases');
    });

    test('a blank label falls back positionally rather than dropping a real '
        'judgement', () {
      final env = readIt([
        row(id: 'r1', section: 'speech', order: 4, text: '   ',
            status: 'present', evidence: 'observed'),
      ]);
      expect(env.findings.single.value, 'present', reason: 'never dropped');
      expect(env.findings.single.fieldLabel, 'Speech — milestone 4');
      expect(env.findings.single.sourceId,
          'ped_language_milestones/r1/status');
    });

    test('example_text is never emitted — it is Cue-authored illustration, '
        'not something she recorded', () {
      final env = readIt([
        row(id: 'r1', section: 'speech', order: 1, status: 'present',
            evidence: 'observed'),
      ]);
      final json = env.toJson().toString();
      expect(json, isNot(contains('An example the clinician did not write')));
    });

    test('capture_notes on the parent is never emitted — no capture path '
        'writes it, and test harnesses do', () {
      final env = readIt([
        row(id: 'r1', section: 'speech', order: 1, status: 'present',
            evidence: 'observed'),
      ]);
      expect(env.toJson().toString(), isNot(contains('a note nobody writes')));
    });
  });

  group('output is deterministic', () {
    test('findings come out in dataset order however the rows arrive', () {
      final rows = [
        row(id: 'r5', section: 'literacy', order: 1, status: 'present',
            evidence: 'observed'),
        row(id: 'r3', section: 'speech', order: 3, status: 'present',
            evidence: 'observed'),
        row(id: 'r1', section: 'speech', order: 1, status: 'present',
            evidence: 'observed'),
        row(id: 'r4', section: 'language', order: 2, status: 'present',
            evidence: 'observed'),
        row(id: 'r2', section: 'speech', order: 2, status: 'present',
            evidence: 'observed'),
      ];
      final forward = readIt(rows);
      final backward = readIt(rows.reversed.toList());
      final ids = forward.findings.map((f) => f.sourceId).toList();
      expect(ids, [
        'ped_language_milestones/r1/status',
        'ped_language_milestones/r2/status',
        'ped_language_milestones/r3/status',
        'ped_language_milestones/r4/status',
        'ped_language_milestones/r5/status',
      ]);
      expect(backward.findings.map((f) => f.sourceId).toList(), ids,
          reason: 'row arrival order must not change the report');
    });
  });

  group('edges', () {
    test('an unseeded assessment is empty, not wrong', () {
      final env = readIt(const []);
      expect(env.isEmpty, isTrue);
      expect(env.coverage, isEmpty);
      expect(env.anomalies, isEmpty);
      expect(env.normStatement, isNull);
      expect(env.protocol, 'pediatric-language');
      expect(env.assessmentId, 'a-1');
    });

    test('a status outside the DB vocabulary is emitted verbatim AND flagged '
        '— nothing dropped, nothing drafted', () {
      final env = readIt([
        row(id: 'r1', section: 'speech', order: 1, status: 'maybe'),
      ]);
      expect(env.findings.single.value, 'maybe');
      expect(env.anomalies.single.kind, 'unknown_vocabulary');
      expect(env.anomalies.single.sourceId,
          'ped_language_milestones/r1/status');
      expect(env.hasAnomalies, isTrue);
    });

    test('an unknown section still reports, sorted last', () {
      final env = readIt([
        row(id: 'r2', section: 'pragmatics', order: 1, status: 'present',
            evidence: 'observed'),
        row(id: 'r1', section: 'speech', order: 1, status: 'present',
            evidence: 'observed'),
      ]);
      expect(env.coverage.map((c) => c.group).toList(),
          ['Speech', 'pragmatics']);
      expect(env.findings.last.group, 'pragmatics');
    });

    test('the protocol string matches what the assembler dispatches on', () {
      expect(PedLanguageAssessmentReader.protocol, 'pediatric-language');
      expect(readIt(const []).protocol,
          PedLanguageAssessmentReader.protocol);
    });

    test('measures stay empty — ped-language captures judgements, not '
        'numbers, and a count is not a measurement', () {
      final env = readIt([
        row(id: 'r1', section: 'speech', order: 1, status: 'present',
            evidence: 'observed'),
      ]);
      expect(env.measures, isEmpty);
    });
  });

  group('the flat-column readers are untouched by the new envelope fields',
      () {
    test('a finding that declares no provenance serialises null, which is '
        'NOT notRecorded', () {
      const f = AssessmentFinding(
        sourceId: 'cas_assessments/x/marker_inconsistent_errors',
        sourceTable: 'cas_assessments',
        fieldLabel: 'Inconsistent errors',
        value: 'present',
        group: 'ASHA consensus markers',
        scale: FindingScale.threeStatePresence,
      );
      expect(f.provenance, isNull);
      expect(f.toJson()['provenance'], isNull);
      expect(f.toJson()['provenance'],
          isNot(FindingProvenance.notRecorded.name));
    });

    test('coverage without a completion contract reports null, not false', () {
      const c = AssessmentCoverage(
          group: 'ASHA consensus markers', expected: 3, recorded: 3);
      expect(c.declaredComplete, isNull,
          reason: 'false would claim she left it undeclared; null says the '
              'protocol has no such contract');
    });
  });
}
