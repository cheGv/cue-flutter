// lib/constants/feeding_ladder_content.dart
//
// Childhood Feeding — Phase 1 (capture). Single source of truth for the
// feeding surface's reference CONTENT: the five oral-motor dissociation
// functions, the seven developmental feeding-ladder bands, the starter
// behaviour set, the Western-norm caveat, and the swallow off-ramp caution.
// FeedingAssessmentService seeds feeding_ladder_bands from kFeedingLadderBands
// (version-freezing the text into each assessment's rows — clinical
// provenance); FeedingAssessmentSurface renders from here.
//
// CONTENT PROVENANCE (brand-neutral — no commercial framework names):
// developmental-feeding literature — Arvedson (pediatric feeding/swallowing
// assessment), Delaney & Goday (development of oral feeding skills), the
// New York State Early Intervention clinical practice guideline, ASHA
// practice guidance, and the Goday et al. pediatric feeding disorder
// consensus. Milestone ages are approximate windows, not cutoffs.
//
// ── SIGN-OFF STATUS (clinician review completed 2026-06-11) ─────────────
//   SIGNED OFF:
//   * every redFlagPrompt below — content v2 (see CONTENT VERSIONS).
//     Observation prompts, never verdicts — that register is unchanged.
//   * the off-ramp trigger — now SIGN-TRIGGERED ONLY: an airway-sign
//     behaviour marked present, at ANY age. Age alone never fires it (an
//     age-based alarm cries wolf on typically developing toddlers and
//     trains the safety channel to be dismissed). Band guidance text in
//     the 18mo+ bands still directs observation toward airway signs.
//   * kFeedingStarterBehaviors — including the EIGHTH item
//     (airway_signs_textured), now LOAD-BEARING: it is the sole off-ramp
//     trigger (free-typed rows cannot be classified as airway signs).
//   STILL v1 DRAFT (refine in real clinician testing):
//   * kFeedingWesternNormCaveat wording
//   * kFeedingOffRampCaution wording (the trigger is signed off; the
//     caution's phrasing iterates with testing)
//
// ── CONTENT VERSIONS (rows are version-frozen at seed time: existing
//    assessments keep the text they were marked against; new assessments
//    seed the current version) ─────────────────────────────────────────────
//   v1 (2026-06-11, commit 87063a4) — initial draft.
//   v2 (2026-06-11, this version) — post-sign-off corrections:
//     band 1: "colour change" → perioral cyanosis (precise sign, urgent);
//     band 3: pincer trigger 10mo → "not emerging by 12mo" (pincer emerges
//             9–12mo, masters ~12mo, normal range to 15mo — 10mo fired
//             false alarms on typical children);
//     band 4: "excessive drooling" REMOVED (developmentally normal until
//             15–18mo, pathologic only past 4yr); EI cutoffs labelled;
//     bands 5–7: unchanged (rotary-chew flag confirmed by ASHA + jaw-motion
//             literature; refusal / selectivity / ARFID / airway triggers
//             clinically standard).

/// One oral-motor dissociation function: the DB column pair it captures to,
/// the clinical term (secondary label), and the plain-language observable
/// sign (primary text — observable-sign-first per the surface doctrine).
typedef FeedingDissociationFunction = ({
  String column, // status column on feeding_assessments; '<column>_notes' pairs it
  String term, // clinical term — the SECONDARY label
  String observableSign, // plain language — the PRIMARY text
});

const List<FeedingDissociationFunction> kFeedingDissociationFunctions = [
  (
    column: 'jaw_stability',
    term: 'Jaw stability / grading',
    observableSign: 'Does the jaw stay steady and graded — opening just '
        'enough — or slide, clench, or over-open?',
  ),
  (
    column: 'jaw_lip_dissociation',
    term: 'Jaw–lip dissociation',
    observableSign: 'Can the lips move independently of the jaw — jaw still '
        'while lips work, or lips move only when jaw does?',
  ),
  (
    column: 'jaw_tongue_dissociation',
    term: 'Jaw–tongue dissociation',
    observableSign: 'Does the tongue move on its own while the jaw stays '
        'steady, or does the jaw drag along with every tongue movement?',
  ),
  (
    column: 'lip_control',
    term: 'Lip control',
    observableSign: 'Lip seal on spoon and cup, rounding and retraction — '
        'food stays in, or spills from the corners?',
  ),
  (
    column: 'tongue_control',
    term: 'Tongue control',
    observableSign: 'Does the tongue move food side to side and up, cupping '
        'the bolus — or stay flat, front-to-back only?',
  ),
];

/// One developmental feeding-ladder band. ageMaxMonths == null means
/// open-ended (the 30–36+ band). offRampBand marks the 18mo+ bands whose
/// red-flag guidance includes overt airway signs — it drives the in-band
/// beyond-scope marker ONLY. The off-ramp CARD itself is SIGN-TRIGGERED
/// (an airway-sign behaviour marked present, any age), never band- or
/// age-triggered (sign-off 2026-06-11).
typedef FeedingLadderBand = ({
  String key,
  int order,
  String label,
  int ageMinMonths,
  int? ageMaxMonths,
  String expectedTexture,
  String expectedSelfFeeding,
  String expectedOralMotor,
  String redFlagPrompt, // OBSERVATION PROMPT — DRAFT, sign-off pending
  bool offRampBand,
});

/// The seven bands, in developmental order. A child's age matches band b when
/// ageMinMonths <= age AND (ageMaxMonths == null OR age < ageMaxMonths).
const List<FeedingLadderBand> kFeedingLadderBands = [
  (
    key: '0_6mo',
    order: 1,
    label: '0–6 months',
    ageMinMonths: 0,
    ageMaxMonths: 6,
    expectedTexture:
        'Liquids (breast / bottle); smooth purées introduced around 4–6 months.',
    expectedSelfFeeding:
        'None yet — hands begin coming to the mouth around 4 months.',
    expectedOralMotor:
        'Suckle transitioning to suck; tongue moves front-to-back '
        '(antero-posterior) only.',
    redFlagPrompt:
        'Suckle reflex not practised or fading before ~4 months; poor latch, '
        'fatigue, or perioral cyanosis (blueness around lips/mouth) during '
        'feeds — the last is urgent, escalate.',
    offRampBand: false,
  ),
  (
    key: '6_9mo',
    order: 2,
    label: '6–9 months',
    ageMinMonths: 6,
    ageMaxMonths: 9,
    expectedTexture:
        'Purées → soft mashables → meltable solids; single textures, not mixed.',
    expectedSelfFeeding: 'Finger feeding begins around 6–7 months.',
    expectedOralMotor:
        'Vertical (up–down) munching; tongue lateralization — moving food '
        'toward the sides — begins around 7–9 months.',
    redFlagPrompt:
        'Absent tongue lateralization in the 7–9 month window — a key early '
        'flag. Excessive gag or vomit on non-liquids; total spoon refusal.',
    offRampBand: false,
  ),
  (
    key: '9_12mo',
    order: 3,
    label: '9–12 months',
    ageMinMonths: 9,
    ageMaxMonths: 12,
    expectedTexture: 'Lumpy purées → ground / soft chewable foods.',
    expectedSelfFeeding:
        'Pincer grasp refines; spoon held whole-hand.',
    expectedOralMotor:
        'Rotary chew begins around 10 months; gag reflex moves posterior.',
    redFlagPrompt:
        'Persistent purée dependence past ~9 months with no progression to '
        'lumps/solids. Pincer grasp not emerging by 12 months. Gagging not '
        'diminished by ~10 months.',
    offRampBand: false,
  ),
  (
    key: '12_18mo',
    order: 4,
    label: '12–18 months',
    ageMinMonths: 12,
    ageMaxMonths: 18,
    expectedTexture: 'All textures; mixed textures appropriate.',
    expectedSelfFeeding:
        'Efficient finger-feeding; utensil practice; open-cup drinking emerging.',
    expectedOralMotor: 'Lateral tongue action; diagonal chew.',
    redFlagPrompt:
        'Not self-feeding finger foods by 14 months; not attempting spoon by '
        '15 months; not open-cup drinking by 15 months (Early Intervention '
        'cutoffs). Failure to advance through textures.',
    offRampBand: false,
  ),
  (
    key: '18_24mo',
    order: 5,
    label: '18–24 months',
    ageMinMonths: 18,
    ageMaxMonths: 24,
    expectedTexture: 'More chewable / firmer foods; most family textures.',
    expectedSelfFeeding:
        'Increasing utensil independence; bites with front teeth, chews with '
        'molars.',
    expectedOralMotor: 'Rotary chewing maturing; graded jaw strength.',
    redFlagPrompt:
        'No rotary chew — cannot break down solids; compensatory wide jaw '
        'excursions, tongue protrusion, spoon-biting. Coughing or choking on '
        'texture — beyond feeding-skills scope (see the swallow off-ramp).',
    offRampBand: true,
  ),
  (
    key: '24_30mo',
    order: 6,
    label: '24–30 months',
    ageMinMonths: 24,
    ageMaxMonths: 30,
    expectedTexture:
        'Full family range; firm / fibrous foods sized appropriately.',
    expectedSelfFeeding: 'Efficient utensil use developing.',
    expectedOralMotor:
        'Circular rotary chew in all directions; full tongue–lip–jaw '
        'dissociation.',
    redFlagPrompt:
        'Extreme or persistent refusal beyond a normal picky phase; whole '
        'food groups missing; growth faltering. Incomplete oral-motor '
        'dissociation.',
    offRampBand: true,
  ),
  (
    key: '30_36mo_plus',
    order: 7,
    label: '30–36+ months',
    ageMinMonths: 30,
    ageMaxMonths: null,
    expectedTexture:
        'Adult-range textures; choking hazards still sized / prepared safely.',
    expectedSelfFeeding:
        'Effective utensil use; knife practice around 3 years.',
    expectedOralMotor: 'Mature mastication; dissociation consolidated.',
    redFlagPrompt:
        'Persistent choking or coughing on age-appropriate textures — swallow '
        'assessment indicated. Severe selectivity / ARFID-pattern restriction; '
        'escalating mealtime refusal.',
    offRampBand: true,
  ),
];

/// Resolve the band a given age in months falls into, or null when age is
/// null / negative. Pure — the surface highlights (never judges) the match.
FeedingLadderBand? feedingBandForAge(int? ageMonths) {
  if (ageMonths == null || ageMonths < 0) return null;
  for (final b in kFeedingLadderBands) {
    final max = b.ageMaxMonths;
    if (ageMonths >= b.ageMinMonths && (max == null || ageMonths < max)) {
      return b;
    }
  }
  return null;
}

/// One starter behaviour the clinician can add with a tap (she can also
/// free-type her own — those rows carry behavior_key NULL). chipLabel is the
/// short quick-add chip text; label is the full row text that persists.
/// airwaySign rows are overt airway signs: marking one PRESENT triggers the
/// swallow off-ramp.
typedef FeedingStarterBehavior = ({
  String key,
  String chipLabel,
  String label,
  bool airwaySign,
});

const List<FeedingStarterBehavior> kFeedingStarterBehaviors = [
  (
    key: 'pocketing',
    chipLabel: 'Pocketing',
    label: 'Pocketing — holding food in the cheeks without swallowing',
    airwaySign: false,
  ),
  (
    key: 'texture_avoidance',
    chipLabel: 'Texture avoidance',
    label: 'Texture avoidance — won\'t progress from soft to harder textures',
    airwaySign: false,
  ),
  (
    key: 'spitting_expelling',
    chipLabel: 'Spitting / expelling',
    label: 'Spitting / expelling food',
    airwaySign: false,
  ),
  (
    key: 'excessive_mealtime_length',
    chipLabel: 'Mealtime length / grazing',
    label: 'Excessive mealtime length / grazing',
    airwaySign: false,
  ),
  (
    key: 'food_selectivity',
    chipLabel: 'Food selectivity',
    label: 'Food selectivity / narrowing repertoire',
    airwaySign: false,
  ),
  (
    key: 'mealtime_distress',
    chipLabel: 'Mealtime distress',
    label: 'Mealtime distress / refusal behaviours',
    airwaySign: false,
  ),
  (
    key: 'gagging_vomiting',
    chipLabel: 'Gagging / vomiting',
    label: 'Gagging / vomiting on food presentation',
    airwaySign: false,
  ),
  // The one overt airway-sign item — SIGNED OFF 2026-06-11 and now
  // LOAD-BEARING: marking it present is the SOLE off-ramp trigger
  // (free-typed rows can't be classified as airway signs).
  // Gagging/vomiting above is deliberately NOT an airway sign (gag is a
  // protective reflex, not an airway-compromise signal).
  (
    key: 'airway_signs_textured',
    chipLabel: 'Coughing / choking / wet voice',
    label: 'Coughing, choking, or wet-sounding voice with textured food',
    airwaySign: true,
  ),
];

/// Western-norm caveat — renders with EVERY ladder band the clinician reads.
/// v1 wording — to be refined in real clinician testing (founder call,
/// 2026-06-11).
const String kFeedingWesternNormCaveat =
    'Milestones derive from predominantly Western cohorts and diets. Indian '
    'weaning practices, staple textures (rice / dal / roti), and hand-feeding '
    'norms may differ — treat this ladder as a reference frame, not a fixed '
    'standard. Clinician and cultural context govern.';

/// Swallow off-ramp caution — the safety boundary of this surface. Renders
/// ONLY when an airway-sign behaviour is marked present, at any age
/// (SIGN-TRIGGERED — sign-off 2026-06-11; age alone never fires it).
/// Wording is v1 — to be refined in real clinician testing.
const String kFeedingOffRampCaution =
    'Beyond feeding-skills scope — if coughing, choking, or a wet-sounding '
    'voice accompanies textured food, that is an airway sign warranting a '
    'swallow / instrumental assessment, not feeding-skills capture.';
