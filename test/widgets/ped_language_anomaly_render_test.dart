// test/widgets/ped_language_anomaly_render_test.dart
//
// The render path the copy tests could not reach: the anomaly banner
// actually mounting, and the Repair button actually driving
// repairCompletion. Uses the injected-service seam (mirroring the feeding
// surface's) so no network is touched.
//
// What these pin, that unit tests could not:
//   * the banner mounts ON LOAD for a defective record,
//   * it does NOT mount for a clean one,
//   * Repair issues the completion write and the banner goes away,
//   * a failed repair keeps the banner AND tells her.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:cue/models/asha_milestone_library.dart';
import 'package:cue/services/ped_language_assessment_service.dart';
import 'package:cue/widgets/assessment/ped_language_capture_surface.dart';

/// In-memory ped-language service. Mirrors _FakeFeedingService: implements
/// the real class, overrides only what the surface calls, no Supabase.
class _FakePedLanguageService implements PedLanguageAssessmentService {
  _FakePedLanguageService({
    required this.bandId,
    required this.completedSections,
    required this.rows,
    this.failCompletion = false,
  });

  final String bandId;
  final Set<String> completedSections;
  final List<Map<String, dynamic>> rows;
  bool failCompletion;

  int completeCalls = 0;
  String? lastCompletedSection;
  List<String>? lastUnmarkedRowIds;

  @override
  Future<PedLanguageBootstrap> resolveParent({required String clientId}) async {
    final lib = await AshaMilestoneLibrary.load();
    return PedLanguageBootstrap(
      state: PedLanguageBootstrapState.ready,
      assessment: {
        'id': 'a-1',
        'client_id': clientId,
        'band_key': bandId,
        'derived_age_months': 30,
        'age_source': 'dob',
        for (final s in kAshaSections)
          '${s}_completed_at':
              completedSections.contains(s) ? '2026-08-01T00:00:00Z' : null,
      },
      band: lib.bandById(bandId),
      ageMonths: 30,
      ageSource: 'dob',
      source: lib.source,
    );
  }

  @override
  Future<Map<String, dynamic>> loadAssessmentRow(String assessmentId) async => {
        'id': assessmentId,
        for (final s in kAshaSections)
          '${s}_completed_at':
              completedSections.contains(s) ? '2026-08-01T00:00:00Z' : null,
      };

  @override
  Future<List<Map<String, dynamic>>> loadMilestoneRows(
          String assessmentId) async =>
      [for (final r in rows) Map<String, dynamic>.from(r)];

  @override
  Future<void> insertMilestoneRows(List<Map<String, dynamic>> newRows) async {
    // The fixture is always fully seeded, so reconciliation inserts
    // nothing; a call here would mean the seed set drifted.
    for (final r in newRows) {
      rows.add({'id': 'seeded-${rows.length}', ...r});
    }
  }

  /// Every persisted mark, in order — so a test can assert what the tap
  /// actually WROTE, not merely what the screen shows.
  final List<({String rowId, String? status, String? evidence})> writes = [];

  @override
  Future<void> updateMilestone({
    required String rowId,
    required String? status,
    required String? evidenceSource,
  }) async {
    writes.add((rowId: rowId, status: status, evidence: evidenceSource));
    final r = rows.firstWhere((r) => r['id'] == rowId);
    r['status'] = status;
    r['evidence_source'] = evidenceSource;
  }

  @override
  Future<void> completeSection({
    required String assessmentId,
    required String section,
    required List<String> unmarkedRowIds,
  }) async {
    completeCalls += 1;
    if (failCompletion) throw StateError('completion write failed');
    lastCompletedSection = section;
    lastUnmarkedRowIds = unmarkedRowIds;
    for (final id in unmarkedRowIds) {
      rows.firstWhere((r) => r['id'] == id)['status'] = 'absent';
    }
    completedSections.add(section);
  }
}

/// A full row set for the 2_to_3y band (3 speech / 8 language / 1 literacy),
/// every row marked 'present' unless listed in [leaveUnmarked].
Future<List<Map<String, dynamic>>> bandRows({
  Set<String> leaveUnmarked = const {},
}) async {
  final lib = await AshaMilestoneLibrary.load();
  final band = lib.bandById('2_to_3y')!;
  final out = <Map<String, dynamic>>[];
  for (final section in kAshaSections) {
    for (final m in band.sections[section]!) {
      final id = '$section-${m.order}';
      out.add({
        'id': id,
        'section': section,
        'milestone_order': m.order,
        'milestone_text': m.milestone,
        'example_text': m.example,
        'status': leaveUnmarked.contains(id) ? null : 'present',
        'evidence_source': leaveUnmarked.contains(id) ? null : 'observed',
      });
    }
  }
  return out;
}

Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('anomaly banner appears ON LOAD when a stamped section still '
      'holds unmarked rows', (tester) async {
    final svc = _FakePedLanguageService(
      bandId: '2_to_3y',
      // Speech declared done…
      completedSections: {'speech'},
      // …but one of its rows never saved.
      rows: await bandRows(leaveUnmarked: {'speech-2'}),
    );
    await tester.pumpWidget(host(
        PedLanguageCaptureSurface(clientId: 'c-1', service: svc)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Speech is marked done'), findsOneWidget);
    expect(find.textContaining('1 milestone in it never saved'),
        findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Repair'), findsOneWidget);
    // Nothing was repaired on load.
    expect(svc.completeCalls, 0);
    expect(svc.rows.firstWhere((r) => r['id'] == 'speech-2')['status'],
        isNull);
  });

  testWidgets('no banner on a clean record', (tester) async {
    final svc = _FakePedLanguageService(
      bandId: '2_to_3y',
      completedSections: {'speech'},
      rows: await bandRows(), // every row marked
    );
    await tester.pumpWidget(host(
        PedLanguageCaptureSurface(clientId: 'c-1', service: svc)));
    await tester.pumpAndSettle();

    expect(find.textContaining('marked done'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Repair'), findsNothing);
  });

  testWidgets('no banner while a section is still in progress — an unmarked '
      'row there is ordinary capture', (tester) async {
    final svc = _FakePedLanguageService(
      bandId: '2_to_3y',
      completedSections: const {}, // nothing declared done
      rows: await bandRows(leaveUnmarked: {'speech-2'}),
    );
    await tester.pumpWidget(host(
        PedLanguageCaptureSurface(clientId: 'c-1', service: svc)));
    await tester.pumpAndSettle();

    expect(find.textContaining('marked done'), findsNothing);
  });

  testWidgets('tapping Repair issues the completion write and clears the '
      'banner', (tester) async {
    final svc = _FakePedLanguageService(
      bandId: '2_to_3y',
      completedSections: {'speech'},
      rows: await bandRows(leaveUnmarked: {'speech-2'}),
    );
    await tester.pumpWidget(host(
        PedLanguageCaptureSurface(clientId: 'c-1', service: svc)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Speech is marked done'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Repair'));
    await tester.pumpAndSettle();

    expect(svc.completeCalls, 1);
    expect(svc.lastCompletedSection, 'speech');
    expect(svc.lastUnmarkedRowIds, ['speech-2'],
        reason: 'explicit id list — exactly the row that never saved');
    expect(find.textContaining('Speech is marked done'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Repair'), findsNothing);
  });

  testWidgets('a FAILED repair keeps the banner and tells her', (tester) async {
    final svc = _FakePedLanguageService(
      bandId: '2_to_3y',
      completedSections: {'speech'},
      rows: await bandRows(leaveUnmarked: {'speech-2'}),
      failCompletion: true,
    );
    await tester.pumpWidget(host(
        PedLanguageCaptureSurface(clientId: 'c-1', service: svc)));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Repair'));
    await tester.pump(); // let the failure land + SnackBar mount
    await tester.pump(const Duration(milliseconds: 100));

    expect(svc.completeCalls, 1);
    // The defect must not look fixed.
    expect(find.textContaining('Speech is marked done'), findsOneWidget);
    expect(find.textContaining('Could not repair the section'),
        findsOneWidget);
  });

  mainProvenanceDefault();
}

/// Review defect G: 'observed' used to be written by the marking tap itself
/// (`m.evidence ??= 'observed'`), which turned a pre-selected UI default into
/// a typed "the clinician saw it herself" clinical claim. A milestone she
/// marked on a parent's account persisted as clinician-observed, and the
/// reader promoted that to provenance: observed — licensing a drafted report
/// to say "observed in session" about an event that never happened.
///
/// The rule now: marking leaves evidence_source NULL until she chooses.
void mainProvenanceDefault() {
  group('G — marking writes no provenance', () {
    testWidgets('tapping a card to PRESENT persists status only, with a null '
        'evidence source', (tester) async {
      final svc = _FakePedLanguageService(
        bandId: '2_to_3y',
        completedSections: const {},
        rows: await bandRows(leaveUnmarked: {
          'speech-1', 'speech-2', 'speech-3',
        }),
      );
      await tester.pumpWidget(host(
          PedLanguageCaptureSurface(clientId: 'c-1', service: svc)));
      await tester.pumpAndSettle();

      // The first milestone card of the open (speech) section.
      final card = find.text(svc.rows
          .firstWhere((r) => r['id'] == 'speech-1')['milestone_text'] as String);
      expect(card, findsOneWidget);
      await tester.tap(card);
      await tester.pumpAndSettle();

      expect(svc.writes, hasLength(1));
      expect(svc.writes.single.status, 'present');
      expect(svc.writes.single.evidence, isNull,
          reason: 'a default here would claim she saw it herself');
      expect(svc.rows.firstWhere((r) => r['id'] == 'speech-1')
          ['evidence_source'], isNull);
    });

    testWidgets('she can still CHOOSE a source, and choosing persists it',
        (tester) async {
      final svc = _FakePedLanguageService(
        bandId: '2_to_3y',
        completedSections: const {},
        rows: await bandRows(leaveUnmarked: {
          'speech-1', 'speech-2', 'speech-3',
        }),
      );
      await tester.pumpWidget(host(
          PedLanguageCaptureSurface(clientId: 'c-1', service: svc)));
      await tester.pumpAndSettle();

      await tester.tap(find.text(svc.rows
          .firstWhere((r) => r['id'] == 'speech-1')['milestone_text'] as String));
      await tester.pumpAndSettle();
      // The toggle appears once marked; neither side is pre-selected.
      await tester.tap(find.text('Parent-reported').first);
      await tester.pumpAndSettle();

      expect(svc.writes.last.evidence, 'parent_reported');
      expect(svc.rows.firstWhere((r) => r['id'] == 'speech-1')
          ['evidence_source'], 'parent_reported');
    });
  });
}
