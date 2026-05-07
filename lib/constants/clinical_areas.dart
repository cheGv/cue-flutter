// lib/constants/clinical_areas.dart
//
// Phase 4.0.7.23 — single source of truth for the 16 SLP clinical
// areas that match the framework library taxonomy and the
// clients.clinical_area schema CHECK constraint. Originally 14;
// pediatric-cas, pediatric-dysarthria, and pediatric-motor-speech
// were promoted in Phase 4.0.7.27c-prep (count corrected here in
// Phase 4.0.7.28-session-capture-v1).
//
// Imported by:
//   - lib/screens/goal_authoring_screen.dart  (4.0.7.23)
//   - lib/screens/add_client_screen.dart      (4.0.7.23-completion)
//   - lib/screens/ltg_edit_screen.dart        (transitively, via the
//                                              CueReasoningPanel
//                                              prefill from
//                                              widget.goal['clinical_area'])
//
// Order is intentional: pediatric general → autism → speech-sound →
// motor speech → fluency → voice → adult split → dysphagia → AAC →
// social → hearing → literacy → multilingual.

const List<({String code, String label})> kClinicalAreas = [
  (code: 'pediatric-language',       label: 'Pediatric Language'),
  (code: 'autism-developmental',     label: 'Autism + Developmental'),
  (code: 'speech-sound-disorders',   label: 'Speech Sound Disorders'),
  // Phase 4.0.7.27c-prep — CAS and Dysarthria promoted to primary
  // selections. Umbrella demoted to differential-pending fallback;
  // surfaced in the picker with distinct visual treatment (italic,
  // muted) to signal it is not a first-choice option.
  (code: 'pediatric-cas',            label: 'Pediatric CAS (Childhood Apraxia of Speech)'),
  (code: 'pediatric-dysarthria',     label: 'Pediatric Dysarthria'),
  (code: 'pediatric-motor-speech',   label: 'Pediatric Motor Speech — differential pending'),
  (code: 'fluency',                  label: 'Fluency'),
  (code: 'voice',                    label: 'Voice'),
  (code: 'adult-language-cognitive', label: 'Adult Language & Cognitive'),
  (code: 'adult-motor-speech',       label: 'Adult Motor Speech'),
  (code: 'dysphagia',                label: 'Dysphagia'),
  (code: 'aac',                      label: 'AAC'),
  (code: 'social-pragmatic',         label: 'Social Communication'),
  (code: 'hearing-aural-rehab',      label: 'Hearing & Aural Rehab'),
  (code: 'literacy',                 label: 'Literacy'),
  (code: 'multilingual',             label: 'Multilingual'),
];

/// Resolves a clinical_area short_code to its SLP-facing display
/// label, or returns the code as-is if no match (defensive against
/// future schema drift).
String clinicalAreaLabel(String? code) {
  if (code == null || code.isEmpty) return '';
  for (final a in kClinicalAreas) {
    if (a.code == code) return a.label;
  }
  return code;
}

/// Phase 4.0.7.23-completion — derive the legacy population_type
/// value from a clinical_area pick. Used by the intake form so newly
/// created clients land with both columns populated; the fluency
/// session screens still route on population_type until 4.0.7.23b
/// migrates them off entirely.
///
/// Mapping (per spec):
///   autism-developmental, aac → 'asd_aac'
///   fluency                   → 'developmental_stuttering'
///   everything else           → null (legacy column allows null)
String? legacyPopulationTypeFor(String clinicalArea) {
  switch (clinicalArea) {
    case 'autism-developmental':
    case 'aac':
      return 'asd_aac';
    case 'fluency':
      return 'developmental_stuttering';
    default:
      return null;
  }
}
