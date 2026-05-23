import 'package:flutter_test/flutter_test.dart';
import 'package:cue/models/session_outcome.dart';

void main() {
  group('SessionOutcome.fromString', () {
    test('parses all known DB values', () {
      expect(SessionOutcome.fromString('progress'), SessionOutcome.progress);
      expect(SessionOutcome.fromString('plan_revised'),
          SessionOutcome.planRevised);
      expect(SessionOutcome.fromString('holding'), SessionOutcome.holding);
    });

    test('unknown value returns null (never coerced to a tone)', () {
      expect(SessionOutcome.fromString('setback'), isNull);
      expect(SessionOutcome.fromString('failure'), isNull);
      expect(SessionOutcome.fromString('regression'), isNull);
      expect(SessionOutcome.fromString(''), isNull);
    });

    test('null returns null', () {
      expect(SessionOutcome.fromString(null), isNull);
    });
  });

  group('SessionOutcome.toDbValue', () {
    test('serialises to DB strings', () {
      expect(SessionOutcome.progress.toDbValue(), 'progress');
      expect(SessionOutcome.planRevised.toDbValue(), 'plan_revised');
      expect(SessionOutcome.holding.toDbValue(), 'holding');
    });

    test('all values round-trip through fromString', () {
      for (final o in SessionOutcome.values) {
        expect(SessionOutcome.fromString(o.toDbValue()), o,
            reason: '$o did not round-trip');
      }
    });
  });

  group('SessionOutcome.displayLabel', () {
    test('human-facing labels', () {
      expect(SessionOutcome.progress.displayLabel(), 'progress');
      expect(SessionOutcome.planRevised.displayLabel(), 'plan revised');
      expect(SessionOutcome.holding.displayLabel(), 'holding');
    });
  });
}
