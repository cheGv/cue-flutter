// lib/screens/inbox_screen.dart
//
// Phase 4.1.7 — Inbox: worklist of draft sessions waiting to be
// documented. Replaces the standalone Narrator destination in the
// sidebar's fourth slot.
//
// Data source: single source of truth is `ClientsRosterService
// .listDraftSessions()` — the SAME query whose `.length` is the Clients
// action-line banner. The Inbox renders the rows; the banner shows the
// count. They cannot drift.
//
// Row tap routes to `/sessions/<id>/edit`, which resolves via
// `main.dart`'s onGenerateRoute to `_SessionCaptureEditDeepLinkLoader`
// and ultimately mounts SessionCaptureScreen in edit mode against the
// existing draft. The Inbox itself processes / transcribes /
// documents nothing — it is a worklist.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/clients_roster_service.dart';
import '../theme/cue_color_scheme.dart';
import '../theme/cue_text_styles.dart';
import '../widgets/app_layout.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final ClientsRosterService _service = ClientsRosterService();

  bool _loading = true;
  String? _error;
  List<DraftSessionEntry> _rows = const <DraftSessionEntry>[];

  // Phase 4.1.8 batch flow — true after the SLP completes a draft and
  // there's a NEW top entry waiting. The banner offers a one-tap entry
  // into that next doc; the SLP can ignore it and use the list, or
  // dismiss it. Never auto-navigates (per spec — "the SLP must stay in
  // control").
  bool _showNextBanner = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = await _service.listDraftSessions();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _openDoc(DraftSessionEntry entry) async {
    final beforeCount = _rows.length;
    // The SessionCaptureScreen edit flow is reached through main.dart's
    // named-route loader. Awaiting Navigator.pushNamed lets us detect
    // the completion-vs-cancel state when the user pops back.
    await Navigator.pushNamed(context, '/sessions/${entry.id}/edit');
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    // If the list got shorter, the SLP saved a complete note for the
    // draft they just opened. Offer the new top entry as a one-tap
    // "Document next" — without yanking them in.
    final completed = _rows.length < beforeCount && _rows.isNotEmpty;
    setState(() => _showNextBanner = completed);
  }

  void _dismissNextBanner() {
    setState(() => _showNextBanner = false);
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: 'Inbox',
      activeRoute: 'inbox',
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 768;
          final padding = isMobile
              ? const EdgeInsets.fromLTRB(20, 28, 20, 40)
              : const EdgeInsets.fromLTRB(80, 50, 56, 56);
          final text = CueTextStyles.of(context, isMobile: isMobile);
          final cue = CueColorsResolved.of(context);
          return RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: padding,
              children: [
                _header(cue),
                const SizedBox(height: 24),
                if (_loading)
                  _LoadingBlock(color: cue.border)
                else if (_error != null)
                  _ErrorBlock(message: _error!, onRetry: _load, text: text)
                else if (_rows.isEmpty)
                  _EmptyBlock(text: text, cue: cue)
                else ...[
                  if (_showNextBanner)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _NextDocBanner(
                        next: _rows.first,
                        onOpen: () {
                          _dismissNextBanner();
                          _openDoc(_rows.first);
                        },
                        onDismiss: _dismissNextBanner,
                      ),
                    ),
                  for (int i = 0; i < _rows.length; i++) ...[
                    if (i > 0)
                      Divider(
                        color: cue.border,
                        height: 1,
                        thickness: 0.5,
                      ),
                    _InboxRow(
                      entry: _rows[i],
                      onTap: () => _openDoc(_rows[i]),
                    ),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  //
  // Mirrors the Assessing screen's header pattern verbatim: Syne 10/600
  // amber uppercase eyebrow → Playfair italic 28/400 hero → DM Sans 13
  // muted subline. Same editorial register the rest of the chrome uses.

  Widget _header(CueColorsResolved cue) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DOCUMENTATION',
          style: GoogleFonts.syne(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: cue.amber,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Sessions waiting.',
          style: GoogleFonts.playfairDisplay(
            fontSize: 28,
            fontWeight: FontWeight.w400,
            fontStyle: FontStyle.italic,
            color: cue.textPrimary,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Every session here needs a note before it is clinically complete.',
          style: GoogleFonts.dmSans(
            fontSize: 13,
            color: cue.textSecondary,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

// ── Row ──────────────────────────────────────────────────────────────────────

class _InboxRow extends StatelessWidget {
  final DraftSessionEntry entry;
  final VoidCallback onTap;

  const _InboxRow({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);
    final dateLabel = _shortDate(entry.sessionDate);
    final chipLabel = entry.consequenceSignal.chipLabel;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          entry.clientName.isEmpty
                              ? 'Untitled client'
                              : entry.clientName,
                          style: GoogleFonts.dmSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: cue.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (chipLabel != null) ...[
                        const SizedBox(width: 10),
                        _ConsequenceChip(label: chipLabel),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Phase 4.1.8 — neutral meta line. The previous
                  // "Waiting Xd ago" phrasing read as judgment ("Waiting
                  // 2 months" implies the SLP is late). Dropped in
                  // favour of plain date + duration. The SLP can read
                  // the wait directly from the date if she wants to.
                  Text(
                    _composeMeta(dateLabel, entry.durationMinutes),
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: cue.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: cue.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  static String _composeMeta(String? date, int? minutes) {
    final parts = <String>[
      if (date != null && date.isNotEmpty) 'Recorded $date',
      if (minutes != null) '$minutes min',
    ];
    if (parts.isEmpty) return 'Draft session';
    return parts.join(' · ');
  }

  static String? _shortDate(DateTime? dt) {
    if (dt == null) return null;
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month]} ${dt.day}';
  }

}

// ── Empty / loading / error states ───────────────────────────────────────────

class _EmptyBlock extends StatelessWidget {
  final CueTextStyles text;
  final CueColorsResolved cue;
  const _EmptyBlock({required this.text, required this.cue});

  @override
  Widget build(BuildContext context) {
    // Matches the "All caught up." editorial voice used on Today's
    // pending-notes treatment.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'All caught up.',
            style: GoogleFonts.playfairDisplay(
              fontSize: 22,
              fontWeight: FontWeight.w400,
              fontStyle: FontStyle.italic,
              color: cue.textPrimary,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Nothing waiting to be documented.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              color: cue.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingBlock extends StatelessWidget {
  final Color color;
  const _LoadingBlock({required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final CueTextStyles text;
  const _ErrorBlock({
    required this.message,
    required this.onRetry,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Could not load the Inbox.',
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: cue.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style: GoogleFonts.dmSans(fontSize: 12, color: cue.textSecondary),
          ),
          const SizedBox(height: 10),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

// ── Consequence chip (Phase 4.1.8) ───────────────────────────────────────────
//
// Renders the cadence-neutral signal label on rows the recon verified
// (currently only "Assessment case"). Uses the existing amber-accent
// surface and border tokens — no new colors, no alarm register.

class _ConsequenceChip extends StatelessWidget {
  final String label;
  const _ConsequenceChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cue.amber.withValues(alpha: cue.isDark ? 0.10 : 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: cue.amber.withValues(alpha: 0.4),
          width: 0.5,
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 10 * 0.02,
          color: cue.amber,
        ),
      ),
    );
  }
}

// ── Document-next banner (Phase 4.1.8 Part 2 — batch flow) ───────────────────
//
// Renders above the list after the SLP completes a draft, hinting at
// the new top entry. Tapping the primary affordance routes into the
// next doc; the × dismisses the banner without leaving the Inbox. The
// SLP can always ignore it and use the list normally — never yanked
// into the next note (per spec).

class _NextDocBanner extends StatelessWidget {
  final DraftSessionEntry next;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  const _NextDocBanner({
    required this.next,
    required this.onOpen,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);
    final clientName =
        next.clientName.isEmpty ? 'this client' : next.clientName;
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: cue.amber.withValues(alpha: cue.isDark ? 0.08 : 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: cue.amber.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onOpen,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Document next: $clientName',
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: cue.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '→',
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: cue.amber,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded, size: 16),
              color: cue.textSecondary,
              tooltip: 'Done for now',
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(
                minWidth: 28,
                minHeight: 28,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
