import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// Evidence tier — mirrors the Postgres `evidence_tier` enum.
//   level_1  — RCT / meta-analysis
//   level_2  — cohort study
//   level_3  — case series
//   practice — practice guidelines or framework documentation
// ---------------------------------------------------------------------------
enum EvidenceTier {
  level1,
  level2,
  level3,
  practice;

  /// Parse the DB string. Unknown / null returns null.
  static EvidenceTier? fromString(String? s) => switch (s) {
        'level_1' => EvidenceTier.level1,
        'level_2' => EvidenceTier.level2,
        'level_3' => EvidenceTier.level3,
        'practice' => EvidenceTier.practice,
        _ => null,
      };

  String toDbValue() => switch (this) {
        EvidenceTier.level1 => 'level_1',
        EvidenceTier.level2 => 'level_2',
        EvidenceTier.level3 => 'level_3',
        EvidenceTier.practice => 'practice',
      };

  String displayLabel() => switch (this) {
        EvidenceTier.level1 => 'Level I',
        EvidenceTier.level2 => 'Level II',
        EvidenceTier.level3 => 'Level III',
        EvidenceTier.practice => 'Practice',
      };
}

// ---------------------------------------------------------------------------
// Citation — immutable model for the `citations` table. Academic / clinical
// evidence attached to an STG; renders as the evidence ladder beneath the
// in-focus STG. Distinct from stg_evidence (per-session clinical trial data).
// ---------------------------------------------------------------------------
@immutable
class Citation {
  final String id;
  final String stgId;
  final EvidenceTier tier;
  final String finding;
  final String authorYear;
  final String? sourceUrl;
  final int displayOrder;

  const Citation({
    required this.id,
    required this.stgId,
    required this.tier,
    required this.finding,
    required this.authorYear,
    this.sourceUrl,
    this.displayOrder = 0,
  });

  factory Citation.fromJson(Map<String, dynamic> json) => Citation(
        id: json['id'] as String,
        stgId: json['stg_id'] as String,
        // tier is NOT NULL + enum-constrained in the DB; default to the
        // weakest tier if an unexpected value ever arrives.
        tier: EvidenceTier.fromString(json['tier'] as String?) ??
            EvidenceTier.practice,
        finding: json['finding'] as String,
        authorYear: json['author_year'] as String,
        sourceUrl: json['source_url'] as String?,
        displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'stg_id': stgId,
        'tier': tier.toDbValue(),
        'finding': finding,
        'author_year': authorYear,
        if (sourceUrl != null) 'source_url': sourceUrl,
        'display_order': displayOrder,
      };
}
