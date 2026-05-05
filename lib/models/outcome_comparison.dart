// lib/models/outcome_comparison.dart
//
// Phase 4.0.7.25a — shared baseline-vs-latest comparison primitives
// used by every assessment surface's Section 11 (Outcome Tracking).
// Originally lived inside voice_assessment.dart (4.0.7.24a); extracted
// here so ald_assessment.dart can reuse without duplicating.
//
// Direction conventions:
//   'lower'   → smaller is better (jitter, shimmer, CAPE-V, VHI handicap)
//   'higher'  → larger is better  (MPT, V-RQOL, WAB AQ, MoCA, BNT)
//   'neutral' → no directional clinical signal (renders gray Δ).

class OutcomeRow {
  final String  label;
  final num?    baseline;
  final num?    latest;
  final String  unit;
  final String  direction; // 'lower' | 'higher' | 'neutral'

  const OutcomeRow({
    required this.label,
    this.baseline,
    this.latest,
    this.unit = '',
    this.direction = 'neutral',
  });

  num? get delta {
    if (baseline == null || latest == null) return null;
    return latest! - baseline!;
  }

  /// Returns 'improved' / 'regressed' / 'unchanged' / 'partial'.
  /// 'partial' means only one of baseline / latest has data.
  String get verdict {
    if (baseline == null && latest == null) return 'partial';
    if (baseline == null || latest == null) return 'partial';
    final d = delta!;
    if (d == 0) return 'unchanged';
    if (direction == 'lower')  return d < 0 ? 'improved' : 'regressed';
    if (direction == 'higher') return d > 0 ? 'improved' : 'regressed';
    return 'unchanged';
  }
}

class OutcomeGroup {
  final String label;
  final List<OutcomeRow> rows;
  const OutcomeGroup({required this.label, required this.rows});
}

class OutcomeComparison {
  final String? baselineId;
  final String? latestId;
  final List<OutcomeGroup> groups;

  const OutcomeComparison({
    this.baselineId,
    this.latestId,
    required this.groups,
  });

  bool get hasFollowUp =>
      baselineId != null && latestId != null && baselineId != latestId;
}
