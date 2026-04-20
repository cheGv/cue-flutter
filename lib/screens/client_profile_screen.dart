import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_layout.dart';
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

// ── Data class ────────────────────────────────────────────────────────────────
class _SpineData {
  final List<Map<String, dynamic>> ltgs;
  final List<Map<String, dynamic>> stgs; // all statuses
  const _SpineData({required this.ltgs, required this.stgs});
}

class ClientProfileScreen extends StatefulWidget {
  final Map<String, dynamic> client;

  const ClientProfileScreen({super.key, required this.client});

  @override
  State<ClientProfileScreen> createState() => _ClientProfileScreenState();
}

class _ClientProfileScreenState extends State<ClientProfileScreen> {
  final _supabase = Supabase.instance.client;

  // Primary: LTGs + all STGs (full ladder needs all statuses)
  late Future<_SpineData> _spineFuture;

  // Secondary: session history
  late Future<List<Map<String, dynamic>>> _sessionsFuture;

  // Edit drawer state
  Map<String, dynamic>? _editingStg;
  Map<String, dynamic>? _editingLtg;

  // LTG collapse state (ltg_id → expanded); default open
  final Map<String, bool> _ltgExpanded = {};

  @override
  void initState() {
    super.initState();
    _spineFuture    = _fetchSpine();
    _sessionsFuture = _fetchSessions();
  }

  // ── Data fetchers ────────────────────────────────────────────────────────────

  Future<_SpineData> _fetchSpine() async {
    final clientId = widget.client['id'].toString();
    // long_term_goals uses client_id (text) — confirmed from actual schema
    final ltgsRaw = await _supabase
        .from('long_term_goals')
        .select()
        .eq('client_id', clientId)
        .order('sequence_num', ascending: true);
    // Fetch ALL statuses so the full arc (mastered → active → upcoming) is visible
    final stgsRaw = await _supabase
        .from('short_term_goals')
        .select()
        .eq('client_id', clientId)
        .order('sequence_num', ascending: true);
    return _SpineData(
      ltgs: List<Map<String, dynamic>>.from(ltgsRaw),
      stgs: List<Map<String, dynamic>>.from(stgsRaw),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchSessions() async {
    final response = await _supabase
        .from('sessions')
        .select()
        .eq('client_id', widget.client['id'])
        .order('date', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  // ── Navigation ───────────────────────────────────────────────────────────────

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
        _spineFuture    = _fetchSpine();
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
        _spineFuture    = _fetchSpine();
      });
    }
  }

  // ── STG edit ─────────────────────────────────────────────────────────────────

  void _openEdit(Map<String, dynamic> stg) =>
      setState(() => _editingStg = Map<String, dynamic>.from(stg));

  void _closeEdit() => setState(() => _editingStg = null);

  Future<void> _saveEdit(String id, Map<String, dynamic> updates) async {
    await _supabase.from('short_term_goals').update(updates).eq('id', id);
    if (mounted) {
      setState(() {
        _editingStg  = null;
        _spineFuture = _fetchSpine();
      });
    }
  }

  // ── LTG edit ─────────────────────────────────────────────────────────────────

  void _openLtgEdit(Map<String, dynamic> ltg) =>
      setState(() => _editingLtg = Map<String, dynamic>.from(ltg));

  void _closeLtgEdit() => setState(() => _editingLtg = null);

  Future<void> _saveLtgEdit(String id, Map<String, dynamic> updates) async {
    await _supabase.from('long_term_goals').update(updates).eq('id', id);
    if (mounted) {
      setState(() {
        _editingLtg  = null;
        _spineFuture = _fetchSpine();
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
          final hPad       = constraints.maxWidth > 700 ? 48.0 : 20.0;
          final drawerWidth =
              (constraints.maxWidth * 0.38).clamp(300.0, 460.0);

          return Stack(
            children: [
              // ── Main scroll content ──────────────────────────────────────
              ColoredBox(
                color: _paper,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _buildClientHeader(hPad)),
                    SliverToBoxAdapter(child: _buildStgSpine(hPad)),
                    SliverToBoxAdapter(child: _buildSessionsSection(hPad)),
                    const SliverToBoxAdapter(child: SizedBox(height: 96)),
                  ],
                ),
              ),

              // ── STG edit drawer backdrop ─────────────────────────────────
              if (_editingStg != null)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: _closeEdit,
                    behavior: HitTestBehavior.opaque,
                    child: const ColoredBox(
                      color: Color.fromRGBO(0, 0, 0, 0.30),
                    ),
                  ),
                ),

              // ── STG edit drawer panel ────────────────────────────────────
              if (_editingStg != null)
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: drawerWidth,
                  child: GestureDetector(
                    onTap: () {}, // absorb so backdrop doesn't fire
                    child: _EditPanel(
                      stg: _editingStg!,
                      onSave: _saveEdit,
                      onCancel: _closeEdit,
                    ),
                  ),
                ),

              // ── LTG edit drawer backdrop ─────────────────────────────────
              if (_editingLtg != null)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: _closeLtgEdit,
                    behavior: HitTestBehavior.opaque,
                    child: const ColoredBox(
                      color: Color.fromRGBO(0, 0, 0, 0.30),
                    ),
                  ),
                ),

              // ── LTG edit drawer panel ────────────────────────────────────
              if (_editingLtg != null)
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: drawerWidth,
                  child: GestureDetector(
                    onTap: () {}, // absorb so backdrop doesn't fire
                    child: _LtgEditPanel(
                      ltg: _editingLtg!,
                      onSave: _saveLtgEdit,
                      onCancel: _closeLtgEdit,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ── Client header ─────────────────────────────────────────────────────────────

  Widget _buildClientHeader(double hPad) {
    final client        = widget.client;
    final name          = client['name'] as String? ?? '';
    final age           = client['age'];
    final usesAac       = client['uses_aac'] == true;
    final diagnosis     = client['diagnosis'] as String?;
    final totalSessions = client['total_sessions'];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(hPad, 28, hPad, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                    if (usesAac) 'AAC user',
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

  // ── STG spine: LTG headers → ladder of STGs ──────────────────────────────────

  Widget _buildStgSpine(double hPad) {
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 28, hPad, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Goals',
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
          const SizedBox(height: 16),

          FutureBuilder<_SpineData>(
            future: _spineFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const _StgSkeleton();
              }
              if (snapshot.hasError) {
                return Text(
                  'Could not load goals.',
                  style: GoogleFonts.dmSans(color: _ghost, fontSize: 13),
                );
              }

              final data = snapshot.data!;

              // Group STGs by long_term_goal_id
              final stgsByLtg = <String, List<Map<String, dynamic>>>{};
              for (final stg in data.stgs) {
                final ltgId =
                    stg['long_term_goal_id'] as String? ?? '__orphan__';
                stgsByLtg.putIfAbsent(ltgId, () => []).add(stg);
              }

              final orphans = stgsByLtg['__orphan__'] ?? [];
              final groups  = <Widget>[];

              for (final ltg in data.ltgs) {
                final ltgId   = ltg['id'] as String;
                final ltgStgs = stgsByLtg[ltgId] ?? [];
                groups.add(_LtgGroup(
                  ltg: ltg,
                  stgs: ltgStgs,
                  expanded: _ltgExpanded[ltgId] ?? true,
                  onToggle: () => setState(() =>
                      _ltgExpanded[ltgId] = !(_ltgExpanded[ltgId] ?? true)),
                  onEditStg: _openEdit,
                  onEditLtg: () => _openLtgEdit(ltg),
                ));
              }

              // STGs not linked to any LTG
              if (orphans.isNotEmpty) {
                groups.add(
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _StgLadder(
                      stgs: orphans,
                      onEdit: _openEdit,
                    ),
                  ),
                );
              }

              if (groups.isEmpty) {
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
                        'No goals yet.',
                        style: GoogleFonts.dmSans(
                          color: _ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Use Generate Plan to create evidence-based goals.',
                        style: GoogleFonts.dmSans(
                          color: _ghost,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Column(children: groups);
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

}

// ── LTG group: collapsible header + STG ladder ────────────────────────────────

class _LtgGroup extends StatelessWidget {
  final Map<String, dynamic> ltg;
  final List<Map<String, dynamic>> stgs;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(Map<String, dynamic>) onEditStg;
  final VoidCallback onEditLtg;

  const _LtgGroup({
    required this.ltg,
    required this.stgs,
    required this.expanded,
    required this.onToggle,
    required this.onEditStg,
    required this.onEditLtg,
  });

  @override
  Widget build(BuildContext context) {
    // Actual column is goal_text (not description) — confirmed from schema
    final goalText = ltg['goal_text'] as String? ?? '';
    final domain   = ltg['domain'] as String? ?? ltg['category'] as String?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // LTG header: expand/collapse area + separate pencil icon
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Tap-to-toggle area (everything except pencil) ──────────
              Expanded(
                child: GestureDetector(
                  onTap: onToggle,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (domain != null) ...[
                        _Tag(domain),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          goalText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        size: 16,
                        color: _ghost,
                      ),
                    ],
                  ),
                ),
              ),
              // ── Pencil edit icon — separate hit area ─────────────────
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onEditLtg,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: _ghost,
                  ),
                ),
              ),
            ],
          ),

          if (expanded) ...[
            const SizedBox(height: 12),
            if (stgs.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 30, bottom: 4),
                child: Text(
                  'No STGs defined under this goal.',
                  style: GoogleFonts.dmSans(
                    color: _ghost,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              _StgLadder(stgs: stgs, onEdit: onEditStg),
          ],
        ],
      ),
    );
  }
}

// ── STG ladder: identifies step types, renders connected steps ────────────────

class _StgLadder extends StatelessWidget {
  final List<Map<String, dynamic>> stgs;
  final void Function(Map<String, dynamic>) onEdit;

  const _StgLadder({required this.stgs, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    // Determine step type per STG:
    //   mastered   → past (green filled node, muted text)
    //   first active encountered in sequence → current (navy border + node)
    //   active after first active → upcoming (outlined node, 50 % opacity)
    //   on_hold / discontinued / modified → 'other' (outlined node, ghost text)
    bool foundActive = false;
    final types = stgs.map((stg) {
      final status = stg['status'] as String? ?? 'active';
      if (status == 'mastered') return 'mastered';
      if (status == 'active' && !foundActive) {
        foundActive = true;
        return 'active';
      }
      if (status == 'active') return 'upcoming';
      return 'other';
    }).toList();

    return Column(
      children: List.generate(stgs.length, (i) {
        return _StgLadderStep(
          stg: stgs[i],
          stepType: types[i],
          isLast: i == stgs.length - 1,
          onTap: () => onEdit(stgs[i]),
        );
      }),
    );
  }
}

// ── Single ladder step: timeline node + card ──────────────────────────────────

class _StgLadderStep extends StatelessWidget {
  final Map<String, dynamic> stg;
  final String stepType; // 'active' | 'mastered' | 'upcoming' | 'other'
  final bool isLast;
  final VoidCallback onTap;

  const _StgLadderStep({
    required this.stg,
    required this.stepType,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive   = stepType == 'active';
    final isMastered = stepType == 'mastered';
    final isUpcoming = stepType == 'upcoming';

    // Node appearance
    final Color nodeColor = isMastered
        ? _green
        : (isActive ? _ink : _line);
    final bool nodeFilled = isMastered || isActive;

    // Card border
    final Color cardBorder = isActive ? _ink : _line;
    final double borderWidth = isActive ? 1.5 : 1.0;

    final behavior = _truncated();
    final supportLevelRaw = stg['current_cue_level'] as String?;
    final currentAccuracy = (stg['current_accuracy'] as num?)?.toDouble();

    final mc = stg['mastery_criterion'];
    final double targetPct =
        (mc is Map ? (mc['accuracy_pct'] as num?)?.toDouble() : null) ??
            (stg['target_accuracy'] as num?)?.toDouble() ??
            80.0;

    Widget step = GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: isUpcoming ? 0.5 : 1.0,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Timeline column ──────────────────────────────────────
              SizedBox(
                width: 20,
                child: Stack(
                  children: [
                    // Connecting line to next step
                    if (!isLast)
                      Positioned(
                        left: 9,
                        top: 26,
                        bottom: 0,
                        child: Container(width: 2, color: _line),
                      ),
                    // Step node
                    Positioned(
                      left: 6,
                      top: 14,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: nodeFilled ? nodeColor : _paper,
                          border: Border.all(color: nodeColor, width: 2),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // ── Card ─────────────────────────────────────────────────
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: cardBorder, width: borderWidth),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Goal text (truncated to 72 chars)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              behavior,
                              style: GoogleFonts.dmSans(
                                fontSize: 13,
                                fontWeight: isActive
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isMastered ? _ghost : _ink,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Support level (skip for mastered)
                      if (!isMastered && supportLevelRaw != null) ...[
                        const SizedBox(height: 6),
                        _DataChip(
                          icon: Icons.touch_app_outlined,
                          label: _supportLabel(supportLevelRaw),
                        ),
                      ],

                      // Accuracy progress bar (skip for mastered / upcoming)
                      if (!isMastered &&
                          !isUpcoming &&
                          currentAccuracy != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: (currentAccuracy / 100)
                                      .clamp(0.0, 1.0),
                                  minHeight: 4,
                                  backgroundColor: _line,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    currentAccuracy >= targetPct
                                        ? _green
                                        : _teal,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${currentAccuracy.toStringAsFixed(0)}%',
                              style: GoogleFonts.dmSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _ink,
                              ),
                            ),
                            Text(
                              ' / ${targetPct.toStringAsFixed(0)}%',
                              style:
                                  GoogleFonts.dmSans(fontSize: 11, color: _ghost),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return step;
  }

  String _truncated() {
    final tb = stg['target_behavior'] as String?;
    final raw = (tb != null && tb.isNotEmpty)
        ? tb
        : (stg['specific'] as String? ?? 'Untitled goal');
    return raw.length > 72 ? '${raw.substring(0, 72)}…' : raw;
  }

  static String _supportLabel(String raw) => switch (raw) {
        'independent'    => 'Independent',
        'minimal'        => 'Minimal support',
        'moderate'       => 'Moderate support',
        'maximal'        => 'Maximal support',
        'hand_over_hand' => 'Hand-over-hand',
        _                => raw,
      };
}

// ── Skeleton placeholder shown while spine loads ──────────────────────────────

class _StgSkeleton extends StatelessWidget {
  const _StgSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        2,
        (_) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: 90,
          decoration: BoxDecoration(
            color: _paper2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _line),
          ),
        ),
      ),
    );
  }
}

// ── Edit panel (right-side drawer) ───────────────────────────────────────────

class _EditPanel extends StatefulWidget {
  final Map<String, dynamic> stg;
  final Future<void> Function(String id, Map<String, dynamic> updates) onSave;
  final VoidCallback onCancel;

  const _EditPanel({
    required this.stg,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<_EditPanel> createState() => _EditPanelState();
}

class _EditPanelState extends State<_EditPanel> {
  late TextEditingController _behaviorCtrl;
  late TextEditingController _contextCtrl;
  late String? _supportLevel;
  late String _status;
  late TextEditingController _accuracyCtrl;
  late TextEditingController _consecutiveCtrl;
  late TextEditingController _trialsCtrl;
  bool _saving = false;

  static const _supportLevels = <String?>[
    null,
    'independent',
    'minimal',
    'moderate',
    'maximal',
    'hand_over_hand',
  ];

  static const _statuses = <String>[
    'active',
    'on_hold',
    'modified',
    'discontinued',
    'mastered',
  ];

  @override
  void initState() {
    super.initState();
    final stg = widget.stg;
    // target_behavior: pre-migration rows have null — fall back to 'specific'
    final tb = stg['target_behavior'] as String?;
    _behaviorCtrl = TextEditingController(
        text: (tb != null && tb.isNotEmpty)
            ? tb
            : (stg['specific'] as String? ?? ''));
    _contextCtrl =
        TextEditingController(text: stg['context'] as String? ?? '');
    _supportLevel = stg['current_cue_level'] as String?;
    _status   = stg['status'] as String? ?? 'active';

    final mc = stg['mastery_criterion'];
    // accuracy_pct: fall back to target_accuracy when mastery_criterion is null
    _accuracyCtrl    = TextEditingController(
      text: mc is Map
          ? (mc['accuracy_pct'] as num?)?.toString() ?? '80'
          : (stg['target_accuracy'] as num?)?.toString() ?? '80',
    );
    _consecutiveCtrl = TextEditingController(
      text: mc is Map
          ? (mc['consecutive_sessions'] as num?)?.toString() ?? '3'
          : '3',
    );
    _trialsCtrl      = TextEditingController(
      text: mc is Map
          ? (mc['trials_per_session'] as num?)?.toString() ?? '10'
          : '10',
    );
  }

  @override
  void dispose() {
    _behaviorCtrl.dispose();
    _contextCtrl.dispose();
    _accuracyCtrl.dispose();
    _consecutiveCtrl.dispose();
    _trialsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: _line)),
      ),
      child: Column(
        children: [
          // ── Header ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
            child: Row(
              children: [
                Text(
                  'Edit Goal',
                  style: GoogleFonts.syne(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: _ghost),
                  onPressed: widget.onCancel,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          Container(height: 1, color: _line),

          // ── Form ──────────────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Target behavior
                  _fieldLabel('Target behavior'),
                  const SizedBox(height: 6),
                  _multiLineField(_behaviorCtrl, minLines: 3, maxLines: 6),
                  const SizedBox(height: 18),

                  // Context
                  _fieldLabel('Context'),
                  const SizedBox(height: 6),
                  _multiLineField(_contextCtrl, minLines: 2, maxLines: 4),
                  const SizedBox(height: 18),

                  // Support level (§6.3)
                  _fieldLabel('Current support level (§6.3)'),
                  const SizedBox(height: 6),
                  _buildSupportLevelDropdown(),
                  const SizedBox(height: 18),

                  // Mastery criterion
                  _fieldLabel('Mastery criterion'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _labeledNumField(
                            _accuracyCtrl, 'Accuracy %'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _labeledNumField(
                            _consecutiveCtrl, 'Consecutive'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _labeledNumField(
                            _trialsCtrl, 'Trials / session'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Status (§6.6)
                  _fieldLabel('Status (§6.6)'),
                  const SizedBox(height: 6),
                  _buildStatusDropdown(),

                  // Mastered warning — §10 invariant
                  if (_status == 'mastered') ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color.fromRGBO(214, 138, 43, 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color.fromRGBO(214, 138, 43, 0.35),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.warning_amber_outlined,
                            size: 14,
                            color: _amber,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Mastered status requires clinician '
                              'confirmation. AI will never auto-set this.',
                              style: GoogleFonts.dmSans(
                                fontSize: 12,
                                color: _amber,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),

          // ── Footer ────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _ghost,
                      side: const BorderSide(color: _line),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text('Cancel', style: GoogleFonts.dmSans()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _onSave,
                    style: FilledButton.styleFrom(
                      backgroundColor: _ink,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text('Save', style: GoogleFonts.dmSans()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onSave() async {
    setState(() => _saving = true);
    final updates = <String, dynamic>{
      'target_behavior': _behaviorCtrl.text.trim(),
      'context': _contextCtrl.text.trim(),
      'current_cue_level': _supportLevel,
      'status': _status,
      'mastery_criterion': {
        'accuracy_pct':
            int.tryParse(_accuracyCtrl.text.trim()) ?? 80,
        'consecutive_sessions':
            int.tryParse(_consecutiveCtrl.text.trim()) ?? 3,
        'trials_per_session':
            int.tryParse(_trialsCtrl.text.trim()) ?? 10,
      },
      if (_status == 'mastered')
        'mastered_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      await widget.onSave(widget.stg['id'].toString(), updates);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not save: $e',
              style: GoogleFonts.dmSans(),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Form helpers ──────────────────────────────────────────────────────

  Widget _fieldLabel(String text) => Text(
        text,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _ghost,
          letterSpacing: 0.3,
        ),
      );

  InputDecoration _inputDecoration() => InputDecoration(
        filled: true,
        fillColor: _paper,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _ink),
        ),
      );

  Widget _multiLineField(
    TextEditingController ctrl, {
    int minLines = 1,
    int maxLines = 4,
  }) =>
      TextField(
        controller: ctrl,
        minLines: minLines,
        maxLines: maxLines,
        style: GoogleFonts.dmSans(fontSize: 13, color: _ink),
        decoration: _inputDecoration(),
      );

  Widget _labeledNumField(TextEditingController ctrl, String label) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.dmSans(fontSize: 10, color: _ghost),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: GoogleFonts.dmSans(fontSize: 13, color: _ink),
            decoration: _inputDecoration(),
          ),
        ],
      );

  // Use DropdownButton (not DropdownButtonFormField) to avoid the deprecated
  // FormField.value parameter introduced in Flutter 3.33.
  Widget _buildSupportLevelDropdown() => _styledDropdown<String?>(
        value: _supportLevel,
        items: _supportLevels,
        labelOf: (v) => v == null ? '— not set —' : _supportLevelLabel(v),
        onChanged: (v) => setState(() => _supportLevel = v),
      );

  Widget _buildStatusDropdown() => _styledDropdown<String>(
        value: _status,
        items: _statuses,
        labelOf: _statusLabel,
        onChanged: (v) => setState(() => _status = v ?? 'active'),
      );

  Widget _styledDropdown<T>({
    required T value,
    required List<T> items,
    required String Function(T) labelOf,
    required void Function(T?) onChanged,
  }) =>
      Container(
        decoration: BoxDecoration(
          color: _paper,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _line),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            dropdownColor: Colors.white,
            borderRadius: BorderRadius.circular(6),
            style: GoogleFonts.dmSans(fontSize: 13, color: _ink),
            items: items
                .map((v) => DropdownMenuItem<T>(
                      value: v,
                      child: Text(
                        labelOf(v),
                        style: GoogleFonts.dmSans(fontSize: 13, color: _ink),
                      ),
                    ))
                .toList(),
            onChanged: onChanged,
          ),
        ),
      );

  static String _supportLevelLabel(String v) => switch (v) {
        'independent'    => 'Independent',
        'minimal'        => 'Minimal support',
        'moderate'       => 'Moderate support',
        'maximal'        => 'Maximal support',
        'hand_over_hand' => 'Hand-over-hand',
        _                => v,
      };

  static String _statusLabel(String v) => switch (v) {
        'active'       => 'Active',
        'mastered'     => 'Mastered',
        'on_hold'      => 'On hold',
        'discontinued' => 'Discontinued',
        'modified'     => 'Modified',
        _              => v,
      };
}

// ── LTG edit panel (right-side drawer) ───────────────────────────────────────

class _LtgEditPanel extends StatefulWidget {
  final Map<String, dynamic> ltg;
  final Future<void> Function(String id, Map<String, dynamic> updates) onSave;
  final VoidCallback onCancel;

  const _LtgEditPanel({
    required this.ltg,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<_LtgEditPanel> createState() => _LtgEditPanelState();
}

class _LtgEditPanelState extends State<_LtgEditPanel> {
  late TextEditingController _goalTextCtrl;
  late String? _domain;
  late String? _framework;
  late String  _status;
  DateTime?    _targetDate;
  bool _saving = false;

  // §6.4 Domain controlled vocabulary
  static const _domains = <String?>[
    null,
    'articulation',
    'phonology',
    'expressive_language',
    'receptive_language',
    'pragmatics',
    'fluency',
    'voice',
    'motor_speech',
    'feeding_swallowing',
    'AAC_operational',
    'AAC_linguistic',
    'AAC_social',
    'literacy',
    'cognitive_communication',
  ];

  // §6.5 Framework controlled vocabulary
  static const _frameworks = <String?>[
    null,
    'PROMPT',
    'OPT',
    'AAC',
    'NLA',
    'DIR',
    'Hanen',
    'PECS',
    'Core_Word',
    'Motor_Speech',
    'Phonological_Process',
    'Interoception_Informed',
    'Polyvagal_Informed',
    'Other',
  ];

  // LTG status vocabulary
  static const _statuses = <String>[
    'active',
    'met',
    'modified',
    'discontinued',
  ];

  @override
  void initState() {
    super.initState();
    final ltg = widget.ltg;
    _goalTextCtrl = TextEditingController(
        text: ltg['goal_text'] as String? ?? '');
    _domain    = ltg['domain'] as String?;
    _framework = ltg['framework'] as String?;
    _status    = ltg['status'] as String? ?? 'active';
    final td   = ltg['target_date'] as String?;
    _targetDate = td != null ? DateTime.tryParse(td) : null;
  }

  @override
  void dispose() {
    _goalTextCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: _line)),
      ),
      child: Column(
        children: [
          // ── Header ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
            child: Row(
              children: [
                Text(
                  'Edit Long-Term Goal',
                  style: GoogleFonts.syne(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: _ghost),
                  onPressed: widget.onCancel,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          Container(height: 1, color: _line),

          // ── Form ──────────────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Goal text
                  _fieldLabel('Goal description'),
                  const SizedBox(height: 6),
                  _multiLineField(_goalTextCtrl, minLines: 3, maxLines: 7),
                  const SizedBox(height: 18),

                  // Domain (§6.4)
                  _fieldLabel('Domain (§6.4)'),
                  const SizedBox(height: 6),
                  _styledDropdown<String?>(
                    value: _domain,
                    items: _domains,
                    labelOf: (v) => v == null ? '— not set —' : _domainLabel(v),
                    onChanged: (v) => setState(() => _domain = v),
                  ),
                  const SizedBox(height: 18),

                  // Framework (§6.5)
                  _fieldLabel('Framework (§6.5)'),
                  const SizedBox(height: 6),
                  _styledDropdown<String?>(
                    value: _framework,
                    items: _frameworks,
                    labelOf: (v) =>
                        v == null ? '— not set —' : _frameworkLabel(v),
                    onChanged: (v) => setState(() => _framework = v),
                  ),
                  const SizedBox(height: 18),

                  // Target date (nullable date picker)
                  _fieldLabel('Target date'),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 11),
                      decoration: BoxDecoration(
                        color: _paper,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _line),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _targetDate != null
                                  ? '${_targetDate!.day.toString().padLeft(2, '0')}/'
                                    '${_targetDate!.month.toString().padLeft(2, '0')}/'
                                    '${_targetDate!.year}'
                                  : '— not set —',
                              style: GoogleFonts.dmSans(
                                fontSize: 13,
                                color:
                                    _targetDate != null ? _ink : _ghost,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 14,
                            color: _ghost,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_targetDate != null) ...[
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () => setState(() => _targetDate = null),
                      child: Text(
                        'Clear date',
                        style: GoogleFonts.dmSans(
                            fontSize: 12, color: _ghost),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),

                  // Status
                  _fieldLabel('Status'),
                  const SizedBox(height: 6),
                  _styledDropdown<String>(
                    value: _status,
                    items: _statuses,
                    labelOf: _statusLabel,
                    onChanged: (v) => setState(() => _status = v ?? 'active'),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),

          // ── Footer ────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _ghost,
                      side: const BorderSide(color: _line),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text('Cancel', style: GoogleFonts.dmSans()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _onSave,
                    style: FilledButton.styleFrom(
                      backgroundColor: _ink,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text('Save', style: GoogleFonts.dmSans()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _ink,
            onPrimary: Colors.white,
            surface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _targetDate = picked);
  }

  Future<void> _onSave() async {
    setState(() => _saving = true);
    final updates = <String, dynamic>{
      'goal_text':    _goalTextCtrl.text.trim(),
      'domain':       _domain,
      'framework':    _framework,
      'status':       _status,
      'target_date':  _targetDate?.toIso8601String().split('T').first,
    };
    try {
      await widget.onSave(widget.ltg['id'].toString(), updates);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not save: $e',
              style: GoogleFonts.dmSans(),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Form helpers (mirrors _EditPanel helpers) ─────────────────────────

  Widget _fieldLabel(String text) => Text(
        text,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _ghost,
          letterSpacing: 0.3,
        ),
      );

  InputDecoration _inputDecoration() => InputDecoration(
        filled: true,
        fillColor: _paper,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _ink),
        ),
      );

  Widget _multiLineField(
    TextEditingController ctrl, {
    int minLines = 1,
    int maxLines = 4,
  }) =>
      TextField(
        controller: ctrl,
        minLines: minLines,
        maxLines: maxLines,
        style: GoogleFonts.dmSans(fontSize: 13, color: _ink),
        decoration: _inputDecoration(),
      );

  Widget _styledDropdown<T>({
    required T value,
    required List<T> items,
    required String Function(T) labelOf,
    required void Function(T?) onChanged,
  }) =>
      Container(
        decoration: BoxDecoration(
          color: _paper,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _line),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            dropdownColor: Colors.white,
            borderRadius: BorderRadius.circular(6),
            style: GoogleFonts.dmSans(fontSize: 13, color: _ink),
            items: items
                .map((v) => DropdownMenuItem<T>(
                      value: v,
                      child: Text(
                        labelOf(v),
                        style: GoogleFonts.dmSans(fontSize: 13, color: _ink),
                      ),
                    ))
                .toList(),
            onChanged: onChanged,
          ),
        ),
      );

  static String _domainLabel(String v) => switch (v) {
        'articulation'          => 'Articulation',
        'phonology'             => 'Phonology',
        'expressive_language'   => 'Expressive Language',
        'receptive_language'    => 'Receptive Language',
        'pragmatics'            => 'Pragmatics',
        'fluency'               => 'Fluency',
        'voice'                 => 'Voice',
        'motor_speech'          => 'Motor Speech',
        'feeding_swallowing'    => 'Feeding & Swallowing',
        'AAC_operational'       => 'AAC — Operational',
        'AAC_linguistic'        => 'AAC — Linguistic',
        'AAC_social'            => 'AAC — Social',
        'literacy'              => 'Literacy',
        'cognitive_communication' => 'Cognitive-Communication',
        _                       => v,
      };

  static String _frameworkLabel(String v) => switch (v) {
        'PROMPT'                  => 'PROMPT',
        'OPT'                     => 'OPT',
        'AAC'                     => 'AAC',
        'NLA'                     => 'NLA',
        'DIR'                     => 'DIR / Floortime',
        'Hanen'                   => 'Hanen',
        'PECS'                    => 'PECS',
        'Core_Word'               => 'Core Word',
        'Motor_Speech'            => 'Motor Speech',
        'Phonological_Process'    => 'Phonological Process',
        'Interoception_Informed'  => 'Interoception-Informed',
        'Polyvagal_Informed'      => 'Polyvagal-Informed',
        'Other'                   => 'Other',
        _                         => v,
      };

  static String _statusLabel(String v) => switch (v) {
        'active'       => 'Active',
        'met'          => 'Met',
        'modified'     => 'Modified',
        'discontinued' => 'Discontinued',
        _              => v,
      };
}

// ── Shared small widgets ──────────────────────────────────────────────────────

class _Tag extends StatelessWidget {
  final String label;
  const _Tag(this.label);

  @override
  Widget build(BuildContext context) => Container(
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

class _DataChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _DataChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: _ghost),
          const SizedBox(width: 4),
          Text(label,
              style: GoogleFonts.dmSans(fontSize: 12, color: _ghost)),
        ],
      );
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _HeaderButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
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

class _SessionCard extends StatelessWidget {
  final Map<String, dynamic> session;
  final String clientId;
  final String clientName;
  const _SessionCard(
      {required this.session,
      required this.clientId,
      required this.clientName});

  @override
  Widget build(BuildContext context) {
    final dateStr = session['date'] as String? ?? '';
    final notes   = session['notes'] as String?;

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
                        (session as Map).entries.map(
                            (e) => MapEntry(e.key.toString(), e.value)),
                      ),
                      clientName: clientName,
                      clientId: clientId,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome, size: 14, color: _teal),
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

