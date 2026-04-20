import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_layout.dart';
import 'add_goal_screen.dart';
import 'report_screen.dart';
import 'add_session_screen.dart';
import 'narrate_session_screen.dart';
import 'goal_authoring_screen.dart';

// ── §5 Design-system palette ──────────────────────────────────────────────────
const Color _ink    = Color(0xFF1B2B4B);
const Color _ghost  = Color(0xFF6B7690);
const Color _paper  = Color(0xFFFAFAF7);
const Color _paper2 = Color(0xFFF0EDE4);
const Color _line   = Color(0xFFE8E4DC);
const Color _teal   = Color(0xFF2A8F84);
const Color _amber  = Color(0xFFD68A2B);
const Color _green  = Color(0xFF3A8C5C);

class ClientProfileScreen extends StatefulWidget {
  final Map<String, dynamic> client;

  const ClientProfileScreen({super.key, required this.client});

  @override
  State<ClientProfileScreen> createState() => _ClientProfileScreenState();
}

class _ClientProfileScreenState extends State<ClientProfileScreen> {
  final _supabase = Supabase.instance.client;

  // Primary: short_term_goals (memory-layer spine)
  late Future<List<Map<String, dynamic>>> _stgsFuture;

  // Secondary: session history
  late Future<List<Map<String, dynamic>>> _sessionsFuture;

  // Legacy accordion: old goals table
  late Future<List<Map<String, dynamic>>> _goalsFuture;
  late Future<List<Map<String, dynamic>>> _achievedGoalsFuture;

  bool _showLtgs = false;
  bool _showAchievedGoals = false;

  @override
  void initState() {
    super.initState();
    _stgsFuture       = _fetchStgs();
    _sessionsFuture   = _fetchSessions();
    _goalsFuture      = _fetchGoals();
    _achievedGoalsFuture = _fetchAchievedGoals();
  }

  // ── Data fetchers ────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _fetchStgs() async {
    final response = await _supabase
        .from('short_term_goals')
        .select()
        .eq('client_id', widget.client['id'].toString())
        .eq('status', 'active')
        .order('sequence_num', ascending: true);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> _fetchSessions() async {
    final response = await _supabase
        .from('sessions')
        .select()
        .eq('client_id', widget.client['id'])
        .order('date', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> _fetchGoals() async {
    final response = await _supabase
        .from('goals')
        .select()
        .eq('client_id', widget.client['id'].toString())
        .eq('status', 'active')
        .isFilter('deleted_at', null)
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> _fetchAchievedGoals() async {
    final response = await _supabase
        .from('goals')
        .select()
        .eq('client_id', widget.client['id'].toString())
        .eq('status', 'achieved')
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  // ── Navigation / mutations ───────────────────────────────────────────────────

  void _openGoalAuthoring() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GoalAuthoringScreen(
          clientId: widget.client['id'].toString(),
          clientName: widget.client['name'] as String? ?? '',
          sessionCount: widget.client['total_sessions'] as int? ?? 0,
        ),
      ),
    );
  }

  Future<void> _openAddGoal({Map<String, dynamic>? goal}) async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddGoalScreen(
          clientId: widget.client['id'].toString(),
          goal: goal,
        ),
      ),
    );
    if (added == true) {
      setState(() => _goalsFuture = _fetchGoals());
    }
  }

  Future<void> _markGoalAchieved(String goalId) async {
    try {
      await _supabase
          .from('goals')
          .update({'status': 'achieved'})
          .eq('id', goalId);
      setState(() {
        _goalsFuture         = _fetchGoals();
        _achievedGoalsFuture = _fetchAchievedGoals();
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update goal. Please try again.')),
        );
      }
    }
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
    if (added == true) {
      setState(() {
        _sessionsFuture = _fetchSessions();
        _stgsFuture     = _fetchStgs(); // evidence may have updated STG state
      });
    }
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
        _stgsFuture     = _fetchStgs();
      });
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: widget.client['name'] as String? ?? '',
      activeRoute: 'roster',
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'narrate_fab',
            onPressed: _openNarrateSession,
            backgroundColor: _ink,
            foregroundColor: Colors.white,
            elevation: 0,
            tooltip: 'Narrate Session',
            child: const Icon(Icons.mic_rounded),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'add_session_fab',
            onPressed: _openAddSession,
            backgroundColor: _teal,
            foregroundColor: Colors.white,
            elevation: 0,
            icon: const Icon(Icons.add),
            label: Text('Add Session', style: GoogleFonts.dmSans()),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final hPad = constraints.maxWidth > 700 ? 48.0 : 20.0;
          return ColoredBox(
            color: _paper,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildClientHeader(hPad)),
                SliverToBoxAdapter(child: _buildStgSpine(hPad)),
                SliverToBoxAdapter(child: _buildSessionsSection(hPad)),
                SliverToBoxAdapter(child: _buildLtgAccordion(hPad)),
                const SliverToBoxAdapter(child: SizedBox(height: 96)),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Client header ─────────────────────────────────────────────────────────────

  Widget _buildClientHeader(double hPad) {
    final client  = widget.client;
    final name    = client['name'] as String? ?? '';
    final age     = client['age'];
    final usesAac = client['uses_aac'] == true;
    final diagnosis     = client['diagnosis'] as String?;
    final totalSessions = client['total_sessions'];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(hPad, 28, hPad, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Initial avatar — §5 style (no CircleAvatar teal)
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _paper2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _line),
            ),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: GoogleFonts.playfairDisplay(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: _ink,
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (age != null) 'Age $age',
                    usesAac ? 'AAC user' : 'No AAC',
                  ].join(' · '),
                  style: GoogleFonts.dmSans(fontSize: 13, color: _ghost),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    if (totalSessions != null)
                      _DataChip(
                        icon: Icons.calendar_today_outlined,
                        label: '$totalSessions sessions',
                      ),
                    if (diagnosis != null && diagnosis.isNotEmpty)
                      _DataChip(icon: Icons.label_outline, label: diagnosis),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── STG spine — always visible, renders first ─────────────────────────────────

  Widget _buildStgSpine(double hPad) {
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 28, hPad, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(
            children: [
              Text(
                'Active Goals',
                style: GoogleFonts.syne(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              _HeaderButton(
                icon: Icons.auto_awesome_outlined,
                label: 'Generate Plan',
                onTap: _openGoalAuthoring,
              ),
            ],
          ),
          const SizedBox(height: 14),

          FutureBuilder<List<Map<String, dynamic>>>(
            future: _stgsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const _StgSkeleton();
              }

              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Could not load goals.',
                    style: GoogleFonts.dmSans(color: _ghost, fontSize: 13),
                  ),
                );
              }

              final stgs = snapshot.data ?? [];

              if (stgs.isEmpty) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _paper2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No active STGs yet.',
                        style: GoogleFonts.dmSans(
                          color: _ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Use Generate Plan to create evidence-based short-term goals.',
                        style: GoogleFonts.dmSans(color: _ghost, fontSize: 13),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: stgs.map((stg) => _StgCard(stg: stg)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Session history ──────────────────────────────────────────────────────────

  Widget _buildSessionsSection(double hPad) {
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 32, hPad, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Session History',
            style: GoogleFonts.syne(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _ink,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 14),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _sessionsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                );
              }

              if (snapshot.hasError) {
                return Text(
                  'Could not load sessions.',
                  style: GoogleFonts.dmSans(color: _ghost, fontSize: 13),
                );
              }

              final sessions = snapshot.data ?? [];

              if (sessions.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'No sessions yet. Record the first one.',
                    style: GoogleFonts.dmSans(
                      color: _ghost,
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                );
              }

              return Column(
                children: sessions
                    .map((s) => _SessionCard(
                          session: s,
                          clientId: widget.client['id'].toString(),
                          clientName:
                              (widget.client['name'] ?? '').toString(),
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Prior goals accordion (legacy goals table) ───────────────────────────────

  Widget _buildLtgAccordion(double hPad) {
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 1, color: _line),
          const SizedBox(height: 16),
          Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _showLtgs = !_showLtgs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Prior Goals',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _ghost,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _showLtgs ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: _ghost,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              _HeaderButton(
                icon: Icons.add,
                label: 'Add',
                onTap: () => _openAddGoal(),
              ),
            ],
          ),
          if (_showLtgs) ...[
            const SizedBox(height: 12),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _goalsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  );
                }
                final goals = snapshot.data ?? [];
                if (goals.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'No prior goals.',
                      style: GoogleFonts.dmSans(
                        color: _ghost,
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  );
                }
                return Column(
                  children: goals
                      .map((g) => _LtgRow(
                            goal: g,
                            onEdit: () => _openAddGoal(goal: g),
                            onMarkAchieved: () =>
                                _markGoalAchieved(g['id'].toString()),
                          ))
                      .toList(),
                );
              },
            ),
            // Achieved goals sub-toggle
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _achievedGoalsFuture,
              builder: (context, snapshot) {
                final achieved = snapshot.data ?? [];
                if (snapshot.connectionState == ConnectionState.waiting &&
                    achieved.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'Achieved',
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            color: _ghost,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => setState(
                              () => _showAchievedGoals = !_showAchievedGoals),
                          child: Text(
                            _showAchievedGoals
                                ? 'Hide'
                                : 'Show (${achieved.length})',
                            style: GoogleFonts.dmSans(
                              fontSize: 12,
                              color: _teal,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_showAchievedGoals && achieved.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Column(
                        children: achieved
                            .map((g) => _LtgRow(
                                  goal: g,
                                  isAchieved: true,
                                  onEdit: () {},
                                  onMarkAchieved: () {},
                                ))
                            .toList(),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── Private widgets ───────────────────────────────────────────────────────────

/// STG card — the primary clinical information unit.
class _StgCard extends StatelessWidget {
  final Map<String, dynamic> stg;

  const _StgCard({required this.stg});

  @override
  Widget build(BuildContext context) {
    final behavior          = _behaviorText();
    final cueLevelRaw       = stg['current_cue_level'] as String?;
    final domain            = stg['domain'] as String?;
    final framework         = stg['framework'] as String?;
    final currentAccuracy   = (stg['current_accuracy'] as num?)?.toDouble();
    final sessionsAtCrit    = stg['sessions_at_criterion'] as int? ?? 0;
    final updatedAt         = stg['updated_at'] as String?;

    // Mastery criterion target — prefer jsonb, fall back to legacy column
    final mc = stg['mastery_criterion'];
    final double targetPct =
        (mc is Map ? (mc['accuracy_pct'] as num?)?.toDouble() : null) ??
            (stg['target_accuracy'] as num?)?.toDouble() ??
            80.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Domain / framework tags + status badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (domain != null) _Tag(domain),
                      if (framework != null) _Tag(framework),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StatusBadge(stg['status'] as String? ?? 'active'),
              ],
            ),
            const SizedBox(height: 10),

            // Target behavior (Playfair — §5 display font)
            Text(
              behavior,
              style: GoogleFonts.playfairDisplay(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _ink,
                height: 1.4,
              ),
            ),

            // Current cue level
            if (cueLevelRaw != null) ...[
              const SizedBox(height: 8),
              _DataChip(
                icon: Icons.touch_app_outlined,
                label: _cueLabel(cueLevelRaw),
              ),
            ],

            // Accuracy progress bar
            if (currentAccuracy != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (currentAccuracy / 100).clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: _line,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          currentAccuracy >= targetPct ? _green : _teal,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${currentAccuracy.toStringAsFixed(0)}%',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _ink,
                    ),
                  ),
                  Text(
                    ' / ${targetPct.toStringAsFixed(0)}%',
                    style: GoogleFonts.dmSans(fontSize: 12, color: _ghost),
                  ),
                ],
              ),
            ],

            // Sessions at criterion
            if (sessionsAtCrit > 0) ...[
              const SizedBox(height: 6),
              Text(
                '$sessionsAtCrit session${sessionsAtCrit == 1 ? '' : 's'} at criterion',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: _green,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],

            // Last worked date
            if (updatedAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'Last worked ${_formatDate(updatedAt)}',
                style: GoogleFonts.dmSans(fontSize: 11, color: _ghost),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _behaviorText() {
    final tb = stg['target_behavior'] as String?;
    if (tb != null && tb.isNotEmpty) return tb;
    return stg['specific'] as String? ?? 'Untitled goal';
  }

  static String _cueLabel(String raw) => switch (raw) {
        'independent'   => 'Independent',
        'minimal'       => 'Minimal cue',
        'moderate'      => 'Moderate cue',
        'maximal'       => 'Maximal cue',
        'hand_over_hand' => 'Hand-over-hand',
        _               => raw,
      };

  static String _formatDate(String iso) {
    try {
      final dt   = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt).inDays;
      if (diff == 0) return 'today';
      if (diff == 1) return 'yesterday';
      if (diff < 7) return '$diff days ago';
      return '${dt.day}/${dt.month}/${dt.year % 100}';
    } catch (_) {
      return iso;
    }
  }
}

/// Two placeholder boxes shown while STGs load.
class _StgSkeleton extends StatelessWidget {
  const _StgSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        2,
        (_) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: 110,
          decoration: BoxDecoration(
            color: _paper2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _line),
          ),
        ),
      ),
    );
  }
}

/// Colored pill reflecting STG status (§6.6).
class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge(this.status);

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      'active'       => ('Active', _ink, Colors.white),
      'mastered'     => ('Mastered', _green, Colors.white),
      'on_hold'      => ('On hold', _amber, Colors.white),
      'discontinued' => ('Discontinued', _paper2, _ghost),
      'modified'     => ('Modified', _amber, Colors.white),
      _              => ('Active', _ink, Colors.white),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

/// Tinted border pill for domain / framework labels.
class _Tag extends StatelessWidget {
  final String label;

  const _Tag(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: _paper2,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _line),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          color: _ink,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Icon + label inline chip (used in header and STG card).
class _DataChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DataChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: _ghost),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.dmSans(fontSize: 12, color: _ghost)),
      ],
    );
  }
}

/// Small teal text + icon action button used in section headers.
class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HeaderButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _teal),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              color: _teal,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Restyled session card — no elevation, §5 palette, navigates to ReportScreen.
class _SessionCard extends StatelessWidget {
  final Map<String, dynamic> session;
  final String clientId;
  final String clientName;

  const _SessionCard({
    required this.session,
    required this.clientId,
    required this.clientName,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr  = session['date'] as String? ?? '';
    final duration = session['duration_minutes'];
    final notes    = session['notes'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  dateStr,
                  style: GoogleFonts.dmSans(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: _ink,
                  ),
                ),
                const Spacer(),
                if (duration != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: _paper2,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _line),
                    ),
                    child: Text(
                      '$duration min',
                      style: GoogleFonts.dmSans(fontSize: 12, color: _ghost),
                    ),
                  ),
              ],
            ),
            if (notes != null && notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                notes,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSans(
                  color: _ghost,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReportScreen(
                      session: Map<String, dynamic>.fromEntries(
                        (session as Map)
                            .entries
                            .map((e) => MapEntry(e.key.toString(), e.value)),
                      ),
                      clientName: clientName,
                      clientId: clientId,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, size: 14, color: _teal),
                    const SizedBox(width: 4),
                    Text(
                      'Generate Report',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        color: _teal,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Row item for the collapsed legacy goals accordion.
class _LtgRow extends StatelessWidget {
  final Map<String, dynamic> goal;
  final bool isAchieved;
  final VoidCallback onEdit;
  final VoidCallback onMarkAchieved;

  const _LtgRow({
    required this.goal,
    this.isAchieved = false,
    required this.onEdit,
    required this.onMarkAchieved,
  });

  @override
  Widget build(BuildContext context) {
    final goalText = goal['goal_text'] as String? ?? '';
    final domain   = goal['domain'] as String? ?? '';
    final accuracy = goal['target_accuracy'];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isAchieved ? _paper2 : Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (domain.isNotEmpty) _Tag(domain),
              const Spacer(),
              if (accuracy != null)
                Text(
                  '$accuracy% target',
                  style: GoogleFonts.dmSans(fontSize: 11, color: _ghost),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            goalText,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              color: isAchieved ? _ghost : _ink,
              height: 1.5,
            ),
          ),
          if (!isAchieved) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: onEdit,
                  child: Text(
                    'Edit',
                    style: GoogleFonts.dmSans(fontSize: 12, color: _ghost),
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: onMarkAchieved,
                  child: Text(
                    'Mark achieved',
                    style: GoogleFonts.dmSans(fontSize: 12, color: _teal),
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 4),
            Text(
              '✓ Achieved',
              style: GoogleFonts.dmSans(fontSize: 12, color: _green),
            ),
          ],
        ],
      ),
    );
  }
}
