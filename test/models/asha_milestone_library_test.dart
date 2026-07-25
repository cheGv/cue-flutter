// test/models/asha_milestone_library_test.dart
//
// Pediatric Language capture surface (Step 2) — headless coverage for
// the ASHA milestone dataset loader. Parses the REAL shipped asset from
// disk (no rootBundle in headless tests), pins band boundaries on both
// edges, and proves the parser fails loudly on structural damage.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cue/models/asha_milestone_library.dart';

String readRealAsset() =>
    File('assets/data/asha_language_milestones_0_5.json')
        .readAsStringSync();

Map<String, dynamic> decodeRealAsset() =>
    jsonDecode(readRealAsset()) as Map<String, dynamic>;

void main() {
  group('real shipped asset', () {
    late AshaMilestoneLibrary lib;

    setUpAll(() {
      lib = AshaMilestoneLibrary.fromJsonString(readRealAsset());
    });

    test('parses with all six bands in youngest-first order', () {
      expect(lib.bands.map((b) => b.bandId).toList(), [
        'birth_to_1y',
        '13_to_18m',
        '19_to_24m',
        '2_to_3y',
        '3_to_4y',
        '4_to_5y',
      ]);
    });

    test('carries the ASHA provenance sentence', () {
      expect(lib.source, contains('ASHA'));
    });

    test('carries the dataset version', () {
      expect(lib.version, '1.0.0');
    });

    test('per-band section counts match the source dataset', () {
      Map<String, int> counts(String bandId) {
        final band = lib.bandById(bandId)!;
        return band.sections.map((k, v) => MapEntry(k, v.length));
      }

      expect(counts('birth_to_1y'),
          {'speech': 3, 'language': 4, 'literacy': 1});
      expect(counts('13_to_18m'),
          {'speech': 1, 'language': 3, 'literacy': 1});
      expect(counts('19_to_24m'),
          {'speech': 1, 'language': 3, 'literacy': 1});
      expect(counts('2_to_3y'),
          {'speech': 3, 'language': 8, 'literacy': 1});
      expect(counts('3_to_4y'),
          {'speech': 5, 'language': 4, 'literacy': 3});
      expect(counts('4_to_5y'),
          {'speech': 2, 'language': 6, 'literacy': 3});
    });

    test('milestone order is 1-based and sequential within a section', () {
      for (final band in lib.bands) {
        for (final section in kAshaSections) {
          final list = band.sections[section]!;
          for (var i = 0; i < list.length; i++) {
            expect(list[i].order, i + 1,
                reason: '${band.bandId}/$section entry $i');
          }
        }
      }
    });

    test('only birth_to_1y carries the pre-verbal note', () {
      expect(lib.bandById('birth_to_1y')!.note, isNotNull);
      expect(lib.bandById('4_to_5y')!.note, isNull);
    });
  });

  group('bandForAgeMonths — inclusive boundaries', () {
    late AshaMilestoneLibrary lib;

    setUpAll(() {
      lib = AshaMilestoneLibrary.fromJsonString(readRealAsset());
    });

    test('birth band spans 0-12 inclusive', () {
      expect(lib.bandForAgeMonths(0)?.bandId, 'birth_to_1y');
      expect(lib.bandForAgeMonths(12)?.bandId, 'birth_to_1y');
      expect(lib.bandForAgeMonths(13)?.bandId, '13_to_18m');
    });

    test('every registry edge lands in its own band', () {
      expect(lib.bandForAgeMonths(18)?.bandId, '13_to_18m');
      expect(lib.bandForAgeMonths(19)?.bandId, '19_to_24m');
      expect(lib.bandForAgeMonths(24)?.bandId, '19_to_24m');
      expect(lib.bandForAgeMonths(25)?.bandId, '2_to_3y');
      expect(lib.bandForAgeMonths(36)?.bandId, '2_to_3y');
      expect(lib.bandForAgeMonths(37)?.bandId, '3_to_4y');
      expect(lib.bandForAgeMonths(48)?.bandId, '3_to_4y');
      expect(lib.bandForAgeMonths(49)?.bandId, '4_to_5y');
      expect(lib.bandForAgeMonths(60)?.bandId, '4_to_5y');
    });

    test('outside birth-5 returns null — never stretches a band', () {
      expect(lib.bandForAgeMonths(61), isNull);
      expect(lib.bandForAgeMonths(72), isNull);
      expect(lib.bandForAgeMonths(-1), isNull);
    });
  });

  group('parser fails loudly on structural damage', () {
    test('invalid JSON throws', () {
      expect(() => AshaMilestoneLibrary.fromJsonString('not json {'),
          throwsFormatException);
    });

    test('non-object root throws', () {
      expect(() => AshaMilestoneLibrary.fromJsonString('[1, 2]'),
          throwsFormatException);
    });

    test('missing source provenance throws', () {
      final json = decodeRealAsset()..remove('source');
      expect(() => AshaMilestoneLibrary.fromJson(json),
          throwsFormatException);
    });

    test('version-less dataset throws — never defaults', () {
      final json = decodeRealAsset()..remove('version');
      expect(() => AshaMilestoneLibrary.fromJson(json),
          throwsFormatException);
    });

    test('malformed version throws — every non-major.minor.patch shape', () {
      for (final bad in ['v1.0.0', '1.0', '', '1.0.0-beta', 1, null]) {
        final json = decodeRealAsset();
        json['version'] = bad;
        expect(() => AshaMilestoneLibrary.fromJson(json),
            throwsFormatException, reason: 'version = $bad');
      }
    });

    test('unknown band_id throws', () {
      final json = decodeRealAsset();
      ((json['age_bands'] as List).first
          as Map<String, dynamic>)['band_id'] = '5_to_6y';
      expect(() => AshaMilestoneLibrary.fromJson(json),
          throwsFormatException);
    });

    test('missing band throws', () {
      final json = decodeRealAsset();
      (json['age_bands'] as List).removeLast();
      expect(() => AshaMilestoneLibrary.fromJson(json),
          throwsFormatException);
    });

    test('duplicated band throws', () {
      final json = decodeRealAsset();
      final bandsList = json['age_bands'] as List;
      // Replace the last band with a copy of the first: birth_to_1y
      // now appears twice AND 4_to_5y is missing — either is fatal.
      bandsList[bandsList.length - 1] = bandsList.first;
      expect(() => AshaMilestoneLibrary.fromJson(json),
          throwsFormatException);
    });

    test('missing section throws', () {
      final json = decodeRealAsset();
      ((json['age_bands'] as List).first as Map<String, dynamic>)
          .remove('literacy');
      expect(() => AshaMilestoneLibrary.fromJson(json),
          throwsFormatException);
    });

    test('empty section throws', () {
      final json = decodeRealAsset();
      ((json['age_bands'] as List).first
          as Map<String, dynamic>)['speech'] = <dynamic>[];
      expect(() => AshaMilestoneLibrary.fromJson(json),
          throwsFormatException);
    });

    test('milestone entry without text throws', () {
      final json = decodeRealAsset();
      final speech = ((json['age_bands'] as List).first
          as Map<String, dynamic>)['speech'] as List;
      (speech.first as Map<String, dynamic>)['milestone'] = '';
      expect(() => AshaMilestoneLibrary.fromJson(json),
          throwsFormatException);
    });
  });
}
