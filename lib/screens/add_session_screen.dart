import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/cue_phase4_tokens.dart';
import '../widgets/app_layout.dart';
import 'narrate_session_screen.dart';
import 'session_capture_screen.dart';
// Phase 4.0.7.27d-population-router-removal — SessionModePickerView no
// longer routed to. Kept in repo as orphan code for Phase 2 multi-domain
// rebuild. The import is dropped here; re-add when routing is restored.

class AddSessionScreen extends StatefulWidget {
  final String clientId;
  final String clientName;

  const AddSessionScreen({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  @override
  State<AddSessionScreen> createState() => _AddSessionScreenState();
}

class _AddSessionScreenState extends State<AddSessionScreen> {
  final _supabase = Supabase.instance.client;

  DateTime _selectedDate = DateTime.now();
  String?  _activeStg;
  bool     _stgLoading = true;

  @override
  void initState() {
    super.initState();
    // Phase 4.0.7.31h — population_type fetch + skeleton + _saving guard
    // all removed. Origins: 4.0.7.27d-population-router-removal ripped
    // out the fluency-vs-AAC routing fork; the fetch became dead-state,
    // and the anti-flash skeleton it gated had no flip to anti-flash.
    // _saving was the await guard for the ALSO-removed _createSession
    // INSERT (deferred to downstream screens in 27d-defer-session-insert).
    // Active goal lookup is the only remaining init concern.
    _loadActiveStg();
  }

  Future<void> _loadActiveStg() async {
    try {
      // Phase 4.0.7.27d-stg-focus-resolver-fix2 — STG text lives in
      // `specific` for every proxy-generated STG (v1 and v2);
      // `target_behavior` is the prototype-era fallback. `goal_text`
      // does not exist on short_term_goals — selecting it 400s the
      // request. Backlogged: 4.0.7.30-stg-resolver-audit (other
      // readers still request goal_text and survive via catch blocks).
      final rows = await _supabase
          .from('short_term_goals')
          .select('specific, target_behavior')
          .eq('client_id', widget.clientId)
          .eq('status', 'active')
          .limit(1);
      if (mounted) {
        final row = rows.isNotEmpty ? rows.first : null;
        final text = row != null
            ? ((row['specific'] as String?)
                ?? (row['target_behavior'] as String?)
                ?? '').trim()
            : null;
        setState(() {
          _activeStg   = (text != null && text.isNotEmpty) ? text : null;
          _stgLoading  = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _stgLoading = false);
    }
  }

  // Phase 4.0.7.27d-defer-session-insert — _createSession deleted.
  // Empty draft rows used to accumulate when the SLP bailed out before
  // recording or typing anything. Row creation is now owned by the
  // downstream screens on first save: NarrateSessionScreen INSERTs in
  // _generateAndNavigate, SessionNoteScreen INSERTs in _save.
  Future<void> _startNarrator() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NarrateSessionScreen(
          clientId:    widget.clientId,
          clientName:  widget.clientName,
          sessionId:   null,
          sessionDate: _selectedDate.toIso8601String().substring(0, 10),
        ),
      ),
    );
    // Phase 4.0.7.40-flutter — this branch is now functionally
    // unreachable. NarrateSessionScreen never calls Navigator.pop
    // with `true` (the only forward exit, _generateAndNavigate, now
    // uses pushAndRemoveUntil that sweeps AddSessionScreen out of
    // the stack — and even pre-fix, narrate's Cancel/back path
    // resolved with null). The if's truth-value was always false in
    // practice; post-fix the State is also disposed before the
    // await resumes (mounted=false). Preserved per phase scope so
    // git-blame can reach the original 4.0.7.28 wiring intent if a
    // regression surfaces. Sunset alongside the legacy proxy endpoint.
    if (result == true && mounted) Navigator.pop(context, true);
  }

  Future<void> _addManually() async {
    // Phase 4.0.7.28-session-capture-v1 — route to SessionCaptureScreen
    // (prose-first capture, auto-save, domain-aware optional fields).
    // Replaces the SessionNoteScreen wizard from 27d-typed-notes-routing-
    // fix; SessionNoteScreen stays in the repo as orphan code for the
    // Phase 2 multi-domain rebuild to adapt.
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SessionCaptureScreen(
          clientId:     widget.clientId,
          clientName:   widget.clientName,
          selectedDate: _selectedDate,
        ),
      ),
    );
    // Phase 4.0.7.40-flutter — this branch still fires for the
    // regular Save flow (SessionCaptureScreen `_save` pops with
    // result=true; that pop completes symmetrically — AddSession is
    // on top when the await resumes — so this Navigator.pop targets
    // AddSessionScreen as intended, returning the SLP to chart).
    //
    // It is NO LONGER reached from the Save & Generate flow.
    // SessionCaptureScreen `_saveAndGenerate` now uses
    // pushAndRemoveUntil that sweeps AddSessionScreen out of the
    // stack, so this State is disposed before the awaited Future
    // resolves; `mounted` is false on resume, the if short-circuits.
    //
    // Pre-fix bug (typed-notes Save & Generate): when
    // SessionCaptureScreen used pushReplacement with `result: true`,
    // this Navigator.pop ran AFTER ReportScreen had already been
    // pushed, popping ReportScreen instead of AddSessionScreen —
    // bouncing the SLP back to the picker. See commit message for
    // the full mechanism. Branch preserved (not deleted) per phase
    // scope so git-blame can reach the original 4.0.7.28 wiring
    // intent if a regression surfaces. Sunset alongside the legacy
    // proxy endpoint.
    if (result == true && mounted) Navigator.pop(context, true);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate:   DateTime(2020),
      lastDate:    DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary:   kCueAmber,
            onPrimary: Colors.white,
            surface:   Colors.white,
            onSurface: kCueInk,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    // Phase 4.0.7.27d-population-router-removal — population_type no
    // longer gates the new-session surface. Every client hits the
    // unified Narrate / Type entry-mode row below regardless of clinical
    // domain. The fluency-specific SessionModePickerView (live entry /
    // debrief / parent interview) is kept in the repo as orphan code
    // for the Phase 2 multi-domain rebuild.
    return AppLayout(
      title:       'New session — ${widget.clientName}',
      activeRoute: 'roster',
      body: LayoutBuilder(
        builder: (context, constraints) {
          final hPad = constraints.maxWidth > 560 ? 48.0 : 24.0;
          return Container(
            color: kCuePaper,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                      horizontal: hPad, vertical: 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStgCard(),
                      const SizedBox(height: 32),
                      _buildDatePicker(),
                      const SizedBox(height: 40),
                      _buildEntryModeRow(),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStgCard() {
    return Container(
      decoration: BoxDecoration(
        color: kCuePaper,
        border: const Border(
            left: BorderSide(color: kCueAmber, width: 1.5)),
      ),
      padding: const EdgeInsets.only(left: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _eyebrow("today's focus"),
          const SizedBox(height: 6),
          if (_stgLoading)
            Container(
              width:  200,
              height: 14,
              decoration: BoxDecoration(
                color:        kCueBorder,
                borderRadius: BorderRadius.circular(3),
              ),
            )
          else if (_activeStg != null)
            Text(
              _activeStg!,
              style: GoogleFonts.dmSans(
                fontSize:   15,
                fontWeight: FontWeight.w500,
                color:      kCueInk,
                height:     1.45,
              ),
            )
          else
            Text(
              'No active short-term goal — set one in the client profile.',
              style: GoogleFonts.dmSans(
                fontSize:   14,
                fontStyle:  FontStyle.italic,
                color:      kCueSubtitleInk,
                height:     1.45,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _eyebrow('session date'),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickDate,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: kCueSurface,
              border: Border.all(color: kCueBorder, width: kCueCardBorderW),
              borderRadius: BorderRadius.circular(kCueCardRadius),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 16, color: kCueMutedInk),
                const SizedBox(width: 12),
                Text(
                  _formatDate(_selectedDate),
                  style: GoogleFonts.dmSans(
                      fontSize: 14, color: kCueInk),
                ),
                const Spacer(),
                const Icon(Icons.unfold_more,
                    size: 16, color: kCueEyebrowInk),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Two co-equal primary entry modes. Voice and typing carry equal weight —
  // SLPs in noisy clinics or family-present environments need typing as a
  // first-class path, not a hidden alternative under the narrator CTA.
  Widget _buildEntryModeRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Stack vertically on very narrow widths; otherwise side-by-side.
        if (constraints.maxWidth < 360) {
          return Column(
            children: [
              _entryModeButton(
                icon:  Icons.mic_rounded,
                label: 'Narrate session',
                onTap: _startNarrator,
              ),
              const SizedBox(height: 12),
              _entryModeButton(
                icon:  Icons.edit_outlined,
                label: 'Type session notes',
                onTap: _addManually,
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: _entryModeButton(
                icon:  Icons.mic_rounded,
                label: 'Narrate session',
                onTap: _startNarrator,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _entryModeButton(
                icon:  Icons.edit_outlined,
                label: 'Type session notes',
                onTap: _addManually,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _entryModeButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 56,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: kCueInk,
          foregroundColor: Colors.white,
          disabledBackgroundColor: kCueInk.withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kCueCardRadius),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSans(
                  fontSize:   15,
                  fontWeight: FontWeight.w500,
                  color:      Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Lowercase tracked eyebrow per Phase 4.0 register.
  Widget _eyebrow(String label) => Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: kCueEyebrowInk,
          letterSpacing: kCueEyebrowLetterSpacing(11),
        ),
      );

  String _formatDate(DateTime d) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month]} ${d.year}';
  }
}
