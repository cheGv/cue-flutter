// lib/protocols/protocol_manifest.dart
//
// THE PROTOCOL MANIFEST — the runtime-enumerable answer to two questions
// the app previously could only answer with a hardcoded if-chain:
//   "which protocols exist for this clinical area?"   -> protocolsForArea()
//   "can this one be turned into a report?"           -> entry.isDraftable
//
// WHY DART, NOT A TABLE OR AN ASSET (decided 2026-08-02). The two facts
// that matter most here — does a capture surface exist, and is there an
// assessment_bridge reader behind it — are facts about THIS COMPILED
// BINARY, not about data. A row in Supabase (or a line in a bundled
// JSON) can assert that 'pediatric-dysarthria' is draftable while the
// deployed build has no PedDysarthriaAssessmentReader; the app would
// then offer a draft and throw UnsupportedError from
// AssessmentContextAssembler. Source of truth belongs where the facts
// live. (The sibling call went the other way for the same reason: the
// RLS allowlist describes DATABASE state, so it lives in the database.)
//
// HOW IT CANNOT LIE. Entries hold REAL REFERENCES, never booleans:
// `buildSurface` is a function that constructs the widget, so "a
// surface exists" is true by construction — delete the widget and this
// file stops compiling. `reader` is null or a binding holding the
// actual read + assessment-id resolver, so "draftable" is likewise
// structural.
//
// SCOPE — THIS BINARY ONLY (amendment, 2026-08-02). A protocol whose
// surface is not in this build is NOT listed. The childhood-feeding and
// SSD-differential surfaces live on their own branches and therefore
// have no entry here; when those branches merge, their entries land
// with them. A registry that lists what it cannot reference is back to
// being an assertion. What is coming later is a roadmap, not a source
// of truth.
//
// The absent third surface state is expressed by ABSENCE FROM THIS
// LIST, not by an enum value — an entry that exists always has a
// constructible surface, so an in-entry `absent` would be unreachable
// by construction. What remains in-entry is the distinction that DOES
// have members: a real instrument vs a placeholder (see
// ProtocolSurfaceStatus.stub, which today is the SSD note-capture
// screen).
//
// This file describes what exists. It deliberately moves NO clinical
// content: the instrument wording stays exactly where it is today
// (const lists inside each surface, or the ASHA asset for pediatric
// language). Extracting content is a separate, much larger decision.

import 'package:flutter/widgets.dart';

import '../models/assessment_envelope.dart';
import '../services/assessment_bridge/cas_assessment_reader.dart';
import '../services/assessment_bridge/ped_language_assessment_reader.dart';
import '../services/assessment_bridge/voice_assessment_reader.dart';
import '../services/cas_assessment_service.dart';
import '../services/ped_language_assessment_service.dart';
import '../services/voice_assessment_service.dart';
import '../widgets/assessment/ald_capture_section.dart';
import '../widgets/assessment/cas_assessment_surface.dart';
import '../widgets/assessment/ped_dysarthria_capture_section.dart';
import '../widgets/assessment/ped_language_capture_surface.dart';
import '../widgets/assessment/ssd_capture_section.dart';
import '../widgets/assessment/voice_capture_section.dart';

/// How finished the capture surface is. Absence of an entry is the
/// third state ("no surface in this binary") — see the file header.
enum ProtocolSurfaceStatus {
  /// A real instrument surface, built and wired.
  shipped,

  /// Constructible, but explicitly NOT the real instrument yet — it
  /// says so on screen. Listing it as `shipped` would tell a clinician
  /// an instrument exists when what exists is a placeholder.
  stub,
}

/// The reader half: present only when this binary can actually turn a
/// completed capture into the assembler's envelope. Null on an entry
/// means "captures, does not draft (yet)" — the honest state for four
/// of the six protocols today.
class AssessmentReaderBinding {
  /// The key AssessmentContextAssembler switches on. It is the
  /// clinical_area string — asserted equal to the entry's
  /// clinicalArea by the manifest test.
  final String protocol;

  /// Loads + transforms one assessment into the uniform envelope.
  final Future<AssessmentEnvelope> Function(String assessmentId) read;

  /// Resolves this client's assessment row id for the protocol. By
  /// report time the row exists (she filled the capture surface), so
  /// the underlying loadOrCreate loads rather than creates.
  final Future<String?> Function(String clientId) resolveAssessmentId;

  const AssessmentReaderBinding({
    required this.protocol,
    required this.read,
    required this.resolveAssessmentId,
  });
}

/// One protocol: what it is, which area it serves, the surface that
/// captures it, and (when it exists) the reader that reports it.
class ProtocolManifestEntry {
  /// Stable manifest key. NOT the clinical_area — one area may serve
  /// several protocols (speech-sound-disorders already does).
  final String code;

  /// SLP-facing name.
  final String displayName;

  /// The kClinicalAreas code this protocol serves.
  final String clinicalArea;

  final ProtocolSurfaceStatus surfaceStatus;

  /// Constructs the capture surface. Non-null by definition — an entry
  /// exists only if this binary can build its surface.
  final Widget Function(String clientId) buildSurface;

  /// Null when this binary has no reader for the protocol.
  final AssessmentReaderBinding? reader;

  const ProtocolManifestEntry({
    required this.code,
    required this.displayName,
    required this.clinicalArea,
    required this.surfaceStatus,
    required this.buildSurface,
    this.reader,
  });

  /// Whether a completed capture can become a drafted report.
  bool get isDraftable => reader != null;
}

// ── Surface builders (top-level tear-offs so the manifest stays const) ──

Widget _buildVoiceSurface(String clientId) =>
    VoiceCaptureSection(clientId: clientId);

Widget _buildSsdScreenSurface(String clientId) =>
    SsdCaptureSection(clientId: clientId);

Widget _buildAldSurface(String clientId) =>
    AldCaptureSection(clientId: clientId);

Widget _buildPedDysarthriaSurface(String clientId) =>
    PedDysarthriaCaptureSection(clientId: clientId);

Widget _buildCasSurface(String clientId) =>
    CasAssessmentSurface(clientId: clientId);

Widget _buildPedLanguageSurface(String clientId) =>
    PedLanguageCaptureSurface(clientId: clientId);

// ── Reader bindings ────────────────────────────────────────────────────

Future<AssessmentEnvelope> _readVoice(String assessmentId) =>
    VoiceAssessmentReader().readById(assessmentId);

Future<String?> _resolveVoiceAssessmentId(String clientId) async {
  final a = await VoiceAssessmentService.instance.loadOrCreate(
      clientId: clientId);
  return a.id;
}

Future<AssessmentEnvelope> _readCas(String assessmentId) =>
    CasAssessmentReader().readById(assessmentId);

Future<String?> _resolveCasAssessmentId(String clientId) async {
  final a = await CasAssessmentService.instance.loadOrCreate(
      clientId: clientId);
  return a['id'] as String?;
}

Future<AssessmentEnvelope> _readPedLanguage(String assessmentId) =>
    PedLanguageAssessmentReader().readById(assessmentId);

/// Returns null when the gate could not produce a record at all — no usable
/// age on the client, or an age outside the dataset's birth-5 coverage. Those
/// are real states, not failures to paper over: with no assessment row there
/// is nothing to draft from, and the caller's null check is where that gets
/// said honestly.
Future<String?> _resolvePedLanguageAssessmentId(String clientId) async {
  final b = await PedLanguageAssessmentService.instance
      .resolveParent(clientId: clientId);
  return b.assessment?['id'] as String?;
}

// ── The manifest ───────────────────────────────────────────────────────

const List<ProtocolManifestEntry> kProtocolManifest = [
  ProtocolManifestEntry(
    code: 'voice',
    displayName: 'Voice',
    clinicalArea: 'voice',
    surfaceStatus: ProtocolSurfaceStatus.shipped,
    buildSurface: _buildVoiceSurface,
    reader: AssessmentReaderBinding(
      protocol: 'voice',
      read: _readVoice,
      resolveAssessmentId: _resolveVoiceAssessmentId,
    ),
  ),
  ProtocolManifestEntry(
    code: 'ped-cas',
    displayName: 'Pediatric CAS',
    clinicalArea: 'pediatric-cas',
    surfaceStatus: ProtocolSurfaceStatus.shipped,
    buildSurface: _buildCasSurface,
    reader: AssessmentReaderBinding(
      protocol: 'pediatric-cas',
      read: _readCas,
      resolveAssessmentId: _resolveCasAssessmentId,
    ),
  ),
  ProtocolManifestEntry(
    code: 'ped-dysarthria',
    displayName: 'Pediatric Dysarthria',
    clinicalArea: 'pediatric-dysarthria',
    surfaceStatus: ProtocolSurfaceStatus.shipped,
    buildSurface: _buildPedDysarthriaSurface,
    // No reader in this binary — captures, does not draft.
  ),
  ProtocolManifestEntry(
    code: 'ald',
    displayName: 'Adult Language & Cognitive',
    clinicalArea: 'adult-language-cognitive',
    surfaceStatus: ProtocolSurfaceStatus.shipped,
    buildSurface: _buildAldSurface,
  ),
  ProtocolManifestEntry(
    code: 'ped-language',
    displayName: 'Pediatric Language — ASHA milestones',
    clinicalArea: 'pediatric-language',
    surfaceStatus: ProtocolSurfaceStatus.shipped,
    buildSurface: _buildPedLanguageSurface,
    reader: AssessmentReaderBinding(
      protocol: 'pediatric-language',
      read: _readPedLanguage,
      resolveAssessmentId: _resolvePedLanguageAssessmentId,
    ),
  ),
  ProtocolManifestEntry(
    code: 'ssd-screen',
    displayName: 'Speech Sound Disorders — screen',
    clinicalArea: 'speech-sound-disorders',
    // Five chips over a free-text note; the surface itself says
    // "instrument fields coming". Not a real instrument yet.
    surfaceStatus: ProtocolSurfaceStatus.stub,
    buildSurface: _buildSsdScreenSurface,
  ),
];

/// Clinical areas that KNOWINGLY have no protocol in this binary. This
/// is not a roadmap — it is an acknowledgement list, so that a newly
/// added clinical area cannot silently arrive with neither a protocol
/// nor a decision. The manifest test asserts covered + uncovered
/// exactly partitions kClinicalAreas.
const Set<String> kUncoveredClinicalAreas = {
  'autism-developmental',
  'pediatric-motor-speech',
  'fluency',
  'adult-motor-speech',
  'dysphagia',
  'aac',
  'social-pragmatic',
  'hearing-aural-rehab',
  'literacy',
  'multilingual',
};

/// Every protocol serving [clinicalArea], in manifest order. Empty when
/// the area has no protocol in this binary.
List<ProtocolManifestEntry> protocolsForArea(String? clinicalArea) {
  if (clinicalArea == null || clinicalArea.isEmpty) return const [];
  return [
    for (final p in kProtocolManifest)
      if (p.clinicalArea == clinicalArea) p,
  ];
}

/// The single protocol for [clinicalArea], or null when the area has
/// none — or more than one, which is a caller-must-choose situation
/// rather than something to resolve silently.
ProtocolManifestEntry? soleProtocolForArea(String? clinicalArea) {
  final all = protocolsForArea(clinicalArea);
  return all.length == 1 ? all.first : null;
}

/// Manifest entry by its stable [code].
ProtocolManifestEntry? protocolByCode(String code) {
  for (final p in kProtocolManifest) {
    if (p.code == code) return p;
  }
  return null;
}
