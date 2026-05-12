// lib/models/timeline_entry.dart
//
// Phase 5.3 B.3 — extracted from client_profile_screen.dart so the
// timeline data model can be consumed by FullTimelineView (in
// timeline_route.dart) and by the TimelineStrip mount on Profile, not
// just by the screen that originally defined it.
//
// Constructed types (per _makeReadyFuture in client_profile_screen.dart):
//   • session       — one entry per row in `sessions`
//   • goalSet       — one entry per LTG with non-null `created_at`
//   • goalAchieved  — one entry per LTG with non-null `achieved_at`
//
// Future-proofing slots (defined but never instantiated as of B.3):
//   • assessment, upload, milestone

enum TimelineEntryType {
  session,
  goalSet,
  goalAchieved,
  assessment,
  upload,
  milestone,
}

class TimelineEntry {
  final DateTime date;
  final TimelineEntryType type;
  final String title;
  final String? subtitle;
  final String? referenceId;
  final Map<String, dynamic>? rawData;

  const TimelineEntry({
    required this.date,
    required this.type,
    required this.title,
    this.subtitle,
    this.referenceId,
    this.rawData,
  });
}
