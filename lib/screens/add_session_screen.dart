import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/cue_phase4_tokens.dart';
import '../widgets/app_layout.dart';
import 'narrate_session_screen.dart';
import 'report_screen.dart';
import 'session_mode_picker_screen.dart';

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
  bool     _saving     = false;

  // Phase 4.0.4 — population routing. While null, render a quiet skeleton
  // so we don't briefly flash the legacy AAC flow before swapping to the
  // mode picker for developmental_stuttering clients.
  String? _populationType;
  bool    _populationLoading = true;

  @override
  void initState() {
    super.initState();
    _loadActiveStg();
    _loadPopulationType();
  }

  Future<void> _loadPopulationType() async {
    try {
      final row = await _supabase
          .from('clients')
          .select('population_type')
          .eq('id', widget.clientId)
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _populationType = (row?['population_type'] as String?) ?? 'asd_aac';
        _populationLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _populationType = 'asd_aac'; // safe fallback — keeps legacy flow
        _populationLoading = false;
      });
    }
  }

  Future<void> _loadActiveStg() async {
    try {
      final rows = await _supabase
          .from('short_term_goals')
          .select('goal_text')
          .eq('client_id', widget.clientId)
          .eq('status', 'active')
          .limit(1);
      if (mounted) {
        final text = rows.isNotEmpty
            ? (rows.first['goal_text'] as String? ?? '').trim()
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

  // Creates a session with date only, returns the inserted row (with id).
  Future<Map<String, dynamic>?> _createSession() async {
    final uid     = _supabase.auth.currentUser?.id;
    final dateStr = _selectedDate.toIso8601String().substring(0, 10);
    try {
      final rows = await _supabase
          .from('sessions')
          .insert({
            'client_id': widget.clientId,
            'date':      dateStr,
            'user_id':   ?uid,
          })
          .select();
      return rows.isNotEmpty
          ? Map<String, dynamic>.from(rows.first as Map)
          : {'client_id': widget.clientId, 'date': dateStr};
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating session: $e')),
        );
      }
      return null;
    }
  }

  Future<void> _startNarrator() async {
    setState(() => _saving = true);
    final session = await _createSession();
    if (!mounted) return;
    setState(() => _saving = false);
    if (session == null) return;

    final sessionId   = session['id']?.toString();
    final sessionDate = _selectedDate.toIso8601String().substring(0, 10);

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NarrateSessionScreen(
          clientId:    widget.clientId,
          clientName:  widget.clientName,
          sessionId:   sessionId,
          sessionDate: sessionDate,
        ),
      ),
    );
    if (result == true && mounted) Navigator.pop(context, true);
  }

  Future<void> _addManually() async {
    setState(() => _saving = true);
    final session = await _createSession();
    if (!mounted) return;
    setState(() => _saving = false);
    if (session == null) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ReportScreen(
          session:    session,
          clientName: widget.clientName,
          clientId:   widget.clientId,
        ),
      ),
    );
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
    // While the population fetch is in flight, render a blank container
    // so the legacy AAC body doesn't flash before swapping to the picker.
    if (_populationLoading) {
      return AppLayout(
        title: 'New session — ${widget.clientName}',
        activeRoute: 'roster',
        body: const SizedBox.shrink(),
      );
    }

    if (_populationType == 'developmental_stuttering') {
      return AppLayout(
        title: 'New session — ${widget.clientName}',
        activeRoute: 'roster',
        body: SessionModePickerView(
          clientId:   widget.clientId,
          clientName: widget.clientName,
        ),
      );
    }

    // ASD/AAC and any other legacy population — Phase 4.0 register.
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
                onTap: _saving ? null : _startNarrator,
              ),
              const SizedBox(height: 12),
              _entryModeButton(
                icon:  Icons.edit_outlined,
                label: 'Type session notes',
                onTap: _saving ? null : _addManually,
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
                onTap: _saving ? null : _startNarrator,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _entryModeButton(
                icon:  Icons.edit_outlined,
                label: 'Type session notes',
                onTap: _saving ? null : _addManually,
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
    final showSpinner = _saving;
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
        child: showSpinner
            ? const SizedBox(
                width:  18,
                height: 18,
                child:  CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
            : Row(
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
