import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/cue_theme.dart';
import 'add_session_screen.dart';
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
    if (added == true) {
      setState(() {
        _sessionsFuture = _fetchSessions();
      });
    }
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

  void _showSessionMenu(Map<String, dynamic> session, String clientName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: CueColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: CueColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined,
                  color: CueColors.inkPrimary),
              title: Text(
                'Generate Report',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: CueColors.inkPrimary,
                ),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReportScreen(
                      session: Map<String, dynamic>.fromEntries(
                        (session as Map).entries.map(
                            (e) => MapEntry(e.key.toString(), e.value)),
                      ),
                      clientName: clientName,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: CueColors.coral),
              title: Text(
                'Delete session',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: CueColors.coral,
                ),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                _confirmDelete(session['id'].toString());
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(String sessionId) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this session?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                color: CueColors.inkSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteSession(sessionId);
            },
            child: Text(
              'Delete',
              style: GoogleFonts.inter(
                color: CueColors.coral,
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
    final client = widget.client;
    final name = client['name']?.toString() ?? '';
    final age = client['age'];
    final usesAac = client['uses_aac'] == true;
    final totalSessions = client['total_sessions'] ?? 0;

    final subParts = <String>[];
    if (age != null) subParts.add('Age $age');
    if (usesAac) subParts.add('AAC user');
    final subtitle = subParts.join(' · ');

    return Scaffold(
      backgroundColor: CueColors.background,
      appBar: AppBar(
        title: const Text(''),
        actions: [
          IconButton(
            icon: const Icon(Icons.mic_none_rounded),
            tooltip: 'Narrator',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NarratorScreen()),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddSession,
        backgroundColor: CueColors.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: Text(
          'Add Session',
          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.fraunces(
                      fontSize: 36,
                      fontWeight: FontWeight.w500,
                      color: CueColors.inkPrimary,
                      height: 1.1,
                      letterSpacing: -0.5,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: CueColors.inkSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _sessionsFuture,
                    builder: (context, snapshot) {
                      final count = snapshot.hasData
                          ? snapshot.data!.length
                          : totalSessions as int;
                      final goalsMet = snapshot.hasData
                          ? snapshot.data!
                              .where((s) => s['goal_met'] == 'yes')
                              .length
                          : 0;
                      return Row(
                        children: [
                          _StatBlock(value: '$count', label: 'Sessions'),
                          const SizedBox(width: 48),
                          _StatBlock(value: '$goalsMet', label: 'Goals met'),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: Divider(height: 1, thickness: 1, color: CueColors.divider),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
              child: CueTheme.eyebrow('Recent Sessions'),
            ),
          ),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _sessionsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: CueColors.accent,
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                );
              }
              if (snapshot.hasError) {
                return SliverToBoxAdapter(
                  child: Center(child: Text('Error: ${snapshot.error}')),
                );
              }

              final sessions = snapshot.data!;

              if (sessions.isEmpty) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: Text(
                        'No sessions yet.',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: CueColors.inkSecondary,
                        ),
                      ),
                    ),
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                sliver: SliverList.separated(
                  itemCount: sessions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final session = sessions[index];
                    return _SessionCard(
                      session: session,
                      onMenu: () => _showSessionMenu(session, name),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  final String value;
  final String label;

  const _StatBlock({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: GoogleFonts.fraunces(
            fontSize: 28,
            fontWeight: FontWeight.w500,
            color: CueColors.inkPrimary,
            height: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: CueColors.inkSecondary,
          ),
        ),
      ],
    );
  }
}

class _SessionCard extends StatelessWidget {
  final Map<String, dynamic> session;
  final VoidCallback onMenu;

  const _SessionCard({required this.session, required this.onMenu});

  @override
  Widget build(BuildContext context) {
    final date = session['date']?.toString() ?? '—';
    final goal = session['target_behaviour']?.toString() ?? '';
    final duration = session['duration_minutes'];
    final goalMet = session['goal_met']?.toString();

    return Container(
      decoration: BoxDecoration(
        color: CueColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CueColors.divider, width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 8, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      date,
                      style: GoogleFonts.fraunces(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: CueColors.inkPrimary,
                      ),
                    ),
                    if (goalMet == 'yes') ...[
                      const SizedBox(width: 10),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: CueColors.amber,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
                if (goal.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    goal,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: CueColors.inkPrimary,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  duration != null ? '$duration min' : '—',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: CueColors.inkTertiary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz_rounded,
                color: CueColors.inkTertiary),
            onPressed: onMenu,
          ),
        ],
      ),
    );
  }
}
