import 'package:flutter_test/flutter_test.dart';
import 'package:cue/models/citation.dart';

void main() {
  final baseJson = <String, dynamic>{
    'id': 'cit-001',
    'stg_id': 'stg-001',
    'tier': 'level_1',
    'finding': 'Polyvagal-informed relationships reduce dysregulation episodes.',
    'author_year': 'Porges · 2011',
    'source_url': 'https://doi.org/10.0000/example',
    'display_order': 1,
  };

  group('EvidenceTier', () {
    test('all values round-trip toDbValue -> fromString', () {
      for (final t in EvidenceTier.values) {
        expect(EvidenceTier.fromString(t.toDbValue()), t,
            reason: '$t did not round-trip');
      }
    });

    test('DB strings are correct', () {
      expect(EvidenceTier.level1.toDbValue(), 'level_1');
      expect(EvidenceTier.level2.toDbValue(), 'level_2');
      expect(EvidenceTier.level3.toDbValue(), 'level_3');
      expect(EvidenceTier.practice.toDbValue(), 'practice');
    });

    test('unknown / null returns null', () {
      expect(EvidenceTier.fromString('level_4'), isNull);
      expect(EvidenceTier.fromString(''), isNull);
      expect(EvidenceTier.fromString(null), isNull);
    });

    test('display labels', () {
      expect(EvidenceTier.level1.displayLabel(), 'Level I');
      expect(EvidenceTier.level2.displayLabel(), 'Level II');
      expect(EvidenceTier.level3.displayLabel(), 'Level III');
      expect(EvidenceTier.practice.displayLabel(), 'Practice');
    });
  });

  group('Citation.fromJson', () {
    test('parses all fields', () {
      final c = Citation.fromJson(baseJson);
      expect(c.id, 'cit-001');
      expect(c.stgId, 'stg-001');
      expect(c.tier, EvidenceTier.level1);
      expect(c.finding, startsWith('Polyvagal'));
      expect(c.authorYear, 'Porges · 2011');
      expect(c.sourceUrl, 'https://doi.org/10.0000/example');
      expect(c.displayOrder, 1);
    });

    test('null source_url is allowed', () {
      final json = Map<String, dynamic>.from(baseJson)..['source_url'] = null;
      expect(Citation.fromJson(json).sourceUrl, isNull);
    });

    test('missing display_order defaults to 0', () {
      final json = Map<String, dynamic>.from(baseJson)..remove('display_order');
      expect(Citation.fromJson(json).displayOrder, 0);
    });

    test('display_order coerces num to int', () {
      final json = Map<String, dynamic>.from(baseJson)..['display_order'] = 2.0;
      expect(Citation.fromJson(json).displayOrder, 2);
    });

    test('unexpected tier falls back to practice (weakest)', () {
      final json = Map<String, dynamic>.from(baseJson)..['tier'] = 'bogus';
      expect(Citation.fromJson(json).tier, EvidenceTier.practice);
    });
  });

  group('Citation.toJson', () {
    test('uses DB column names and serialises tier', () {
      final json = Citation.fromJson(baseJson).toJson();
      expect(json['stg_id'], 'stg-001');
      expect(json['author_year'], 'Porges · 2011');
      expect(json['tier'], 'level_1');
      expect(json['display_order'], 1);
      expect(json.containsKey('stgId'), isFalse);
      expect(json.containsKey('authorYear'), isFalse);
    });

    test('omits null source_url', () {
      final c =
          Citation.fromJson(Map<String, dynamic>.from(baseJson)..['source_url'] = null);
      expect(c.toJson().containsKey('source_url'), isFalse);
    });

    test('round-trips fromJson -> toJson -> fromJson', () {
      final c = Citation.fromJson(baseJson);
      final r = Citation.fromJson(c.toJson());
      expect(r.id, c.id);
      expect(r.tier, c.tier);
      expect(r.displayOrder, c.displayOrder);
      expect(r.sourceUrl, c.sourceUrl);
    });
  });
}
