import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/cue_theme.dart';
import 'add_client_screen.dart';
import 'client_profile_screen.dart';
import 'login_screen.dart';
import 'narrator_screen.dart';

class ClientRosterScreen extends StatefulWidget {
  const ClientRosterScreen({super.key});

  @override
  State<ClientRosterScreen> createState() => _ClientRosterScreenState();
}

class _ClientRosterScreenState extends State<ClientRosterScreen> {
  final _supabase = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _clientsFuture;

  @override
  void initState() {
    super.initState();
    _clientsFuture = _fetchClients();
  }

  Future<List<Map<String, dynamic>>> _fetchClients() async {
    final response = await _supabase
        .from('clients')
        .select()
        .order('name', ascending: true);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> _openAddClient() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddClientScreen()),
    );
    if (added == true) setState(() => _clientsFuture = _fetchClients());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CueColors.softWhite,
      appBar: AppBar(
        title: Text('My Clients',
            style: GoogleFonts.dmSans(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
        backgroundColor: CueColors.inkNavy,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.mic_rounded),
            tooltip: 'Narrator',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NarratorScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (_) => false,
                );
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddClient,
        backgroundColor: CueColors.signalTeal,
        foregroundColor: Colors.white,
        tooltip: 'Add client',
        child: const Icon(Icons.person_add_outlined),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _clientsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: CueColors.signalTeal));
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final clients = snapshot.data!;

          if (clients.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_outline,
                      size: 56, color: CueColors.textMid.withOpacity(0.4)),
                  const SizedBox(height: 16),
                  Text('No clients yet',
                      style: GoogleFonts.dmSerifDisplay(
                          fontSize: 20, color: CueColors.textMid)),
                  const SizedBox(height: 8),
                  Text('Tap + to add your first client',
                      style: GoogleFonts.dmSans(
                          fontSize: 14, color: CueColors.textMid)),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
            itemCount: clients.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final client = clients[index];
              final name = client['name'] as String? ?? '?';
              final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
              final age = client['age'];
              final sessions = client['total_sessions'] ?? 0;
              final usesAac = client['uses_aac'] == true;

              return _AnimatedItem(
                index: index,
                child: _ClientCard(
                  name: name,
                  initial: initial,
                  age: age,
                  sessions: sessions,
                  usesAac: usesAac,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ClientProfileScreen(client: client),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ── Staggered entrance animation ─────────────────────────────────────────────
class _AnimatedItem extends StatefulWidget {
  final int index;
  final Widget child;

  const _AnimatedItem({required this.index, required this.child});

  @override
  State<_AnimatedItem> createState() => _AnimatedItemState();
}

class _AnimatedItemState extends State<_AnimatedItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    Future.delayed(Duration(milliseconds: widget.index * 60), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, (1.0 - _ctrl.value) * 8),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

class _ClientCard extends StatelessWidget {
  final String name;
  final String initial;
  final dynamic age;
  final dynamic sessions;
  final bool usesAac;
  final VoidCallback onTap;

  const _ClientCard({
    required this.name,
    required this.initial,
    required this.age,
    required this.sessions,
    required this.usesAac,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: CueColors.surfaceWhite,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: CueColors.inkNavy.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                color: Color(0xFF2D4169),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  initial,
                  style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Name + chips
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.dmSerifDisplay(
                      fontSize: 16,
                      color: CueColors.inkNavy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (age != null) _Chip(label: 'Age $age', color: CueColors.signalTeal),
                      if (age != null) const SizedBox(width: 6),
                      _Chip(
                        label: '$sessions ${sessions == 1 ? 'session' : 'sessions'}',
                        color: CueColors.signalTeal,
                      ),
                      if (usesAac) ...[
                        const SizedBox(width: 6),
                        _Chip(label: 'AAC', color: CueColors.warmAmber, dark: true),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Chevron
            Icon(Icons.chevron_right_rounded,
                color: CueColors.textMid, size: 22),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final bool dark;

  const _Chip({required this.label, required this.color, this.dark = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(dark ? 1 : 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: dark ? Colors.white : color,
        ),
      ),
    );
  }
}
