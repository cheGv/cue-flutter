// lib/services/ped_language_assessment_service.dart
//
// Pediatric Language capture — parent record + milestone persistence,
// retrofitted (2026-07-29) onto the shared SectionalCapture primitive.
// The completion lifecycle (in-flight save queue, idempotent completion
// keyed on section id, per-key seed self-heal, rollback on failed
// completion, dirty-row refusal + retry) lives in
// SectionalCaptureController; this file owns ONLY:
//   - the gate: age resolution + band lock + parent loadOrCreate
//     (resolveParent — returns a state, never rows),
//   - the SQL: row load/update, seed insert, completion write,
//   - the SectionalCaptureStore adapter and the surface's config.
// There is deliberately NO seeding or self-heal here anymore — that
// single path is the controller's bootstrap.
//
// Data doctrine (unchanged): milestone/example text and provenance
// (norm_reference = the dataset's source sentence, library_version =
// its loud-fail-parsed version) are SNAPSHOTTED into every row; the
// unique constraint on (assessment, section, milestone_order) makes a
// double-seed loud; status NULL = not yet captured, and 'absent' is
// only written by the completion the SLP declares.
//
// RLS: both tables sealed 2026-07-25 (slp_owns_via_client /
// slp_owns_via_assessment); clinician_id set from the authenticated
// user, as on the sibling surfaces.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/asha_milestone_library.dart';
import '../widgets/assessment/sectional_capture.dart';

/// Why resolveParent could not produce a capture-ready assessment.
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

/// Gate result only — rows are the controller's business now.
class PedLanguageBootstrap {
  final PedLanguageBootstrapState state;

  /// Set when state == ready.
  final Map<String, dynamic>? assessment;
  final AshaAgeBand? band;

  /// Resolved age in months (set for ready and outOfAgeRange) — the
  /// value the band lookup actually used (derived_age_months).
  final int? ageMonths;

  /// 'dob' | 'stated_years_midpoint' (set whenever ageMonths is).
  final String? ageSource;

  /// Dataset provenance sentence, surfaced verbatim in the UI.
  final String source;

  const PedLanguageBootstrap({
    required this.state,
    this.assessment,
    this.band,
    this.ageMonths,
    this.ageSource,
    required this.source,
  });
}

/// The surface's mutable mirror of one ped_language_milestones row.
class PedLanguageMark {
  final String id;
  final String section;
  final int order;
  final String text;
  final String? example;
  String? status;   // present | emerging | absent | null (not yet captured)
  String? evidence; // observed | parent_reported | null

  /// The row's SERVER creation time (ped_language_milestones.created_at, a
  /// DB now() default). Lets the controller tell a row seeded AFTER a
  /// section was declared done (self-heal) from a failed completion fill.
  /// Null only when the source row carried none — read as unknown, which
  /// the controller treats as pre-existing (fails toward reporting).
  final DateTime? createdAt;

  PedLanguageMark({
    required this.id,
    required this.section,
    required this.order,
    required this.text,
    required this.example,
    required this.status,
    required this.evidence,
    this.createdAt,
  });
}

/// Seed identity within the assessment: (section, milestone_order).
typedef PedLanguageSeedKey = (String, int);

/// The surface's SectionalCapture wiring — top-level and pure so the
/// four async findings are re-verifiable headlessly against the REAL
/// config (test/widgets/ped_language_sectional_test.dart).
SectionalCaptureConfig<PedLanguageMark> pedLanguageSectionalConfig(
    AshaAgeBand band) {
  return SectionalCaptureConfig<PedLanguageMark>(
    sectionIds: kAshaSections,
    rowId: (m) => m.id,
    sectionOf: (m) => m.section,
    seedKey: (m) => (m.section, m.order),
    expectedSeedKeys: {
      for (final section in kAshaSections)
        for (final m in band.sections[section]!) (section, m.order),
    },
    completion: SectionalCompletionSpec<PedLanguageMark>(
      isUnmarked: (m) => m.status == null,
      // Server created_at, so a self-heal row seeded after the section was
      // declared done is not flagged as a failed fill (review defect C).
      createdAt: (m) => m.createdAt,
      applyCompletionFill: (m) {
        m.status = 'absent';
        m.evidence = null;
      },
      revertCompletionFill: (m) {
        m.status = null;
        m.evidence = null;
      },
    ),
  );
}

/// A timestamptz value as the server sent it (PostgREST ISO-8601 with offset),
/// or null when absent or unparseable. Never throws. Used for the RPC's
/// returned stamp and for each row's created_at, so both sides of the
/// post-declaration comparison parse the server clock the same way. The
/// PARENT's own completion stamps in load() deliberately keep the throwing
/// DateTime.parse: a malformed declaration must fail bootstrap loudly rather
/// than quietly read as "not declared".
DateTime? _time(Object? v) {
  if (v is DateTime) return v;
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : DateTime.tryParse(s);
}

class PedLanguageAssessmentService {
  PedLanguageAssessmentService._([this._injectedClient]);
  static final instance = PedLanguageAssessmentService._();

  /// Test seam, mirroring FeedingAssessmentService.withClient: a service
  /// bound to a specific Supabase client. Production uses [instance],
  /// which reads Supabase.instance.client.
  factory PedLanguageAssessmentService.withClient(SupabaseClient client) =>
      PedLanguageAssessmentService._(client);

  final SupabaseClient? _injectedClient;

  SupabaseClient get _sb => _injectedClient ?? Supabase.instance.client;

  /// Full months elapsed from [dob] to [now] (day-of-month aware).
  static int ageMonthsFromDob(DateTime dob, DateTime now) {
    var months = (now.year - dob.year) * 12 + (now.month - dob.month);
    if (now.day < dob.day) months -= 1;
    return months;
  }

  /// Pure age derivation — exactly what gets persisted as
  /// derived_age_months / age_source, extracted so both paths are
  /// testable without a Supabase client. DOB wins over a stated age
  /// and is exact full months; a stated age is the year's midpoint
  /// (years*12 + 6) under the honest name 'stated_years_midpoint'.
  /// Future-dated DOB is invalidDob (data-entry slip, named — never a
  /// nonsense positive age); statedYears <= 0 is noAge, because 0 is
  /// the codebase's missing-age placeholder (trial runs write a
  /// literal 0) and a real under-1 infant is better served by a DOB.
  static ({PedLanguageBootstrapState state, int? ageMonths, String? ageSource})
      resolveAge({
    required String? dobIso,
    required int? statedYears,
    required DateTime now,
  }) {
    if (dobIso != null && dobIso.isNotEmpty) {
      final months = ageMonthsFromDob(DateTime.parse(dobIso), now);
      if (months < 0) {
        return (
          state: PedLanguageBootstrapState.invalidDob,
          ageMonths: null,
          ageSource: null,
        );
      }
      return (
        state: PedLanguageBootstrapState.ready,
        ageMonths: months,
        ageSource: 'dob',
      );
    }
    if (statedYears != null && statedYears > 0) {
      return (
        state: PedLanguageBootstrapState.ready,
        ageMonths: statedYears * 12 + 6,
        ageSource: 'stated_years_midpoint',
      );
    }
    return (
      state: PedLanguageBootstrapState.noAge,
      ageMonths: null,
      ageSource: null,
    );
  }

  /// The GATE half of bootstrap: loads the most recent assessment for
  /// the client, or creates one with the band locked from the child's
  /// age. Returns state + parent + band — NEVER rows and NEVER seeds;
  /// row loading and per-key seed self-heal are the
  /// SectionalCaptureController's bootstrap, the one and only path.
  Future<PedLanguageBootstrap> resolveParent({required String clientId}) async {
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
      return PedLanguageBootstrap(
        state: PedLanguageBootstrapState.ready,
        assessment: assessment,
        band: band,
        ageMonths: assessment['derived_age_months'] as int?,
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

    final resolved = resolveAge(
      dobIso: client['date_of_birth'] as String?,
      statedYears: client['age'] as int?,
      now: DateTime.now(),
    );
    if (resolved.state != PedLanguageBootstrapState.ready) {
      return PedLanguageBootstrap(
        state: resolved.state,
        source: library.source,
      );
    }
    final ageMonths = resolved.ageMonths!;
    final ageSource = resolved.ageSource!;

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
          'client_id':          clientId,
          'clinician_id':       _sb.auth.currentUser?.id,
          'band_key':           band.bandId,
          'derived_age_months': ageMonths,
          'age_source':         ageSource,
        })
        .select()
        .single();

    return PedLanguageBootstrap(
      state: PedLanguageBootstrapState.ready,
      assessment: Map<String, dynamic>.from(inserted),
      band: band,
      ageMonths: ageMonths,
      ageSource: ageSource,
      source: library.source,
    );
  }

  /// The exact row set a FULL seed writes — pure and static so tests
  /// pin the provenance stamping without a Supabase client. Every row
  /// snapshots the dataset text AND its provenance: norm_reference is
  /// the dataset's source sentence verbatim, library_version the
  /// dataset's parsed (loud-fail) version.
  static List<Map<String, dynamic>> seedRowsFor(
      String assessmentId, AshaAgeBand band, AshaMilestoneLibrary library) {
    return <Map<String, dynamic>>[
      for (final section in kAshaSections)
        for (final m in band.sections[section]!)
          {
            'ped_language_assessment_id': assessmentId,
            'section':         section,
            'milestone_order': m.order,
            'milestone_text':  m.milestone,
            'example_text':    m.example,
            'norm_reference':  library.source,
            'library_version': library.version,
          },
    ];
  }

  /// The seed payloads for exactly [keys] — the store's insertSeedRows
  /// input, pure for the same reason. A key the band does not know is
  /// simply absent from the result (the controller only ever passes
  /// keys from expectedSeedKeys, which came from the same band).
  static List<Map<String, dynamic>> seedRowsForKeys(String assessmentId,
      AshaAgeBand band, AshaMilestoneLibrary library, Set<Object> keys) {
    return [
      for (final row in seedRowsFor(assessmentId, band, library))
        if (keys.contains(
            (row['section'] as String, row['milestone_order'] as int)))
          row,
    ];
  }

  /// The parent row by id. Moved here from PedLanguageSectionalStore
  /// (2026-08-02) so ALL database access for this protocol goes through
  /// the service — the shape FeedingAssessmentService already has, and
  /// what makes a single injected service a sufficient test seam. Same
  /// query, same order, same errors as before; no behaviour changed.
  Future<Map<String, dynamic>> loadAssessmentRow(String assessmentId) async {
    final row = await _sb
        .from('ped_language_assessments')
        .select()
        .eq('id', assessmentId)
        .single();
    return Map<String, dynamic>.from(row);
  }

  /// Every milestone row for an assessment, unordered (the store applies
  /// dataset order — the section column is text, so a server-side sort
  /// would be alphabetical).
  Future<List<Map<String, dynamic>>> loadMilestoneRows(
      String assessmentId) async {
    final rows = await _sb
        .from('ped_language_milestones')
        .select()
        .eq('ped_language_assessment_id', assessmentId);
    return (rows as List)
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  /// Bulk-inserts seed rows. The unique constraint makes a concurrent
  /// double-seed loud rather than silent duplication — the store
  /// contract's requirement.
  Future<void> insertMilestoneRows(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    await _sb.from('ped_language_milestones').insert(rows);
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

  /// The completion write, ATOMIC (2026-09-05, review defect A): the rows the
  /// SLP left unmarked — the EXPLICIT id list the controller computed after
  /// draining every in-flight save — become 'absent', and the parent's
  /// <section>_completed_at stamp is set, in ONE Postgres transaction via
  /// complete_ped_language_section. Both land or neither does.
  ///
  /// This used to be two separate non-transactional PostgREST calls; a failure
  /// between them left rows stamped 'absent' (a positive clinical claim the SLP
  /// never made) with no parent stamp, while the controller reverted only its
  /// in-memory state — so screen and record diverged. With the RPC a failed
  /// completion changes nothing, which makes the controller's memory-only
  /// revert correct. The row predicate is unchanged (this assessment + the
  /// explicit id list, never a server-side status-IS-NULL filter). The reader's
  /// absence_without_declaration anomaly stays as belt-and-braces for any
  /// record written before this fix.
  ///
  /// Returns the section's stamp AS THE SERVER RECORDED IT, from the same
  /// transaction: now() on a fresh declaration, the ORIGINAL stamp on a repair
  /// (set once — a repair never re-declares). One round trip, so there is no
  /// second read whose failure could masquerade as a failed write. Against a
  /// not-yet-upgraded (void) function the result is null, which the
  /// controller reads as "stamp not supplied" and keeps its placeholder.
  Future<DateTime?> completeSection({
    required String assessmentId,
    required String section,
    required List<String> unmarkedRowIds,
  }) async {
    final result = await _sb.rpc('complete_ped_language_section', params: {
      'p_assessment_id':    assessmentId,
      'p_section':          section,
      'p_unmarked_row_ids': unmarkedRowIds,
    });
    return _time(result);
  }
}

/// SectionalCaptureStore adapter — the SQL half the controller drives.
/// Constructed only in the ready world (after resolveParent gating).
class PedLanguageSectionalStore
    implements SectionalCompletionCapableStore<PedLanguageMark> {
  final String assessmentId;
  final AshaAgeBand band;
  final AshaMilestoneLibrary library;
  final PedLanguageAssessmentService _service;

  PedLanguageSectionalStore({
    required this.assessmentId,
    required this.band,
    required this.library,
    PedLanguageAssessmentService? service,
  }) : _service = service ?? PedLanguageAssessmentService.instance;

  @override
  Future<SectionalSnapshot<PedLanguageMark>> load() async {
    // All DB access goes through the service — see loadAssessmentRow.
    final parent = await _service.loadAssessmentRow(assessmentId);
    final rows = await _service.loadMilestoneRows(assessmentId);
    final marks = [
      for (final r in rows)
        PedLanguageMark(
          id:       r['id'] as String,
          section:  r['section'] as String,
          order:    r['milestone_order'] as int,
          text:     r['milestone_text'] as String,
          example:  r['example_text'] as String?,
          status:   r['status'] as String?,
          evidence: r['evidence_source'] as String?,
          createdAt: _time(r['created_at']),
        ),
    ];
    // Dataset order — the section column is text, so a server-side
    // order would be alphabetical.
    int rank(String s) => kAshaSections.indexOf(s);
    marks.sort((a, b) {
      final bySection = rank(a.section).compareTo(rank(b.section));
      if (bySection != 0) return bySection;
      return a.order.compareTo(b.order);
    });
    return SectionalSnapshot(
      rows: marks,
      completedAt: {
        for (final section in kAshaSections)
          section: parent['${section}_completed_at'] == null
              ? null
              : DateTime.parse(parent['${section}_completed_at'] as String),
      },
    );
  }

  @override
  Future<void> insertSeedRows(Set<Object> missingSeedKeys) {
    return _service.insertMilestoneRows(
        PedLanguageAssessmentService.seedRowsForKeys(
            assessmentId, band, library, missingSeedKeys));
  }

  @override
  Future<DateTime?> persistCompletion({
    required String sectionId,
    required List<String> unmarkedRowIds,
  }) {
    // ONE request. The RPC returns the stamp the server recorded in the same
    // transaction, so the controller compares server clock to server clock
    // (created_at) with no second read whose failure could be mistaken for a
    // failed write. If the RPC itself throws, nothing was written, and the
    // controller's rollback is exactly right.
    return _service.completeSection(
      assessmentId: assessmentId,
      section: sectionId,
      unmarkedRowIds: unmarkedRowIds,
    );
  }
}
