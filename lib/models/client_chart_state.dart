import 'package:flutter/foundation.dart';

// ClientChartState — immutable mirror of the `client_chart_state` SQL view.
//
// Derived per-client state the chart reads to drive contextual logic (the
// action-chip resolver, the narrator state-voice line). Read-only.
//
// Renamed from the spec name `chart_context` to avoid collision with
// lib/utils/chart_context.dart (an AI-prompt context builder).
//
// Field notes (forced by the real schema):
//   dateOfBirth          <- clients.date_of_birth (often null; prefer `age`)
//   lastSessionDate      <- max(COALESCE(sessions.date, created_at::date))
//   lastNextSessionFocus <- sessions.next_session_focus (the plan-forward seed;
//                           there is no separate next_session_intent column)
//   caregiverPresent     <- derived (caregiver_email or guardian_whatsapp set)
@immutable
class ClientChartState {
  final String clientId;
  final String clientName;
  final int age;
  final DateTime? dateOfBirth;
  final String? diagnosis;

  final int ltgCount;
  final int activeStgCount;
  final int totalSessionCount;
  final DateTime? lastSessionDate;
  final int undocumentedSessionCount;
  final String? lastNextSessionFocus;

  final bool caregiverPresent;
  final int substrateCellCount;

  const ClientChartState({
    required this.clientId,
    required this.clientName,
    this.age = 0,
    this.dateOfBirth,
    this.diagnosis,
    this.ltgCount = 0,
    this.activeStgCount = 0,
    this.totalSessionCount = 0,
    this.lastSessionDate,
    this.undocumentedSessionCount = 0,
    this.lastNextSessionFocus,
    this.caregiverPresent = false,
    this.substrateCellCount = 0,
  });

  factory ClientChartState.fromJson(Map<String, dynamic> json) =>
      ClientChartState(
        clientId: json['client_id'] as String,
        clientName: json['client_name'] as String? ?? '',
        age: (json['age'] as num?)?.toInt() ?? 0,
        dateOfBirth: _parseDate(json['date_of_birth']),
        diagnosis: json['diagnosis'] as String?,
        ltgCount: (json['ltg_count'] as num?)?.toInt() ?? 0,
        activeStgCount: (json['active_stg_count'] as num?)?.toInt() ?? 0,
        totalSessionCount: (json['total_session_count'] as num?)?.toInt() ?? 0,
        lastSessionDate: _parseDate(json['last_session_date']),
        undocumentedSessionCount:
            (json['undocumented_session_count'] as num?)?.toInt() ?? 0,
        lastNextSessionFocus: json['last_next_session_focus'] as String?,
        caregiverPresent: json['caregiver_present'] as bool? ?? false,
        substrateCellCount:
            (json['substrate_cell_count'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'client_id': clientId,
        'client_name': clientName,
        'age': age,
        if (dateOfBirth != null)
          'date_of_birth': dateOfBirth!.toIso8601String(),
        if (diagnosis != null) 'diagnosis': diagnosis,
        'ltg_count': ltgCount,
        'active_stg_count': activeStgCount,
        'total_session_count': totalSessionCount,
        if (lastSessionDate != null)
          'last_session_date': lastSessionDate!.toIso8601String(),
        'undocumented_session_count': undocumentedSessionCount,
        if (lastNextSessionFocus != null)
          'last_next_session_focus': lastNextSessionFocus,
        'caregiver_present': caregiverPresent,
        'substrate_cell_count': substrateCellCount,
      };

  static DateTime? _parseDate(dynamic v) =>
      v is String ? DateTime.tryParse(v) : null;
}
