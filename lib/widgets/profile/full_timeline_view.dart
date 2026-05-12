// lib/widgets/profile/full_timeline_view.dart
//
// Phase 5.3 B.3 — full vertical timeline view, extracted from
// client_profile_screen.dart's _buildTimeline + 4 helpers.
//
// Used by lib/screens/timeline_route.dart as the route's body when the
// SLP follows the "See all N events →" link from TimelineStrip on
// Profile. Profile no longer mounts FullTimelineView directly —
// TimelineStrip is the compressed-on-Profile pattern.
//
// Three transformations from the original State methods:
//   • _refreshSpine() → onRefresh() callback (passed via constructor
//     so the host widget owns the refresh logic — Profile would wire
//     its _refreshSpine; timeline_route passes a no-op per Phase 4A
//     Decision 3 staleness limitation).
//   • mounted → context.mounted (no State subclass; Flutter 3.7+
//     BuildContext.mounted getter handles the post-async-gap check).
//   • clientId / clientName params → this.clientId / this.clientName
//     (constructor-supplied, no longer threaded through every method).
//
// Hairline cleanup applied along the way: literal `0.5` border widths
// replaced with `CueSize.hairline` to match the design-system discipline
// established in Fix 2's brief_thought_view cleanup.
//
// _buildTimelineLoading is NOT extracted (Phase 4A Decision 2). The
// mono uppercase TIMELINE eyebrow is calcified typography flagged for
// Phase 5.4 redesign; carrying its loading variant into a new file
// would deepen that calcification. timeline_route's data arrives via
// Navigator args (Option 1), so no loading state is needed there.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/timeline_entry.dart';
import '../../screens/report_screen.dart';
import '../../services/session_archive_service.dart';
import '../../theme/cue_color_scheme.dart';
import '../../theme/cue_tokens.dart';

class FullTimelineView extends StatelessWidget {
  /// Sorted-newest-first list of timeline entries to render.
  final List<TimelineEntry> entries;

  /// Threaded through to ReportScreen on session-card tap.
  final String clientId;

  /// Threaded through to ReportScreen.
  final String clientName;

  /// Fires after a state-mutating action (session archive, ReportScreen
  /// pop with edits). Profile would wire its _refreshSpine; timeline_
  /// route passes a no-op per Phase 4A Decision 3 staleness limitation.
  final VoidCallback onRefresh;

  /// Outer padding around the timeline column. Defaults to
  /// EdgeInsets.fromLTRB(24, 48, 24, 0) matching Profile's prior spacing.
  final EdgeInsets? padding;

  const FullTimelineView({
    super.key,
    required this.entries,
    required this.clientId,
    required this.clientName,
    required this.onRefresh,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(24, 48, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: CueSize.hairline, color: cue.border),
          const SizedBox(height: 20),
          Text(
            'TIMELINE',
            style: GoogleFonts.dmSans(
              fontSize:      10,
              fontWeight:    FontWeight.w600,
              color:         cue.textBody,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 20),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Sessions and goals will appear here as you document them.',
                style: GoogleFonts.dmSans(
                  fontSize:  14,
                  color:     cue.textBody,
                  fontStyle: FontStyle.italic,
                  height:    1.6,
                ),
              ),
            )
          else
            // Stack: teal line (Positioned) behind entry Column.
            Stack(
              children: [
                // Continuous teal line at x=83 (center of 24px spine,
                // after 72px date col).
                Positioned(
                  left:   83,
                  top:    0,
                  bottom: 0,
                  child: Container(width: 2, color: cue.tealFaded),
                ),
                Column(
                  children: entries
                      .map((e) => _buildEntry(context, cue, e))
                      .toList(),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ── Entry row ─────────────────────────────────────────────────────────────

  Widget _buildEntry(
      BuildContext context, CueColorsResolved cue, TimelineEntry entry) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final dayStr = entry.date.day.toString();
    final monStr = months[entry.date.month - 1];

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date column — 72px, right-aligned.
          SizedBox(
            width: 72,
            child: Padding(
              padding: const EdgeInsets.only(top: 1, right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    dayStr,
                    style: GoogleFonts.dmSans(
                      fontSize:   13,
                      fontWeight: FontWeight.w600,
                      color:      cue.textBody,
                    ),
                  ),
                  Text(
                    monStr,
                    style: GoogleFonts.dmSans(
                        fontSize: 10, color: cue.textMuted),
                  ),
                ],
              ),
            ),
          ),
          // Spine — 24px; dot centered on the Positioned teal line.
          SizedBox(
            width: 24,
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                width:  10,
                height: 10,
                margin: const EdgeInsets.only(top: 3),
                decoration: BoxDecoration(
                  shape:  BoxShape.circle,
                  color:  cue.bgCard,
                  border: Border.all(color: cue.teal, width: 2),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Content card — expanded.
          Expanded(
            child: _buildEntryCard(context, cue, entry),
          ),
        ],
      ),
    );
  }

  // ── Card dispatch ─────────────────────────────────────────────────────────

  Widget _buildEntryCard(
      BuildContext context, CueColorsResolved cue, TimelineEntry entry) {
    switch (entry.type) {
      case TimelineEntryType.session:
        return _buildSessionCard(context, cue, entry);
      case TimelineEntryType.goalSet:
        return _buildGoalSetCard(cue, entry);
      case TimelineEntryType.goalAchieved:
        return _buildGoalAchievedCard(cue, entry);
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Session card ──────────────────────────────────────────────────────────

  Widget _buildSessionCard(
      BuildContext context, CueColorsResolved cue, TimelineEntry entry) {
    // Phase 4.0.7.31b-timeline-notes-aware — third site of the legacy
    // "soap_note is the only session content" assumption pattern (after
    // report_screen.dart:196 fixed in aec81a9 and _sessionIsEmpty fixed
    // in 1ee37ba). soap_note OR notes counts as documentation; either is
    // a tap-able review target. Tri-state visual ("Notes captured ·
    // Generate report?") deferred to 4.0.7.34 design pass.
    final raw      = entry.rawData;
    final hasSoap  = (raw?['soap_note'] as String?)?.trim().isNotEmpty == true;
    final hasNotes = (raw?['notes']     as String?)?.trim().isNotEmpty == true;
    final hasNote  = hasSoap || hasNotes;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color:        cue.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: cue.isDark
            ? Border.all(color: cue.border, width: CueSize.hairline)
            : null,
        boxShadow: cue.isDark
            ? const [
                BoxShadow(
                  color:      Color(0x33000000),
                  blurRadius: 6,
                  offset:     Offset(0, 1),
                ),
              ]
            : const [
                BoxShadow(
                  color:      Color(0x08000000),
                  blurRadius: 8,
                  offset:     Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Phase 4.0.7.10b — eyebrow row with inline kebab. The popup
          // is the canonical inline-archive affordance for session cards
          // on the client profile timeline; previously the SLP had to
          // open the report screen to reach the same action.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  'Session · ${entry.title}',
                  style: GoogleFonts.dmSans(
                    fontSize:      10,
                    fontWeight:    FontWeight.w600,
                    color:         cue.teal,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              SizedBox(
                width:  28,
                height: 28,
                child: PopupMenuButton<String>(
                  tooltip:  'More',
                  iconSize: 16,
                  padding:  EdgeInsets.zero,
                  icon: Icon(
                    Icons.more_vert,
                    size:  16,
                    color: cue.textBody,
                  ),
                  onSelected: (value) async {
                    if (value != 'archive') return;
                    if (entry.rawData == null) return;
                    final archived = await archiveSession(
                      context: context,
                      session: entry.rawData!,
                    );
                    // Phase 5.3 B.3 — _refreshSpine → onRefresh callback;
                    // mounted → context.mounted post-extraction.
                    if (archived && context.mounted) onRefresh();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem<String>(
                      value: 'archive',
                      child: Text(
                        'Archive this session',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (entry.subtitle != null && entry.subtitle!.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              entry.subtitle!,
              style: GoogleFonts.dmSans(
                fontSize:  13,
                color:     cue.textBody,
                fontStyle: FontStyle.italic,
                height:    1.5,
              ),
              maxLines:  2,
              overflow:  TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          GestureDetector(
            // Phase 4.0.7.36 — await the ReportScreen pop and refresh
            // the spine. ReportScreen may mutate soap_note /
            // parent_summary / notes / clinician_attested via the
            // SOAP form save, parent-update auto-save, or the
            // "Continue editing →" → SessionCaptureScreen edit flow.
            // Without the refresh, the timeline subtitle preview
            // (now driven by _extractSoapPreview's 3-tier fallback,
            // 31c) reads stale until the SLP navigates away and back.
            onTap: hasNote && entry.rawData != null
                ? () async {
                    // Phase 4.0.7.39 — RouteSettings.name reflects
                    // /sessions/:id in the URL bar; the imperative push
                    // forwards the already-loaded session row so the
                    // timeline → report transition stays one-frame.
                    final sid = entry.rawData!['id'];
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        settings: sid == null
                            ? null
                            : RouteSettings(name: '/sessions/$sid'),
                        builder: (_) => ReportScreen(
                          session:    entry.rawData!,
                          clientName: clientName,
                          clientId:   clientId,
                        ),
                      ),
                    );
                    // Phase 5.3 B.3 — _refreshSpine → onRefresh callback;
                    // mounted → context.mounted post-extraction.
                    if (context.mounted) onRefresh();
                  }
                : null,
            child: hasNote
                ? Text(
                    'View note →',
                    style: GoogleFonts.dmSans(
                      fontSize:   12,
                      color:      cue.teal,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : Text(
                    'Pending documentation',
                    style: GoogleFonts.dmSans(
                      fontSize:   12,
                      color:      cue.amber,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ── Goal-set card ─────────────────────────────────────────────────────────

  Widget _buildGoalSetCard(CueColorsResolved cue, TimelineEntry entry) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color:        cue.tealSurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            entry.title,
            style: GoogleFonts.dmSans(
              fontSize:   11,
              fontWeight: FontWeight.w600,
              color:      cue.teal,
            ),
          ),
        ),
        if (entry.subtitle != null && entry.subtitle!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            entry.subtitle!,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              color:    cue.textPrimary,
              height:   1.5,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 4),
      ],
    );
  }

  // ── Goal-achieved card ────────────────────────────────────────────────────

  Widget _buildGoalAchievedCard(CueColorsResolved cue, TimelineEntry entry) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color:        cue.amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '✓ ${entry.title}',
            style: GoogleFonts.dmSans(
              fontSize:   11,
              fontWeight: FontWeight.w600,
              color:      cue.amber,
            ),
          ),
        ),
        if (entry.subtitle != null && entry.subtitle!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            entry.subtitle!,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              color:    cue.textPrimary,
              height:   1.5,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 4),
      ],
    );
  }
}
