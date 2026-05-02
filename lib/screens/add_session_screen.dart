import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_layout.dart';
import 'narrate_session_screen.dart';
import 'report_screen.dart';

const _bg    = Color(0xFFF2EFE9);
const _ink   = Color(0xFF0A0A0A);
const _ghost = Color(0xFF8A8A8A);
const _muted = Color(0xFFB0ADA6);
const _line  = Color(0xFFD8D5CE);
const _teal  = Color(0xFF1D9E75);

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

  @override
  void initState() {
    super.initState();
    _loadActiveStg();
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
            primary:   _teal,
            onPrimary: Colors.white,
            surface:   Colors.white,
            onSurface: _ink,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title:       'New Session — ${widget.clientName}',
      activeRoute: 'roster',
      body: LayoutBuilder(
        builder: (context, constraints) {
          final hPad = constraints.maxWidth > 560 ? 48.0 : 24.0;
          return Container(
            color: _bg,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
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
                      _buildNarratorButton(),
                      const SizedBox(height: 12),
                      _buildManualButton(),
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
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: _teal, width: 1.5)),
      ),
      padding: const EdgeInsets.only(left: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "TODAY'S FOCUS",
            style: GoogleFonts.dmSans(
              fontSize:   10,
              fontWeight: FontWeight.w700,
              color:      _teal,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          if (_stgLoading)
            Container(
              width:  200,
              height: 14,
              decoration: BoxDecoration(
                color:        _line,
                borderRadius: BorderRadius.circular(3),
              ),
            )
          else if (_activeStg != null)
            Text(
              _activeStg!,
              style: GoogleFonts.dmSans(
                fontSize:   15,
                fontWeight: FontWeight.w500,
                color:      _ink,
                height:     1.45,
              ),
            )
          else
            Text(
              'No active short-term goal — set one in the client profile.',
              style: GoogleFonts.dmSans(
                fontSize:   14,
                fontStyle:  FontStyle.italic,
                color:      _ghost,
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
        Text(
          'SESSION DATE',
          style: GoogleFonts.dmSans(
            fontSize:   10,
            fontWeight: FontWeight.w700,
            color:      _ghost,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickDate,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border:       Border.all(color: _line),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 16, color: _ghost),
                const SizedBox(width: 12),
                Text(
                  _formatDate(_selectedDate),
                  style: GoogleFonts.dmSans(
                      fontSize: 14, color: _ink),
                ),
                const Spacer(),
                const Icon(Icons.unfold_more,
                    size: 16, color: _muted),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNarratorButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _saving ? null : _startNarrator,
        style: FilledButton.styleFrom(
          backgroundColor:         _teal,
          disabledBackgroundColor: _teal.withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _saving
            ? const SizedBox(
                width:  20,
                height: 20,
                child:  CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
            : Text(
                'Start Narrator →',
                style: GoogleFonts.dmSans(
                  fontSize:   16,
                  fontWeight: FontWeight.w500,
                  color:      Colors.white,
                ),
              ),
      ),
    );
  }

  Widget _buildManualButton() {
    return Center(
      child: TextButton(
        onPressed: _saving ? null : _addManually,
        style: TextButton.styleFrom(foregroundColor: _ghost),
        child: Text(
          'Add notes manually',
          style: GoogleFonts.dmSans(fontSize: 13, color: _ghost),
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month]} ${d.year}';
  }
}
