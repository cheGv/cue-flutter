import 'package:flutter_test/flutter_test.dart';
import 'package:cue/models/short_term_goal.dart';

void main() {
  // ── fixtures ──────────────────────────────────────────────────────────────

  final baseJson = <String, dynamic>{
    'id': 'stg-001',
    'long_term_goal_id': 'ltg-001',
    'client_id': 'client-001',
    'user_id': 'user-001',
    'specific': 'Produce /s/ in word-initial position',
    'measurable': '4/5 trials across 3 sessions',
    'target_accuracy': 80,
    'time_bound_sessions': 12,
    'sessions_attempted': 3,
    'sequence_num': 1,
    'is_ai_generated': false,
    'original_text': null,
    'target_behavior': 'Produce /s/ in word-initial position',
    'context': 'Structured drill',
    'mastery_criterion': {
      'accuracy_pct': 80,
      'consecutive_sessions': 3,
      'trials_per_session': 10,
    },
    'current_cue_level': 'moderate',
    'initial_cue_level': 'maximal',
    'cue_fade_plan': 'Step down one level per 2 sessions',
    'status': 'active',
    'current_accuracy': 72.5,
    'sessions_at_criterion': 0,
    'total_sessions_worked': 3,
    'framework': 'PROMPT',
    'domain': 'motor_speech',
    'parent_visible': false,
    'parent_friendly_label': null,
    'parent_routine_anchor': null,
    'notes': 'Client responds well to visual cues',
    'created_at': '2026-04-01T10:00:00.000Z',
    'updated_at': '2026-04-19T17:59:59.635Z',
    'mastered_at': null,
  };

  ShortTermGoal buildGoal() => ShortTermGoal.fromJson(baseJson);

  // ── CueLevel enum ─────────────────────────────────────────────────────────

  group('CueLevel', () {
    test('all values round-trip through toJson / fromString', () {
      for (final level in CueLevel.values) {
        final str = level.toJson();
        expect(CueLevel.fromString(str), level,
            reason: '$level → "$str" did not round-trip');
      }
    });

    test('hand_over_hand serialises correctly', () {
      expect(CueLevel.handOverHand.toJson(), 'hand_over_hand');
      expect(CueLevel.fromString('hand_over_hand'), CueLevel.handOverHand);
    });

    test('fromString(null) returns null', () {
      expect(CueLevel.fromString(null), isNull);
    });

    test('fromString with unrecognized value returns unknown (never throws)',
        () {
      // Open vocabulary: junk inputs must degrade, not crash the chart.
      expect(CueLevel.fromString('unknown_level'), CueLevel.unknown);
      expect(CueLevel.fromString('partial_physical'), CueLevel.unknown);
      expect(CueLevel.fromString(''), CueLevel.unknown);
    });
  });

  // ── StgDomain enum ────────────────────────────────────────────────────────

  group('StgDomain', () {
    test('all values round-trip', () {
      for (final d in StgDomain.values) {
        final str = d.toJson();
        expect(StgDomain.fromString(str), d,
            reason: '$d → "$str" did not round-trip');
      }
    });

    test('AAC variants serialise with correct casing', () {
      expect(StgDomain.aacOperational.toJson(), 'AAC_operational');
      expect(StgDomain.aacLinguistic.toJson(), 'AAC_linguistic');
      expect(StgDomain.aacSocial.toJson(), 'AAC_social');
    });

    test('snake_case variants serialise correctly', () {
      expect(StgDomain.expressiveLanguage.toJson(), 'expressive_language');
      expect(StgDomain.receptiveLanguage.toJson(), 'receptive_language');
      expect(StgDomain.motorSpeech.toJson(), 'motor_speech');
      expect(StgDomain.feedingSwallowing.toJson(), 'feeding_swallowing');
      expect(StgDomain.cognitiveCommunication.toJson(), 'cognitive_communication');
    });

    test('fromString(null) returns null', () {
      expect(StgDomain.fromString(null), isNull);
    });

    test('folds known dialect aliases to their canonical case (VOI → voice)',
        () {
      // Live data has both "VOI" and "voice"; both must parse to the same case.
      // Data-normalisation is a separate task — the parser tolerates both.
      expect(StgDomain.fromString('VOI'), StgDomain.voice);
      expect(StgDomain.fromString('voi'), StgDomain.voice);
      expect(StgDomain.fromString('voice'), StgDomain.voice);
      expect(StgDomain.fromString('Voice'), StgDomain.voice);
      expect(StgDomain.fromString('ART'), StgDomain.articulation);
      expect(StgDomain.fromString('FLU'), StgDomain.fluency);
    });

    test('fromString with unrecognized value returns unknown (never throws)',
        () {
      expect(StgDomain.fromString('garbage_domain'), StgDomain.unknown);
      expect(StgDomain.fromString('NONSENSE'), StgDomain.unknown);
    });
  });

  // ── StgFramework enum ─────────────────────────────────────────────────────

  group('StgFramework', () {
    test('all values round-trip', () {
      for (final f in StgFramework.values) {
        final str = f.toJson();
        expect(StgFramework.fromString(str), f,
            reason: '$f → "$str" did not round-trip');
      }
    });

    test('acronyms serialise upper-case', () {
      expect(StgFramework.prompt.toJson(), 'PROMPT');
      expect(StgFramework.opt.toJson(), 'OPT');
      expect(StgFramework.aac.toJson(), 'AAC');
      expect(StgFramework.nla.toJson(), 'NLA');
      expect(StgFramework.dir.toJson(), 'DIR');
      expect(StgFramework.pecs.toJson(), 'PECS');
    });

    test('compound names serialise with underscore', () {
      expect(StgFramework.coreWord.toJson(), 'Core_Word');
      expect(StgFramework.motorSpeech.toJson(), 'Motor_Speech');
      expect(StgFramework.phonologicalProcess.toJson(), 'Phonological_Process');
      expect(StgFramework.interoceptionInformed.toJson(), 'Interoception_Informed');
      expect(StgFramework.polyvagalInformed.toJson(), 'Polyvagal_Informed');
    });

    test('fromString with unrecognized value returns unknown (never throws)',
        () {
      // The original RVT crash: an unrecognised value MUST not throw. The
      // chart's STG section had this exact crash before tolerant parsing.
      expect(StgFramework.fromString('RVT_dialect'), StgFramework.unknown);
      expect(StgFramework.fromString('Unknown_Framework'), StgFramework.unknown);
      expect(StgFramework.fromString(''), StgFramework.unknown);
    });

    test('fromString(null) returns null', () {
      expect(StgFramework.fromString(null), isNull);
    });

    test('parses voice-domain technique frameworks', () {
      // RVT (Resonant Voice Therapy), VFE (Vocal Function Exercises),
      // LSVT-LOUD, SOVT — added so voice-domain STGs no longer crash the chart.
      expect(StgFramework.fromString('RVT'), StgFramework.rvt);
      expect(StgFramework.fromString('VFE'), StgFramework.vfe);
      expect(StgFramework.fromString('LSVT-LOUD'), StgFramework.lsvtLoud);
      expect(StgFramework.fromString('LSVT_LOUD'), StgFramework.lsvtLoud);
      expect(StgFramework.fromString('LSVT LOUD'), StgFramework.lsvtLoud);
      expect(StgFramework.fromString('SOVT'), StgFramework.sovt);
      expect(StgFramework.rvt.displayLabel(), 'Resonant Voice Therapy');
      expect(StgFramework.vfe.displayLabel(), 'Vocal Function Exercises');
      expect(StgFramework.lsvtLoud.displayLabel(), 'LSVT LOUD');
    });
  });

  // ── StgStatus enum ────────────────────────────────────────────────────────

  group('StgStatus', () {
    test('all values round-trip', () {
      for (final s in StgStatus.values) {
        final str = s.toJson();
        expect(StgStatus.fromString(str), s,
            reason: '$s → "$str" did not round-trip');
      }
    });

    test('on_hold serialises correctly', () {
      expect(StgStatus.onHold.toJson(), 'on_hold');
      expect(StgStatus.fromString('on_hold'), StgStatus.onHold);
    });

    test('unknown status defaults to active', () {
      expect(StgStatus.fromString('garbage'), StgStatus.active);
    });
  });

  // ── MasteryCriterion ──────────────────────────────────────────────────────

  group('MasteryCriterion', () {
    test('fromJson / toJson round-trip', () {
      const mc = MasteryCriterion(
          accuracyPct: 80, consecutiveSessions: 3, trialsPerSession: 10);
      final json = mc.toJson();
      final restored = MasteryCriterion.fromJson(json);
      expect(restored.accuracyPct, 80);
      expect(restored.consecutiveSessions, 3);
      expect(restored.trialsPerSession, 10);
    });

    test('fromJson coerces num to int', () {
      final mc = MasteryCriterion.fromJson({
        'accuracy_pct': 80.0,
        'consecutive_sessions': 3.0,
        'trials_per_session': 10.0,
      });
      expect(mc.accuracyPct, isA<int>());
    });

    test('hint-only blob parses with quantified fields null', () {
      // The voice-client shape: { "hint": "..." } with no numeric keys.
      // 4 of 7 STGs on feeb0c02-... carry this exact shape; before the fix
      // they parsed to an empty MasteryCriterion and the rule was lost.
      final mc = MasteryCriterion.fromJson({
        'hint': '80% phonation continuity across 3 consecutive sessions',
      });
      expect(mc.accuracyPct, isNull);
      expect(mc.consecutiveSessions, isNull);
      expect(mc.trialsPerSession, isNull);
      expect(mc.hint, '80% phonation continuity across 3 consecutive sessions');
      expect(mc.hasQuantifiedRule, isFalse);
    });

    test('hint-only blob round-trips through toJson without loss', () {
      const mc = MasteryCriterion(
          hint: '80% phonation continuity across 3 consecutive sessions');
      final json = mc.toJson();
      expect(json, {
        'hint': '80% phonation continuity across 3 consecutive sessions',
      });
      final restored = MasteryCriterion.fromJson(json);
      expect(restored.hint, mc.hint);
    });

    test('blank or whitespace hint is normalised to null', () {
      expect(MasteryCriterion.fromJson({'hint': ''}).hint, isNull);
      expect(MasteryCriterion.fromJson({'hint': '   '}).hint, isNull);
    });

    test('displayLine: quantified → composed clinical phrase', () {
      const mc = MasteryCriterion(
          accuracyPct: 80, consecutiveSessions: 3, trialsPerSession: 10);
      expect(mc.displayLine,
          '80% across 3 consecutive sessions of 10 trials each');
    });

    test('displayLine: quantified without trialsPerSession omits trial detail',
        () {
      const mc = MasteryCriterion(accuracyPct: 80, consecutiveSessions: 3);
      expect(mc.displayLine, '80% across 3 consecutive sessions');
    });

    test('displayLine: hint-only → the hint verbatim', () {
      const mc = MasteryCriterion(
          hint: '80% phonation continuity across 3 consecutive sessions');
      expect(mc.displayLine,
          '80% phonation continuity across 3 consecutive sessions');
    });

    test('displayLine: partial quantified blob without consecutive_sessions '
        'falls through to hint (no "X% for null sessions" string)', () {
      const mc = MasteryCriterion(accuracyPct: 80, hint: 'see plan notes');
      expect(mc.hasQuantifiedRule, isFalse);
      expect(mc.displayLine, 'see plan notes');
    });

    test('displayLine: both quantified + hint → quantified wins, '
        'hint preserved on round-trip but not surfaced', () {
      const mc = MasteryCriterion(
          accuracyPct: 80,
          consecutiveSessions: 3,
          hint: 'see plan notes for caveats');
      expect(mc.displayLine, '80% across 3 consecutive sessions');
      // Hint not lost — still present on the model and in toJson.
      expect(mc.hint, 'see plan notes for caveats');
      expect(mc.toJson()['hint'], 'see plan notes for caveats');
    });

    test('displayLine: empty blob → null', () {
      const mc = MasteryCriterion();
      expect(mc.displayLine, isNull);
    });
  });

  // ── ShortTermGoal.fromJson ────────────────────────────────────────────────

  group('ShortTermGoal.fromJson', () {
    test('parses all fields correctly', () {
      final stg = buildGoal();
      expect(stg.id, 'stg-001');
      expect(stg.longTermGoalId, 'ltg-001');
      expect(stg.clientId, 'client-001');
      expect(stg.userId, 'user-001');
      expect(stg.specific, 'Produce /s/ in word-initial position');
      expect(stg.measurable, '4/5 trials across 3 sessions');
      expect(stg.targetAccuracy, 80);
      expect(stg.timeBoundSessions, 12);
      expect(stg.sessionsAttempted, 3);
      expect(stg.sequenceNum, 1);
      expect(stg.isAiGenerated, isFalse);
      expect(stg.targetBehavior, 'Produce /s/ in word-initial position');
      expect(stg.context, 'Structured drill');
      expect(stg.masteryCriterion!.accuracyPct, 80);
      expect(stg.masteryCriterion!.consecutiveSessions, 3);
      expect(stg.masteryCriterion!.trialsPerSession, 10);
      expect(stg.currentCueLevel, CueLevel.moderate);
      expect(stg.initialCueLevel, CueLevel.maximal);
      expect(stg.status, StgStatus.active);
      expect(stg.currentAccuracy, 72.5);
      expect(stg.sessionsAtCriterion, 0);
      expect(stg.totalSessionsWorked, 3);
      expect(stg.framework, StgFramework.prompt);
      expect(stg.domain, StgDomain.motorSpeech);
      expect(stg.parentVisible, isFalse);
      expect(stg.notes, 'Client responds well to visual cues');
      expect(stg.createdAt, DateTime.parse('2026-04-01T10:00:00.000Z'));
      expect(stg.masteredAt, isNull);
    });

    test('handles nullable fields as null', () {
      final json = Map<String, dynamic>.from(baseJson)
        ..['mastery_criterion'] = null
        ..['current_cue_level'] = null
        ..['initial_cue_level'] = null
        ..['framework'] = null
        ..['domain'] = null
        ..['current_accuracy'] = null
        ..['mastered_at'] = null;
      final stg = ShortTermGoal.fromJson(json);
      expect(stg.masteryCriterion, isNull);
      expect(stg.currentCueLevel, isNull);
      expect(stg.framework, isNull);
      expect(stg.domain, isNull);
      expect(stg.currentAccuracy, isNull);
      expect(stg.masteredAt, isNull);
    });

    test('defaults missing optional fields', () {
      final minimal = <String, dynamic>{
        'id': 'stg-min',
        'long_term_goal_id': 'ltg-min',
        'client_id': 'client-min',
        'user_id': 'user-min',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      };
      final stg = ShortTermGoal.fromJson(minimal);
      expect(stg.specific, '');
      expect(stg.measurable, '');
      expect(stg.sessionsAttempted, 0);
      expect(stg.sessionsAtCriterion, 0);
      expect(stg.totalSessionsWorked, 0);
      expect(stg.isAiGenerated, isFalse);
      expect(stg.parentVisible, isFalse);
      expect(stg.status, StgStatus.active);
    });

    test('parses mastered_at when present', () {
      final json = Map<String, dynamic>.from(baseJson)
        ..['mastered_at'] = '2026-04-15T12:00:00Z'
        ..['status'] = 'mastered';
      final stg = ShortTermGoal.fromJson(json);
      expect(stg.masteredAt, DateTime.parse('2026-04-15T12:00:00Z'));
      expect(stg.status, StgStatus.mastered);
    });
  });

  // ── ShortTermGoal.toJson ──────────────────────────────────────────────────

  group('ShortTermGoal.toJson', () {
    test('round-trips through fromJson → toJson', () {
      final stg = buildGoal();
      final json = stg.toJson();
      final restored = ShortTermGoal.fromJson(json);
      expect(restored.id, stg.id);
      expect(restored.longTermGoalId, stg.longTermGoalId);
      expect(restored.clientId, stg.clientId);
      expect(restored.framework, stg.framework);
      expect(restored.domain, stg.domain);
      expect(restored.currentCueLevel, stg.currentCueLevel);
      expect(restored.status, stg.status);
      expect(restored.currentAccuracy, stg.currentAccuracy);
    });

    test('uses DB column names, not Dart field names', () {
      final json = buildGoal().toJson();
      expect(json.containsKey('long_term_goal_id'), isTrue);
      expect(json.containsKey('client_id'), isTrue);
      expect(json.containsKey('user_id'), isTrue);
      expect(json.containsKey('is_ai_generated'), isTrue);
      expect(json.containsKey('sessions_at_criterion'), isTrue);
      expect(json.containsKey('total_sessions_worked'), isTrue);
      // Must NOT contain Dart-only names
      expect(json.containsKey('longTermGoalId'), isFalse);
      expect(json.containsKey('clientId'), isFalse);
    });

    test('omits null optional fields', () {
      // Use fromJson with null to get a goal that genuinely has null notes.
      // copyWith(notes: null) means "keep existing" per Flutter convention.
      final json = ShortTermGoal.fromJson({
        ...baseJson,
        'notes': null,
        'parent_friendly_label': null,
        'parent_routine_anchor': null,
      }).toJson();
      expect(json.containsKey('notes'), isFalse);
      expect(json.containsKey('parent_friendly_label'), isFalse);
    });

    test('serialises framework to DB string', () {
      final json = buildGoal().toJson();
      expect(json['framework'], 'PROMPT');
      expect(json['domain'], 'motor_speech');
      expect(json['current_cue_level'], 'moderate');
      expect(json['status'], 'active');
    });
  });

  // ── ShortTermGoal.copyWith ────────────────────────────────────────────────

  group('ShortTermGoal.copyWith', () {
    test('returns equal object when no fields changed', () {
      final stg = buildGoal();
      final copy = stg.copyWith();
      expect(copy.id, stg.id);
      expect(copy.status, stg.status);
      expect(copy.framework, stg.framework);
    });

    test('only mutates specified fields', () {
      final stg = buildGoal();
      final updated = stg.copyWith(
        status: StgStatus.mastered,
        currentAccuracy: 88.0,
      );
      expect(updated.status, StgStatus.mastered);
      expect(updated.currentAccuracy, 88.0);
      expect(updated.id, stg.id);
      expect(updated.clientId, stg.clientId);
      expect(updated.framework, stg.framework);
    });
  });

  // ── Open-vocabulary raw-string preservation ───────────────────────────────
  //
  // Regression suite for the RVT-style chart crash. Any STG with an
  // unrecognised framework / domain / cue-level must (a) NOT throw during
  // parsing and (b) preserve the raw DB string so the UI can still show it.

  group('ShortTermGoal open-vocabulary fallback', () {
    test('fromJson with unknown framework parses without throwing', () {
      final json = Map<String, dynamic>.from(baseJson)..['framework'] = 'RVT_X';
      final stg = ShortTermGoal.fromJson(json);
      expect(stg.framework, StgFramework.unknown);
      expect(stg.frameworkRaw, 'RVT_X');
      expect(stg.frameworkDisplay, 'RVT_X');
    });

    test('fromJson with first-class RVT lands on the new enum case', () {
      final json = Map<String, dynamic>.from(baseJson)..['framework'] = 'RVT';
      final stg = ShortTermGoal.fromJson(json);
      expect(stg.framework, StgFramework.rvt);
      // Known case → no raw needed; display uses the human label.
      expect(stg.frameworkRaw, isNull);
      expect(stg.frameworkDisplay, 'Resonant Voice Therapy');
    });

    test('fromJson with unknown domain parses without throwing', () {
      final json = Map<String, dynamic>.from(baseJson)
        ..['domain'] = 'novel_domain_token';
      final stg = ShortTermGoal.fromJson(json);
      expect(stg.domain, StgDomain.unknown);
      expect(stg.domainRaw, 'novel_domain_token');
      expect(stg.domainDisplay, 'novel_domain_token');
    });

    test('fromJson folds "VOI" to voice and leaves domainRaw null', () {
      // Dialect alias — known mapping, no raw fallback needed.
      final json = Map<String, dynamic>.from(baseJson)..['domain'] = 'VOI';
      final stg = ShortTermGoal.fromJson(json);
      expect(stg.domain, StgDomain.voice);
      expect(stg.domainRaw, isNull);
      expect(stg.domainDisplay, 'voice');
    });

    test('fromJson with unknown cue level preserves raw on both fields', () {
      final json = Map<String, dynamic>.from(baseJson)
        ..['current_cue_level'] = 'tactile_assist'
        ..['initial_cue_level'] = 'tactile_assist';
      final stg = ShortTermGoal.fromJson(json);
      expect(stg.currentCueLevel, CueLevel.unknown);
      expect(stg.currentCueLevelRaw, 'tactile_assist');
      expect(stg.initialCueLevel, CueLevel.unknown);
      expect(stg.initialCueLevelRaw, 'tactile_assist');
      expect(stg.currentCueLevelDisplay, 'tactile_assist');
      expect(stg.initialCueLevelDisplay, 'tactile_assist');
    });

    test('display getters return null when the field itself is null', () {
      final json = Map<String, dynamic>.from(baseJson)
        ..['framework'] = null
        ..['domain'] = null
        ..['current_cue_level'] = null
        ..['initial_cue_level'] = null;
      final stg = ShortTermGoal.fromJson(json);
      expect(stg.frameworkDisplay, isNull);
      expect(stg.domainDisplay, isNull);
      expect(stg.currentCueLevelDisplay, isNull);
      expect(stg.initialCueLevelDisplay, isNull);
    });

    test('toJson round-trips an unknown framework via the raw string', () {
      // Critical: writing the goal back must NOT clobber the unrecognised
      // clinical value with "unknown" — round-trip the original DB token.
      final json = Map<String, dynamic>.from(baseJson)..['framework'] = 'RVT_X';
      final stg = ShortTermGoal.fromJson(json);
      final out = stg.toJson();
      expect(out['framework'], 'RVT_X');
    });

    test('toJson round-trips an unknown domain via the raw string', () {
      final json = Map<String, dynamic>.from(baseJson)
        ..['domain'] = 'novel_domain_token';
      final stg = ShortTermGoal.fromJson(json);
      final out = stg.toJson();
      expect(out['domain'], 'novel_domain_token');
    });

    test('the voice-client null trial fields parse without crashing', () {
      // Mirrors the actual data shape that crashed the chart for the
      // feeb0c02-0000-4000-8000-00000000c102 voice client: framework RVT,
      // null target_accuracy + null time_bound_sessions + null
      // mastery_criterion. Asserts no throw and correct field shape.
      final json = Map<String, dynamic>.from(baseJson)
        ..['framework'] = 'RVT'
        ..['domain'] = 'voice'
        ..['target_accuracy'] = null
        ..['time_bound_sessions'] = null
        ..['mastery_criterion'] = null;
      expect(() => ShortTermGoal.fromJson(json), returnsNormally);
      final stg = ShortTermGoal.fromJson(json);
      expect(stg.framework, StgFramework.rvt);
      expect(stg.domain, StgDomain.voice);
      expect(stg.targetAccuracy, isNull);
      expect(stg.timeBoundSessions, isNull);
      expect(stg.masteryCriterion, isNull);
    });
  });
}
