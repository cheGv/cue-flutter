// lib/services/ped_language_assessment_service.dart
//
// Pediatric Language capture surface (Step 4) — parent record + milestone
// row persistence. Mirrors the CasAssessmentService shape (loadOrCreate
// parent keyed on client_id, seed-once child rows, deterministic
// update-by-id) with two differences:
//   1. The canonical row set comes from the ASHA dataset asset
//      (AshaMilestoneLibrary), band-matched to the child's age — and the
//      milestone/example text is SNAPSHOTTED into each row so the
//      clinical record survives future dataset edits.
//   2. ped_language_milestones DOES carry a unique constraint on
//      (assessment, section, milestone_order), so double-seeding fails
//      loudly instead of duplicating rows.
//
// Age resolution: clients.date_of_birth → exact months; else
// clients.age (years) → midpoint months (years*12 + 6). No age on file
// means NO capture — the surface asks for an age instead of guessing a
// band. The band locks onto the parent row at creation; a later
// birthday never silently migrates an in-progress capture.
//
// status NULL = not yet captured. 'absent' is only written by
// completeSection — the SLP declaring the section done is what turns
// "unselected" into an explicit clinical record.
//
// RLS is off in the sandbox (prototype convention); clinician_id is set
// from the authenticated user when present, as on cas_assessments.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/asha_milestone_library.dart';

/// Why loadOrCreate could not produce a capture-ready assessment.
enum PedLanguageBootstrapState {
  ready,

  /// Client has neither date_of_birth nor a positive stated age.
  /// clients.age == 0 is a known placeholder (trial-run clients are
  /// written with a literal 0), so it must read as "no age", never as
  /// a real six-month-old.
  noAge,

  /// date_of_birth on file is in the future — a data-entry slip. Kept
  /// distinct from noAge so the surface can point at the actual error
  /// instead of asking for an age that (wrongly) exists.
  invalidDob,

  /// Resolved age falls outside the dataset's birth-5 coverage.
  outOfAgeRange,
}

class PedLanguageBootstrap {
  final PedLanguageBootstrapState state;

  /// Set when state == ready.
  final Map<String, dynamic>? assessment;
  final AshaAgeBand? band;

  /// Milestone rows from the DB, ordered by section (dataset order)
  /// then milestone_order. Set when state == ready.
  final List<Map<String, dynamic>> rows;

  /// Resolved age in months (set for ready and outOfAgeRange).
  final int? ageMonths;

  /// 'dob' | 'stated_years' (set whenever ageMonths is).
  final String? ageSource;

  /// Dataset provenance sentence, surfaced verbatim in the UI.
  final String source;

  const PedLanguageBootstrap({
    required this.state,
    this.assessment,
    this.band,
    this.rows = const [],
    this.ageMonths,
    this.ageSource,
    required this.source,
  });
}

class PedLanguageAssessmentService {
  PedLanguageAssessmentService._();
  static final instance = PedLanguageAssessmentService._();

  SupabaseClient get _sb => Supabase.instance.client;

  /// Full months elapsed from [dob] to [now] (day-of-month aware).
  static int ageMonthsFromDob(DateTime dob, DateTime now) {
    var months = (now.year - dob.year) * 12 + (now.month - dob.month);
    if (now.day < dob.day) months -= 1;
    return months;
  }

  /// Loads the most recent assessment for the client, or creates one
  /// with the band locked from the child's age and the band's full
  /// milestone set seeded (status NULL).
  Future<PedLanguageBootstrap> loadOrCreate({required String clientId}) async {
    final library = await AshaMilestoneLibrary.load();

    // An existing assessment wins outright — its band_key is locked and
    // age questions were settled at creation.
    final existing = await _sb
        .from('ped_language_assessments')
        .select()
        .eq('client_id', clientId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (existing != null) {
      final assessment = Map<String, dynamic>.from(existing);
      final band = library.bandById(assessment['band_key'] as String);
      if (band == null) {
        // A stored band key the shipped dataset no longer knows is a
        // build defect — fail loudly, never render a wrong band.
        throw StateError(
            'ped_language_assessments.band_key `${assessment['band_key']}` '
            'not present in the shipped ASHA dataset');
      }
      var rows = await _loadRows(assessment['id'] as String);
      if (rows.isEmpty) {
        // Self-heal a partial bootstrap: the parent insert and the seed
        // are two requests, so a drop between them leaves a parent with
        // zero rows. Re-seeding here is safe — the unique constraint
        // makes a concurrent double-seed loud, and a seeded assessment
        // never has zero rows (every band has milestones in every
        // section).
        await _seedBand(assessment['id'] as String, band);
        rows = await _loadRows(assessment['id'] as String);
      }
      return PedLanguageBootstrap(
        state: PedLanguageBootstrapState.ready,
        assessment: assessment,
        band: band,
        rows: rows,
        ageMonths: assessment['age_months_at_capture'] as int?,
        ageSource: assessment['age_source'] as String?,
        source: library.source,
      );
    }

    // Fresh capture — resolve the age, then the band.
    final client = await _sb
        .from('clients')
        .select('date_of_birth, age')
        .eq('id', clientId)
        .single();

    final int ageMonths;
    final String ageSource;
    final dob = client['date_of_birth'];
    final statedYears = client['age'];
    if (dob is String && dob.isNotEmpty) {
      ageMonths = ageMonthsFromDob(DateTime.parse(dob), DateTime.now());
      ageSource = 'dob';
      if (ageMonths < 0) {
        // Future-dated DOB — a data-entry slip (the AI intake path has
        // no future-date guard). Name the error; don't fold it into
        // the out-of-range message with a nonsense positive age.
        return PedLanguageBootstrap(
          state: PedLanguageBootstrapState.invalidDob,
          source: library.source,
        );
      }
    } else if (statedYears is int && statedYears > 0) {
      // Midpoint of the stated year: "3 years old" reads as 3y6m.
      // age <= 0 falls through to noAge — 0 is the codebase's missing-
      // age placeholder (trial runs write a literal 0), and a real
      // under-1 infant is better served by asking for a DOB.
      ageMonths = statedYears * 12 + 6;
      ageSource = 'stated_years';
    } else {
      return PedLanguageBootstrap(
        state: PedLanguageBootstrapState.noAge,
        source: library.source,
      );
    }

    final band = library.bandForAgeMonths(ageMonths);
    if (band == null) {
      return PedLanguageBootstrap(
        state: PedLanguageBootstrapState.outOfAgeRange,
        ageMonths: ageMonths,
        ageSource: ageSource,
        source: library.source,
      );
    }

    final inserted = await _sb
        .from('ped_language_assessments')
        .insert({
          'client_id':             clientId,
          'clinician_id':          _sb.auth.currentUser?.id,
          'band_key':              band.bandId,
          'age_months_at_capture': ageMonths,
          'age_source':            ageSource,
        })
        .select()
        .single();
    final assessment = Map<String, dynamic>.from(inserted);
    final assessmentId = assessment['id'] as String;

    await _seedBand(assessmentId, band);

    return PedLanguageBootstrap(
      state: PedLanguageBootstrapState.ready,
      assessment: assessment,
      band: band,
      rows: await _loadRows(assessmentId),
      ageMonths: ageMonths,
      ageSource: ageSource,
      source: library.source,
    );
  }

  /// Seeds the band's full milestone set in one bulk insert,
  /// snapshotting the dataset text. The unique constraint makes an
  /// accidental re-seed a loud failure rather than silent duplication.
  Future<void> _seedBand(String assessmentId, AshaAgeBand band) async {
    final seedRows = <Map<String, dynamic>>[
      for (final section in kAshaSections)
        for (final m in band.sections[section]!)
          {
            'ped_language_assessment_id': assessmentId,
            'section':         section,
            'milestone_order': m.order,
            'milestone_text':  m.milestone,
            'example_text':    m.example,
          },
    ];
    await _sb.from('ped_language_milestones').insert(seedRows);
  }

  /// Rows in dataset order — kAshaSections order, then milestone_order.
  /// (The section column is text, so a server-side order would be
  /// alphabetical; the dataset ordering is applied here.)
  Future<List<Map<String, dynamic>>> _loadRows(String assessmentId) async {
    final rows = await _sb
        .from('ped_language_milestones')
        .select()
        .eq('ped_language_assessment_id', assessmentId);
    final list = (rows as List)
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    int sectionRank(Object? s) => kAshaSections.indexOf(s as String? ?? '');
    list.sort((a, b) {
      final bySection =
          sectionRank(a['section']).compareTo(sectionRank(b['section']));
      if (bySection != 0) return bySection;
      return (a['milestone_order'] as int)
          .compareTo(b['milestone_order'] as int);
    });
    return list;
  }

  /// Updates one milestone row by id. status null clears the mark back
  /// to not-yet-captured; evidenceSource must be null unless status is
  /// present/emerging (the DB check enforces what the UI promises).
  Future<void> updateMilestone({
    required String rowId,
    required String? status,
    required String? evidenceSource,
  }) async {
    await _sb.from('ped_language_milestones').update({
      'status':          status,
      'evidence_source': evidenceSource,
      'updated_at':      DateTime.now().toUtc().toIso8601String(),
    }).eq('id', rowId);
  }

  /// Declares a section done: the rows the SLP left unmarked — passed
  /// as an EXPLICIT id list computed from what was on her screen —
  /// become 'absent', and the parent's completion stamp is set. The
  /// explicit list (rather than a server-side status-IS-NULL filter)
  /// keeps the persisted record identical to the declared screen state
  /// even if an earlier per-row save failed or is still in flight.
  Future<void> completeSection({
    required String assessmentId,
    required String section,
    required List<String> unmarkedRowIds,
  }) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    if (unmarkedRowIds.isNotEmpty) {
      await _sb
          .from('ped_language_milestones')
          .update({
            'status':          'absent',
            'evidence_source': null,
            'updated_at':      nowIso,
          })
          .eq('ped_language_assessment_id', assessmentId)
          .inFilter('id', unmarkedRowIds);
    }
    await _sb.from('ped_language_assessments').update({
      '${section}_completed_at': nowIso,
      'updated_at':              nowIso,
    }).eq('id', assessmentId);
  }
}
