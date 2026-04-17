import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/cue_theme.dart';
import 'add_session_screen.dart';
import 'narrate_session_screen.dart';
import 'narrator_screen.dart';
import 'report_screen.dart';

class ClientProfileScreen extends StatefulWidget {
  final Map<String, dynamic> client;

  const ClientProfileScreen({super.key, required this.client});

  @override
  State<ClientProfileScreen> createState() => _ClientProfileScreenState();
}

class _ClientProfileScreenState extends State<ClientProfileScreen> {
  final _supabase = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _sessionsFuture;

  @override
  void initState() {
    super.initState();
    _sessionsFuture = _fetchSessions();
  }

  Future<List<Map<String, dynamic>>> _fetchSessions() async {
    final response = await _supabase
        .from('sessions')
        .select()
        .eq('client_id', widget.client['id'])
        .order('date', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> _openNarrateSession() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NarrateSessionScreen(
          clientId: widget.client['id'].toString(),
          clientName: widget.client['name'].toString(),
        ),
      ),
    );
    if (added == true) setState(() => _sessionsFuture = _fetchSessions());
  }

  Future<void> _openAddSession() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddSessionScreen(
          clientId: widget.client['id'].toString(),
          clientName: widget.client['name'].toString(),
        ),
      ),
    );
    if (added == true) setState(() => _sessionsFuture = _fetchSessions());
  }

  Future<void> _deleteSession(String sessionId) async {
    try {
      await _supabase.from('sessions').delete().eq('id', sessionId);
      if (mounted) {
        setState(() {
          _sessionsFuture = _fetchSessions();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete session: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final client       = widget.client;
    final name         = client['name']?.toString() ?? '';
    final age          = client['age'];
    final diagnosis    = client['diagnosis']?.toString() ?? '';
    final usesAac      = client['uses_aac'] == true;
    final totalSessions = client['total_sessions'] ?? 0;
    final initial      = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Scaffold(
      backgroundColor: CueColors.softWhite,
      body: CustomScrollView(
        slivers: [
          // ── inkNavy header ─────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: CueColors.inkNavy,
            foregroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: CueColors.inkNavy,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Avatar
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white.withOpacity(0.25), width: 2),
                            color: Colors.white.withOpacity(0.12),
                          ),
                          child: Center(
                            child: Text(
                              initial,
                              style: GoogleFonts.dmSerifDisplay(
                                  fontSize: 24, color: Colors.white),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Name + subtitle
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                name,
                                style: GoogleFonts.dmSerifDisplay(
                                  fontSize: 26,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                [
                                  if (age != null) 'Age $age',
                                  if (diagnosis.isNotEmpty) diagnosis,
                                  if (usesAac) 'AAC user',
                                ].join(' · '),
                                style: GoogleFonts.dmSans(
                                  fontSize: 13,
                                  color: Colors.white.withOpacity(0.65),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Session count badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: CueColors.warmAmber,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$totalSessions',
                                style: GoogleFonts.dmSans(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'sessions',
                                style: GoogleFonts.dmSans(
                                    fontSize: 10, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.mic_rounded),
                tooltip: 'Narrator',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NarratorScreen()),
                ),
              ),
            ],
          ),

          // ── Session history header ─────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: CueTheme.sectionLabel('Session History'),
            ),
          ),

          // ── Sessions list ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _sessionsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(40),
                    child:
                        Center(child: CircularProgressIndicator(color: CueColors.signalTeal)),
                  );
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final sessions = snapshot.data!;

                if (sessions.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: Text(
                        'No sessions yet.\nTap the mic or + to add one.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.dmSans(
                            fontSize: 14, color: CueColors.textMid),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                  itemCount: sessions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final session = sessions[index];
                    return _SessionCard(
                      session: session,
                      clientName: name,
                      onDelete: () => _deleteSession(session['id'].toString()),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'narrate_fab',
            onPressed: _openNarrateSession,
            backgroundColor: CueColors.inkNavy,
            foregroundColor: Colors.white,
            tooltip: 'Narrate Session',
            child: const Icon(Icons.mic_rounded),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'add_session_fab',
            onPressed: _openAddSession,
            backgroundColor: CueColors.signalTeal,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add),
            label: Text('Add Session',
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final Map<String, dynamic> session;
  final String clientName;
  final VoidCallback onDelete;

  const _SessionCard({
    required this.session,
    required this.clientName,
    required this.onDelete,
  });

  void _showDeleteDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CueColors.surfaceWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete this session?',
          style: GoogleFonts.dmSans(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: CueColors.inkNavy,
          ),
        ),
        content: Text(
          'This cannot be undone.',
          style: GoogleFonts.dmSans(fontSize: 14, color: CueColors.textMid),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.dmSans(
                color: CueColors.inkNavy,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDelete();
            },
            style: FilledButton.styleFrom(
              backgroundColor: CueColors.errorRed,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Delete',
              style: GoogleFonts.dmSans(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final date     = session['date']?.toString() ?? '—';
    final goal     = session['target_behaviour']?.toString() ?? '';
    final duration = session['duration_minutes'];
    final goalMet  = session['goal_met']?.toString();

    return GestureDetector(
      onLongPress: () => _showDeleteDialog(context),
      child: Container(
      decoration: BoxDecoration(
        color: CueColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: const Border(
          left: BorderSide(color: CueColors.signalTeal, width: 4),
        ),
        boxShadow: [
          BoxShadow(
            color: CueColors.inkNavy.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                date,
                style: GoogleFonts.dmSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: CueColors.inkNavy,
                ),
              ),
              Row(
                children: [
                  if (duration != null)
                    _Tag(label: '$duration min', color: CueColors.textMid),
                  if (goalMet == 'yes') ...[
                    const SizedBox(width: 6),
                    _Tag(label: 'Goal met', color: CueColors.warmAmber, filled: true),
                  ] else if (goalMet == 'partially') ...[
                    const SizedBox(width: 6),
                    _Tag(label: 'Partial', color: CueColors.warmAmber),
                  ],
                ],
              ),
            ],
          ),
          if (goal.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              goal,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color: CueColors.textMid,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReportScreen(
                    session: Map<String, dynamic>.fromEntries(
                      (session as Map)
                          .entries
                          .map((e) => MapEntry(e.key.toString(), e.value)),
                    ),
                    clientName: clientName,
                  ),
                ),
              ),
              icon: const Icon(Icons.auto_awesome, size: 15,
                  color: CueColors.signalTeal),
              label: Text(
                'Generate Report',
                style: GoogleFonts.dmSans(
                    fontSize: 13, color: CueColors.signalTeal,
                    fontWeight: FontWeight.w600),
              ),
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
            ),
          ),
        ],
      ),
      ),  // Container
    );    // GestureDetector
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  final bool filled;

  const _Tag({required this.label, required this.color, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: filled ? Colors.white : color,
        ),
      ),
    );
  }
}
