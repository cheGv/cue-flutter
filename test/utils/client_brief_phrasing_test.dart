import 'package:cue/models/client_brief_signals.dart';
import 'package:cue/utils/client_brief_phrasing.dart';
import 'package:flutter_test/flutter_test.dart';

// Layer 3 — phrasing. Deterministic templates → exact-match assertions.

ClientBriefSignals _sig(
  BriefLead lead, {
  int sessions = 0,
  List<String> pending = const [],
  int days = 0,
  bool first = false,
  int active = 0,
}) =>
    ClientBriefSignals(
      lead: lead,
      sessionsSinceLastVisit: sessions,
      pendingGoalCodes: pending,
      daysSinceLastSeen: days,
      isFirstVisit: first,
      activeGoalCount: active,
    );

String _phrase(ClientBriefSignals s, {String name = 'Ratnadeep'}) =>
    phraseClientBrief(s, clientName: name);

void main() {
  group('per-lead sentence shape', () {
    test('newActivity leads with sessions since last visit', () {
      expect(
        _phrase(_sig(BriefLead.newActivity, sessions: 2)),
        'Ratnadeep — two sessions logged since you last opened the file.',
      );
    });

    test('newActivity + pending adds one lighter secondary thread (no codes)',
        () {
      expect(
        _phrase(_sig(BriefLead.newActivity,
            sessions: 1, pending: ['1.A', '1.B', '1.C'])),
        'Ratnadeep — one session logged since you last opened the file. '
        'Three short-term goals are still to be taken up.',
      );
    });

    test('pending (1) names the goal by type + code', () {
      expect(
        _phrase(_sig(BriefLead.pending, pending: ['1.B'])),
        'Ratnadeep has one short-term goal still to be taken up — '
        'short-term goal 1.B.',
      );
    });

    test('pending (2) names both by type + codes', () {
      expect(
        _phrase(_sig(BriefLead.pending, pending: ['1.B', '1.C'])),
        'Ratnadeep has two short-term goals still to be taken up — '
        'short-term goals 1.B and 1.C.',
      );
    });

    test('pending (many) reports a COUNT, never lists codes', () {
      final out = _phrase(_sig(BriefLead.pending,
          pending: ['1.B', '1.C', '2.A', '2.B', '2.C', '3.A']));
      expect(out, 'Ratnadeep has six short-term goals still to be taken up.');
      // Not one of the six codes leaks into the sentence (brief, not dashboard).
      for (final code in ['1.B', '1.C', '2.A', '2.B', '2.C', '3.A']) {
        expect(out.contains(code), isFalse, reason: 'code $code leaked');
      }
    });

    test('longGap leads with the gap in days', () {
      expect(
        _phrase(_sig(BriefLead.longGap, days: 21)),
        "It's been 21 days since you saw Ratnadeep.",
      );
    });

    test('longGap + pending adds the lighter secondary', () {
      expect(
        _phrase(_sig(BriefLead.longGap, days: 21, pending: ['2.A'])),
        "It's been 21 days since you saw Ratnadeep. "
        'One short-term goal is still to be taken up.',
      );
    });

    test('firstVisit orients with the goal count', () {
      expect(
        _phrase(_sig(BriefLead.firstVisit, first: true, active: 7)),
        "Opening Ratnadeep's file for the first time — "
        'seven short-term goals on the plan.',
      );
    });

    test('firstVisit with one goal uses singular', () {
      expect(
        _phrase(_sig(BriefLead.firstVisit, first: true, active: 1)),
        "Opening Ratnadeep's file for the first time — "
        'one short-term goal on the plan.',
      );
    });

    test('firstVisit with no goals drops the count', () {
      expect(
        _phrase(_sig(BriefLead.firstVisit, first: true, active: 0)),
        "Opening Ratnadeep's file for the first time.",
      );
    });

    test('nothingNew is the warm steady floor', () {
      expect(
        _phrase(_sig(BriefLead.nothingNew)),
        'Ratnadeep is steady — nothing new since your last session.',
      );
    });
  });

  group('voice + law constraints', () {
    test('blank client name degrades gracefully', () {
      expect(
        _phrase(_sig(BriefLead.pending, pending: ['1.B']), name: ''),
        'this client has one short-term goal still to be taken up — '
        'short-term goal 1.B.',
      );
    });

    test('every code is named with its type word — never a bare code', () {
      // 1- and 2-code cases: the code always follows "short-term goal(s) ".
      for (final s in [
        _sig(BriefLead.pending, pending: ['1.B']),
        _sig(BriefLead.pending, pending: ['1.B', '1.C']),
      ]) {
        final out = _phrase(s);
        final codeRe = RegExp(r'(\d+\.[A-Z])');
        for (final m in codeRe.allMatches(out)) {
          final before = out.substring(0, m.start);
          expect(before.endsWith('short-term goal ') ||
              before.endsWith('short-term goals ') ||
              before.endsWith('and '), isTrue,
              reason: 'bare code in: $out');
        }
      }
    });

    test('no evaluation / forecast / advice vocabulary appears', () {
      const banned = [
        'progress', 'improv', 'declin', 'mastery', 'on track',
        'doing well', 'better', 'worse', 'should', 'recommend', 'try to',
      ];
      final samples = [
        _phrase(_sig(BriefLead.newActivity, sessions: 3, pending: ['1.A'])),
        _phrase(_sig(BriefLead.pending, pending: ['1.B'])),
        _phrase(_sig(BriefLead.pending, pending: ['1.B', '1.C', '2.A'])),
        _phrase(_sig(BriefLead.longGap, days: 30)),
        _phrase(_sig(BriefLead.firstVisit, first: true, active: 4)),
        _phrase(_sig(BriefLead.nothingNew)),
      ];
      for (final out in samples) {
        final low = out.toLowerCase();
        for (final w in banned) {
          expect(low.contains(w), isFalse, reason: '"$w" in: $out');
        }
      }
    });

    test('name-first leads start with the client name', () {
      expect(_phrase(_sig(BriefLead.newActivity, sessions: 1)).startsWith('Ratnadeep'), isTrue);
      expect(_phrase(_sig(BriefLead.pending, pending: ['1.B'])).startsWith('Ratnadeep'), isTrue);
      expect(_phrase(_sig(BriefLead.nothingNew)).startsWith('Ratnadeep'), isTrue);
    });
  });
}
