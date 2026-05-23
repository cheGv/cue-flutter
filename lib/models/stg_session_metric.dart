import 'package:flutter/foundation.dart';

// StgSessionMetric — immutable model for the `stg_session_metrics` table.
//
// One numeric value per (STG, session). Drives the sparkline inside the
// in-focus STG card. metric_label/unit carry the semantics so the sparkline
// can render and label non-accuracy metrics (prompting level, support level,
// frequency counts) that session_goal_data / stg_evidence don't store cleanly.
//
// Column types:
//   session_id  bigint -> int (sessions.id is a bigint identity column)
//   stg_id      uuid   -> String
@immutable
class StgSessionMetric {
  final String id;
  final String stgId;
  final int sessionId;
  final double metricValue;
  final String metricLabel;
  final String? metricUnit;
  final DateTime recordedAt;

  const StgSessionMetric({
    required this.id,
    required this.stgId,
    required this.sessionId,
    required this.metricValue,
    required this.metricLabel,
    this.metricUnit,
    required this.recordedAt,
  });

  factory StgSessionMetric.fromJson(Map<String, dynamic> json) =>
      StgSessionMetric(
        id: json['id'] as String,
        stgId: json['stg_id'] as String,
        sessionId: (json['session_id'] as num).toInt(),
        metricValue: (json['metric_value'] as num).toDouble(),
        metricLabel: json['metric_label'] as String,
        metricUnit: json['metric_unit'] as String?,
        recordedAt: DateTime.parse(json['recorded_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'stg_id': stgId,
        'session_id': sessionId,
        'metric_value': metricValue,
        'metric_label': metricLabel,
        if (metricUnit != null) 'metric_unit': metricUnit,
        'recorded_at': recordedAt.toIso8601String(),
      };
}
