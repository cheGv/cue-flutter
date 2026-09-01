// lib/services/assessment_bridge/assessment_context_assembler.dart
//
// Step 3 of the assessment data bridge: assembleAssessmentContext — folds an
// assessment reader's uniform envelope into the SAME canonical_data bundle the
// Mirror engine consumes (the shape produced today on the therapy side by
// FormatDrafterService.assembleCanonicalContext). It ADDS a new `assessment`
// block and reuses client_meta; the therapy-only keys are kept PRESENT but
// EMPTY for an assessment draft (adding a key is non-breaking — the engine
// reads the bundle through the same code path).
//
// SOURCE ATTRIBUTION IS PRESERVED VERBATIM. The assembler ARRANGES only: it
// embeds envelope.toJson() unchanged under `assessment`, so every finding's
// source_id / source_table / field_label / value / group survives exactly as
// the reader emitted it. The assembler NEVER invents, merges, drops, renames,
// or alters a finding. (That verbatim source tag is what the proxy will later
// rely on to enforce "every clinical claim traces to a source" — Step 4, a
// separate session. The proxy / /format-draft contract is NOT touched here.)

import '../../models/assessment_envelope.dart';
import '../../repositories/client_chart_state_repository.dart';
import 'cas_assessment_reader.dart';
import 'ped_language_assessment_reader.dart';
import 'voice_assessment_reader.dart';

class AssessmentContextAssembler {
  AssessmentContextAssembler({ClientChartStateRepository? chartStateRepository})
      : _chartStateRepo = chartStateRepository;

  // Held but NOT created in the constructor: ClientChartStateRepository touches
  // Supabase.instance, which is not initialised in unit tests (and the pure
  // assembleFromEnvelope needs no repository at all). The live path lazily
  // creates one when Supabase IS initialised; tests may inject a fake.
  final ClientChartStateRepository? _chartStateRepo;

  // Therapy-only canonical keys, kept PRESENT but EMPTY for an assessment draft
  // so the engine consumes the bundle through the same path. Shape mirrors
  // FormatDrafterService.assembleCanonicalContext (client_meta + these + the new
  // `assessment` block).
  static const List<String> _therapyOnlyKeys = [
    'substrate_cells',
    'long_term_goals',
    'short_term_goals',
    'sessions',
    'citations',
    'metrics',
  ];

  /// PURE arrangement: given a reader's [envelope] and the [clientMeta] map
  /// (ClientChartState.toJson() shape), produce the canonical_data bundle.
  /// No I/O; no mutation — embeds envelope.toJson() verbatim under `assessment`.
  /// This is the gate-tested core.
  Map<String, dynamic> assembleFromEnvelope({
    required AssessmentEnvelope envelope,
    required Map<String, dynamic> clientMeta,
  }) {
    return <String, dynamic>{
      'client_meta': clientMeta,
      for (final k in _therapyOnlyKeys) k: const <dynamic>[],
      'assessment': envelope.toJson(), // verbatim — source tags preserved
    };
  }

  /// Convenience: pick the reader for [protocol], load the assessment + the
  /// client's chart state, and assemble. (Not exercised by the pure gate.)
  Future<Map<String, dynamic>> assembleAssessmentContext({
    required String clientId,
    required String protocol,
    required String assessmentId,
  }) async {
    final envelope = await _readEnvelope(protocol, assessmentId);
    final repo = _chartStateRepo ?? ClientChartStateRepository();
    final chartState = await repo.loadForClient(clientId);
    return assembleFromEnvelope(
      envelope: envelope,
      clientMeta: chartState?.toJson() ?? const <String, dynamic>{},
    );
  }

  /// Every protocol this binary can actually turn into an envelope.
  ///
  /// Public because the protocol manifest advertises draftability to the
  /// clinician BEFORE she taps, and the two must not be able to disagree —
  /// a manifest entry naming a protocol missing from here would offer a draft
  /// that throws UnsupportedError halfway through. The manifest test asserts
  /// the containment; this set is what it asserts against.
  static const Set<String> supportedProtocols = {
    CasAssessmentReader.protocol, // 'pediatric-cas'
    VoiceAssessmentReader.protocol, // 'voice'
    PedLanguageAssessmentReader.protocol, // 'pediatric-language'
  };

  // Protocol -> reader. Structured so ped-dysarthria / ALD slot in here when
  // their readers land (no real captured data for them yet).
  Future<AssessmentEnvelope> _readEnvelope(String protocol, String assessmentId) {
    switch (protocol) {
      case CasAssessmentReader.protocol: // 'pediatric-cas'
        return CasAssessmentReader().readById(assessmentId);
      case VoiceAssessmentReader.protocol: // 'voice'
        return VoiceAssessmentReader().readById(assessmentId);
      case PedLanguageAssessmentReader.protocol: // 'pediatric-language'
        return PedLanguageAssessmentReader().readById(assessmentId);
      // case 'pediatric-dysarthria': return PedDysarthriaAssessmentReader().readById(assessmentId);
      // case 'adult-language-cognitive': return AldAssessmentReader().readById(assessmentId);
      default:
        throw UnsupportedError(
          'No assessment reader for protocol "$protocol" yet '
          '(supported: ${supportedProtocols.join(', ')}).',
        );
    }
  }
}
