// test/protocols/protocol_manifest_test.dart
//
// The manifest's job is to be the thing that CANNOT drift from the
// binary. These tests are what makes that true rather than aspirational:
//   * every entry's references actually resolve (the surface builds, the
//     reader binding is wired to a real reader),
//   * the reader set matches what AssessmentContextAssembler can
//     actually dispatch — so the manifest can never advertise a draft
//     the assembler would throw on,
//   * covered + explicitly-uncovered EXACTLY partitions kClinicalAreas,
//     so a newly added clinical area cannot arrive with neither a
//     protocol nor a decision.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cue/constants/clinical_areas.dart';
import 'package:cue/protocols/protocol_manifest.dart';
import 'package:cue/services/assessment_bridge/cas_assessment_reader.dart';
import 'package:cue/services/assessment_bridge/voice_assessment_reader.dart';
import 'package:cue/widgets/assessment/ald_capture_section.dart';
import 'package:cue/widgets/assessment/cas_assessment_surface.dart';
import 'package:cue/widgets/assessment/ped_dysarthria_capture_section.dart';
import 'package:cue/widgets/assessment/ped_language_capture_surface.dart';
import 'package:cue/widgets/assessment/ssd_capture_section.dart';
import 'package:cue/widgets/assessment/voice_capture_section.dart';

void main() {
  group('every entry resolves its references', () {
    test('buildSurface constructs a widget for every entry', () {
      for (final p in kProtocolManifest) {
        final w = p.buildSurface('test-client-id');
        expect(w, isA<Widget>(), reason: p.code);
      }
    });

    test('each entry builds the EXPECTED surface widget type', () {
      Type typeOf(String code) =>
          protocolByCode(code)!.buildSurface('c').runtimeType;
      expect(typeOf('voice'), VoiceCaptureSection);
      expect(typeOf('ped-cas'), CasAssessmentSurface);
      expect(typeOf('ped-dysarthria'), PedDysarthriaCaptureSection);
      expect(typeOf('ald'), AldCaptureSection);
      expect(typeOf('ped-language'), PedLanguageCaptureSurface);
      expect(typeOf('ssd-screen'), SsdCaptureSection);
    });

    test('codes are unique', () {
      final codes = kProtocolManifest.map((p) => p.code).toList();
      expect(codes.toSet().length, codes.length);
    });

    test('every clinicalArea is a real kClinicalAreas code', () {
      final known = kClinicalAreas.map((a) => a.code).toSet();
      for (final p in kProtocolManifest) {
        expect(known, contains(p.clinicalArea), reason: p.code);
      }
    });

    test('display names are non-empty', () {
      for (final p in kProtocolManifest) {
        expect(p.displayName.trim(), isNotEmpty, reason: p.code);
      }
    });
  });

  group('reader bindings cannot advertise a draft the assembler '
      'would throw on', () {
    test('a binding, where present, is fully wired and its protocol '
        'equals the entry clinical area', () {
      for (final p in kProtocolManifest) {
        final r = p.reader;
        if (r == null) continue;
        expect(r.protocol, p.clinicalArea, reason: p.code);
        expect(r.read, isNotNull, reason: p.code);
        expect(r.resolveAssessmentId, isNotNull, reason: p.code);
      }
    });

    test('the draftable set is exactly the readers this binary has', () {
      // Tied to the reader classes themselves — if a reader is deleted
      // this stops compiling; if one is added without a manifest entry
      // (or vice versa) this fails.
      final supported = {
        CasAssessmentReader.protocol,
        VoiceAssessmentReader.protocol,
      };
      final advertised = {
        for (final p in kProtocolManifest)
          if (p.isDraftable) p.reader!.protocol,
      };
      expect(advertised, supported);
    });

    test('isDraftable is exactly reader != null', () {
      for (final p in kProtocolManifest) {
        expect(p.isDraftable, p.reader != null, reason: p.code);
      }
    });

    test('the four capture-only protocols are honestly marked', () {
      for (final code in ['ped-dysarthria', 'ald', 'ped-language',
          'ssd-screen']) {
        expect(protocolByCode(code)!.isDraftable, isFalse, reason: code);
      }
    });
  });

  group('coverage partitions kClinicalAreas', () {
    test('covered + uncovered is EXACTLY kClinicalAreas, no overlap, '
        'no gap', () {
      final all = kClinicalAreas.map((a) => a.code).toSet();
      final covered =
          kProtocolManifest.map((p) => p.clinicalArea).toSet();

      expect(covered.intersection(kUncoveredClinicalAreas), isEmpty,
          reason: 'an area cannot be both covered and acknowledged-uncovered');
      expect(covered.union(kUncoveredClinicalAreas), all,
          reason: 'a new clinical area must either get a protocol or be '
              'added to kUncoveredClinicalAreas — never silently neither');
      expect(kUncoveredClinicalAreas.difference(all), isEmpty,
          reason: 'uncovered list names an area that no longer exists');
    });

    test('one area may serve several protocols — speech-sound-disorders '
        'is the live case', () {
      // Not hypothetical: the SSD screen stub is here, and the Dodd
      // differential surface joins it when its branch merges.
      expect(protocolsForArea('speech-sound-disorders'), isNotEmpty);
      expect(protocolsForArea('voice').length, 1);
      expect(protocolsForArea('fluency'), isEmpty);
      expect(protocolsForArea(null), isEmpty);
      expect(protocolsForArea(''), isEmpty);
    });

    test('soleProtocolForArea returns null when the area has none', () {
      expect(soleProtocolForArea('fluency'), isNull);
      expect(soleProtocolForArea('voice')?.code, 'voice');
    });

    test('protocolByCode resolves and misses cleanly', () {
      expect(protocolByCode('ped-language')?.clinicalArea,
          'pediatric-language');
      expect(protocolByCode('nope'), isNull);
    });
  });

  group('surface maturity is stated honestly', () {
    test('the SSD screen is marked stub, not shipped', () {
      expect(protocolByCode('ssd-screen')!.surfaceStatus,
          ProtocolSurfaceStatus.stub);
    });

    test('every other entry is shipped', () {
      for (final p in kProtocolManifest) {
        if (p.code == 'ssd-screen') continue;
        expect(p.surfaceStatus, ProtocolSurfaceStatus.shipped,
            reason: p.code);
      }
    });
  });
}
