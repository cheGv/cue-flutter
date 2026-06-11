// test/services/feeding_sandbox_roundtrip_test.dart
//
// ONLINE integration gate — the one layer the headless tests can't reach:
// the real FeedingAssessmentService ↔ sandbox save/load path. It drives the
// actual service methods (parent patch through the allowlist, the 7-band
// ladder seeding + idempotent re-seed, band marking round-trip, behaviour
// child add/mark/remove) against the live sandbox, reads the rows back, and
// asserts EMPTY STAYS EMPTY on the real DB (freshly seeded bands carry NULL
// clinician_marking — no fabricated marks). It cleans up after itself
// (cascade delete via the parent) and verifies the cascade.
//
// No reader assertions — feeding has no reader in Phase 1 (non-draftable by
// design; graduation is a later phase, exactly like SSD's).
//
// Skipped unless FEEDING_SANDBOX=1 so the default offline `flutter test`
// stays green:
//   $env:FEEDING_SANDBOX='1'; flutter test test/services/feeding_sandbox_roundtrip_test.dart

import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cue/config/app_config.dart';
import 'package:cue/services/feeding_assessment_service.dart';

void main() {
  final online = Platform.environment['FEEDING_SANDBOX'] == '1';

  test(
    'service <-> sandbox round-trip: seed, mark, behaviours, cascade cleanup',
    () async {
      // Direct sandbox client (no Supabase.initialize / auth needed — RLS is
      // off on the feeding_* tables, captured-as-is like the SSD siblings).
      final sb = SupabaseClient(kSupabaseUrlSandbox, kSupabaseAnonKeySandbox);
      final svc = FeedingAssessmentService.withClient(sb);

      // An existing client to satisfy the FK. `clients` is RLS-guarded for a
      // raw anon client (no session), so we use a known id (overridable via
      // env) rather than reading the table — the FK still validates
      // server-side. Same id the SSD round-trip uses.
      final clientId = Platform.environment['FEEDING_TEST_CLIENT'] ??
          '1aeba020-a649-4e0f-be8f-50b5f9fa9ca4';

      // A throwaway parent row (marked for cleanup).
      final inserted = await sb
          .from('feeding_assessments')
          .insert({'client_id': clientId, 'capture_notes': '__feeding_uitest__'})
          .select()
          .single();
      final id = inserted['id'] as String;

      try {
        // ── Ladder seeding: 7 bands, EMPTY STAYS EMPTY on the real DB ──────
        final bands = await svc.ensureLadderBands(id);
        expect(bands, hasLength(7));
        for (var i = 0; i < bands.length; i++) {
          expect(bands[i]['band_order'], i + 1);
          expect(bands[i]['clinician_marking'], isNull,
              reason: 'freshly seeded band must carry NO mark');
          expect(bands[i]['notes'], isNull);
          expect(bands[i]['expected_texture'], isNotNull);
          expect(bands[i]['red_flag_prompt'], isNotNull);
        }
        expect(bands.last['age_max_months'], isNull); // open-ended 30–36+
        expect(bands.where((b) => b['off_ramp_band'] == true), hasLength(3));

        // Re-seed is idempotent — still exactly 7.
        final again = await svc.ensureLadderBands(id);
        expect(again, hasLength(7));

        // ── Parent patch through the allowlist; untouched stays NULL ──────
        await svc.saveAssessmentColumns(assessmentId: id, data: {
          'age_months': 20,
          'jaw_stability': 'present',
          'tongue_control': 'emerging',
          'jaw_lip_dissociation_notes': 'sandbox round-trip probe',
        });
        final parent = Map<String, dynamic>.from(
            await sb.from('feeding_assessments').select().eq('id', id).single());
        expect(parent['age_months'], 20);
        expect(parent['jaw_stability'], 'present');
        expect(parent['tongue_control'], 'emerging');
        expect(parent['jaw_lip_dissociation_notes'], 'sandbox round-trip probe');
        expect(parent['lip_control'], isNull,
            reason: 'untouched clinical column stays NULL — empty stays empty');

        // ── Band marking round-trip (the clinician's call, hers alone) ────
        final band5 =
            bands.firstWhere((b) => b['band_key'] == '18_24mo');
        await svc.updateRow(
          table: 'feeding_ladder_bands',
          rowId: band5['id'] as String,
          data: {'clinician_marking': 'below_level', 'notes': 'marked in test'},
        );
        final reread = await svc.ensureLadderBands(id);
        expect(
            reread.firstWhere((b) => b['band_key'] == '18_24mo')[
                'clinician_marking'],
            'below_level');
        expect(
            reread.firstWhere((b) => b['band_key'] == '12_18mo')[
                'clinician_marking'],
            isNull,
            reason: 'marking one band must not touch its neighbours');

        // ── Behaviours child: add (starter + airway), mark, remove ────────
        final pocketingId = await svc.insertRow(
          table: 'feeding_behaviors',
          assessmentId: id,
          data: {
            'behavior_key': 'pocketing',
            'behavior_label':
                'Pocketing — holding food in the cheeks without swallowing',
            'airway_sign': false,
            'status': 'present',
          },
        );
        final airwayId = await svc.insertRow(
          table: 'feeding_behaviors',
          assessmentId: id,
          data: {
            'behavior_key': 'airway_signs_textured',
            'behavior_label':
                'Coughing, choking, or wet-sounding voice with textured food',
            'airway_sign': true,
          },
        );
        await svc.updateRow(
            table: 'feeding_behaviors',
            rowId: airwayId,
            data: {'status': 'present'});

        var behaviors = await svc.loadRows('feeding_behaviors', id);
        expect(behaviors, hasLength(2));
        final airwayRow =
            behaviors.firstWhere((b) => b['id'] == airwayId);
        expect(airwayRow['airway_sign'], true);
        expect(airwayRow['status'], 'present');

        await svc.deleteRow(table: 'feeding_behaviors', rowId: pocketingId);
        behaviors = await svc.loadRows('feeding_behaviors', id);
        expect(behaviors, hasLength(1));
      } finally {
        // Cleanup — cascade removes the children; verify it actually did.
        await sb.from('feeding_assessments').delete().eq('id', id);
        final orphans = await sb
            .from('feeding_ladder_bands')
            .select('id')
            .eq('feeding_assessment_id', id);
        expect(orphans as List, isEmpty,
            reason: 'ON DELETE CASCADE must remove the seeded bands');
        await sb.dispose();
      }
    },
    timeout: const Timeout(Duration(seconds: 90)),
    skip: online ? false : 'online sandbox gate — set FEEDING_SANDBOX=1 to run',
  );
}
