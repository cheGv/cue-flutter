// Phase C — format_type vocabulary shared by the format-adaptation screens.
// Mirrors the format_templates.format_type CHECK constraint.

const List<String> kFormatTypeKeys = [
  'pt_report',
  'lp_report',
  'progress_report',
  'session_note',
  'discharge_summary',
  'other',
];

const Map<String, String> kFormatTypeLabels = {
  'pt_report': 'Pre-therapy report',
  'lp_report': 'Lesson plan',
  'progress_report': 'Progress report',
  'session_note': 'Session note',
  'discharge_summary': 'Discharge summary',
  'other': 'Other',
};

String formatTypeLabel(String key) => kFormatTypeLabels[key] ?? 'Other';
