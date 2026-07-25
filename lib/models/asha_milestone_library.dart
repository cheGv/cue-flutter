// lib/models/asha_milestone_library.dart
//
// Pediatric Language capture surface (Step 2) — typed loader for the
// ASHA communication-milestones dataset shipped as an asset at
// assets/data/asha_language_milestones_0_5.json.
//
// Provenance discipline: milestone wording is verbatim ASHA (see the
// dataset's `source` field); the example sentences are Cue-authored
// Indian-English familiarity aids. This library is a structured
// developmental reference that informs clinical judgment — it is not a
// norm table and never produces a score or verdict.
//
// Parsing fails LOUDLY (FormatException) on any structural surprise —
// unknown or missing band ids, a missing section, an empty milestone —
// rather than rendering a silently incomplete capture surface. The
// asset is version-controlled with the app, so a parse failure is a
// build defect, never a runtime condition to soften.
//
// Band matching is age-in-months, inclusive on both edges, driven by
// the const registry below. Ages beyond 60 months return null — the
// dataset covers birth-5 and the surface shows an honest out-of-range
// state instead of stretching the oldest band.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Canonical section keys, in capture order.
const List<String> kAshaSections = ['speech', 'language', 'literacy'];

/// The one shipping dataset asset.
const String kAshaMilestoneAssetPath =
    'assets/data/asha_language_milestones_0_5.json';

/// band_id → inclusive age range in months. The parser requires the
/// dataset's band ids to match these keys exactly (no more, no fewer),
/// so the boundary knowledge lives in exactly one place.
const Map<String, ({int minMonths, int maxMonths})> kAshaBandRanges = {
  'birth_to_1y': (minMonths: 0, maxMonths: 12),
  '13_to_18m':   (minMonths: 13, maxMonths: 18),
  '19_to_24m':   (minMonths: 19, maxMonths: 24),
  '2_to_3y':     (minMonths: 25, maxMonths: 36),
  '3_to_4y':     (minMonths: 37, maxMonths: 48),
  '4_to_5y':     (minMonths: 49, maxMonths: 60),
};

class AshaMilestone {
  /// Verbatim ASHA milestone wording.
  final String milestone;

  /// Cue-authored Indian-English example sentence.
  final String example;

  /// 1-based position within its section — the persistence key half
  /// (with section) for a milestone row, so it must stay stable for a
  /// given dataset version.
  final int order;

  const AshaMilestone({
    required this.milestone,
    required this.example,
    required this.order,
  });
}

class AshaAgeBand {
  final String bandId;
  final String label;

  /// Optional dataset note (e.g. the pre-verbal framing on birth_to_1y).
  final String? note;

  final int minMonths; // inclusive
  final int maxMonths; // inclusive

  /// section key → milestones in file order. Keys are exactly
  /// [kAshaSections].
  final Map<String, List<AshaMilestone>> sections;

  const AshaAgeBand({
    required this.bandId,
    required this.label,
    required this.note,
    required this.minMonths,
    required this.maxMonths,
    required this.sections,
  });

  bool containsAgeMonths(int months) =>
      months >= minMonths && months <= maxMonths;

  int get milestoneCount =>
      sections.values.fold(0, (sum, list) => sum + list.length);
}

class AshaMilestoneLibrary {
  /// Bands in dataset order (youngest first).
  final List<AshaAgeBand> bands;

  /// The dataset's own provenance sentence, surfaced verbatim in the UI.
  final String source;

  /// Dataset version (strict major.minor.patch), stamped onto every
  /// seeded milestone row as library_version so a persisted capture
  /// records exactly which parse of the reference set it came from.
  final String version;

  const AshaMilestoneLibrary(
      {required this.bands, required this.source, required this.version});

  // Never invalidated by design: the asset is immutable at runtime and
  // assignment happens only after a successful parse. Dev note: this
  // static survives hot reload — after editing the dataset JSON, hot
  // RESTART to see the change.
  static AshaMilestoneLibrary? _cached;

  /// Loads and caches the shipped asset. Throws [FormatException] on a
  /// malformed dataset — a build defect, not a runtime condition.
  static Future<AshaMilestoneLibrary> load() async {
    if (_cached != null) return _cached!;
    final raw = await rootBundle.loadString(kAshaMilestoneAssetPath);
    _cached = AshaMilestoneLibrary.fromJsonString(raw);
    return _cached!;
  }

  factory AshaMilestoneLibrary.fromJsonString(String raw) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } on Object catch (e) {
      throw FormatException('ASHA milestone dataset is not valid JSON: $e');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
          'ASHA milestone dataset root must be a JSON object');
    }
    return AshaMilestoneLibrary.fromJson(decoded);
  }

  factory AshaMilestoneLibrary.fromJson(Map<String, dynamic> json) {
    final source = json['source'];
    if (source is! String || source.trim().isEmpty) {
      throw const FormatException(
          'ASHA milestone dataset missing its `source` provenance field');
    }

    // Version is provenance, not decoration: missing or malformed is a
    // hard failure — never defaulted, so an unversioned dataset can
    // never stamp rows.
    final version = json['version'];
    if (version is! String ||
        !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
      throw const FormatException(
          'ASHA milestone dataset `version` missing or malformed '
          '(expected major.minor.patch)');
    }

    final rawBands = json['age_bands'];
    if (rawBands is! List) {
      throw const FormatException(
          'ASHA milestone dataset missing `age_bands` list');
    }

    final bands = <AshaAgeBand>[];
    for (final rawBand in rawBands) {
      if (rawBand is! Map<String, dynamic>) {
        throw const FormatException('age_bands entry is not an object');
      }
      bands.add(_parseBand(rawBand));
    }

    // Exact-match the registry: every known band present exactly once,
    // no unknown bands (the unknown case already threw in _parseBand).
    final seen = bands.map((b) => b.bandId).toList();
    for (final expected in kAshaBandRanges.keys) {
      final count = seen.where((id) => id == expected).length;
      if (count != 1) {
        throw FormatException(
            'ASHA milestone dataset: band `$expected` appears $count times '
            '(expected exactly 1)');
      }
    }

    return AshaMilestoneLibrary(
        bands: List.unmodifiable(bands), source: source, version: version);
  }

  static AshaAgeBand _parseBand(Map<String, dynamic> json) {
    final bandId = json['band_id'];
    if (bandId is! String) {
      throw const FormatException('age_bands entry missing `band_id`');
    }
    final range = kAshaBandRanges[bandId];
    if (range == null) {
      throw FormatException(
          'ASHA milestone dataset: unknown band_id `$bandId`');
    }
    final label = json['label'];
    if (label is! String || label.trim().isEmpty) {
      throw FormatException('band `$bandId` missing `label`');
    }

    final sections = <String, List<AshaMilestone>>{};
    for (final section in kAshaSections) {
      final rawList = json[section];
      if (rawList is! List || rawList.isEmpty) {
        throw FormatException(
            'band `$bandId` section `$section` is missing or empty');
      }
      final milestones = <AshaMilestone>[];
      for (var i = 0; i < rawList.length; i++) {
        final raw = rawList[i];
        if (raw is! Map<String, dynamic>) {
          throw FormatException(
              'band `$bandId` section `$section` entry ${i + 1} is not an '
              'object');
        }
        final milestone = raw['milestone'];
        final example = raw['example'];
        if (milestone is! String || milestone.trim().isEmpty) {
          throw FormatException(
              'band `$bandId` section `$section` entry ${i + 1} missing '
              '`milestone` text');
        }
        if (example is! String || example.trim().isEmpty) {
          throw FormatException(
              'band `$bandId` section `$section` entry ${i + 1} missing '
              '`example` text');
        }
        milestones.add(AshaMilestone(
          milestone: milestone,
          example: example,
          order: i + 1,
        ));
      }
      sections[section] = List.unmodifiable(milestones);
    }

    return AshaAgeBand(
      bandId: bandId,
      label: label,
      note: json['note'] is String ? json['note'] as String : null,
      minMonths: range.minMonths,
      maxMonths: range.maxMonths,
      sections: Map.unmodifiable(sections),
    );
  }

  /// The band whose inclusive month range contains [months], or null
  /// when the age falls outside birth-5 (months < 0 or > 60).
  AshaAgeBand? bandForAgeMonths(int months) {
    for (final band in bands) {
      if (band.containsAgeMonths(months)) return band;
    }
    return null;
  }

  AshaAgeBand? bandById(String bandId) {
    for (final band in bands) {
      if (band.bandId == bandId) return band;
    }
    return null;
  }
}
