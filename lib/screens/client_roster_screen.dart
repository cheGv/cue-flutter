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

class _ClientRosterScreenState extends State<ClientRosterScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _clientsFuture;
  late AnimationController _fadeCtrl;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _clientsFuture = _fetchClients();
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
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
    if (added == true) {
      setState(() {
        _clientsFuture = _fetchClients();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CueColors.background,
      appBar: AppBar(
        title: Text(
          'Clients',
          style: GoogleFonts.fraunces(
            fontSize: 24,
            fontWeight: FontWeight.w500,
            color: CueColors.inkPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.mic_none_rounded),
            tooltip: 'Narrator',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NarratorScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
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
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddClient,
        backgroundColor: CueColors.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: Text(
          'Add Client',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: FadeTransition(
        opacity: CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _clientsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                  color: CueColors.accent,
                  strokeWidth: 2,
                ),
              );
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Error: ${snapshot.error}',
                  style: GoogleFonts.inter(color: CueColors.inkSecondary),
                ),
              );
            }

            final clients = snapshot.data!;

            if (clients.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'No clients yet',
                      style: GoogleFonts.fraunces(
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                        color: CueColors.inkPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap  +  to add your first client',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: CueColors.inkSecondary,
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(0, 32, 0, 120),
              itemCount: clients.length,
              separatorBuilder: (_, __) => const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: CueColors.divider,
                ),
              ),
              itemBuilder: (context, index) {
                final client = clients[index];
                return _ClientRow(
                  client: client,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ClientProfileScreen(client: client),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ClientRow extends StatelessWidget {
  final Map<String, dynamic> client;
  final VoidCallback onTap;

  const _ClientRow({required this.client, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = client['name'] as String? ?? '?';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final age = client['age'];
    final sessions = client['total_sessions'] ?? 0;
    final usesAac = client['uses_aac'] == true;

    final subParts = <String>[];
    if (age != null) subParts.add('Age $age');
    subParts.add('$sessions ${sessions == 1 ? 'session' : 'sessions'}');
    final subtitle = subParts.join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Text(
                initial,
                style: GoogleFonts.fraunces(
                  fontSize: 32,
                  fontWeight: FontWeight.w400,
                  color: CueColors.inkPrimary,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: GoogleFonts.fraunces(
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                            color: CueColors.inkPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (usesAac) ...[
                        const SizedBox(width: 8),
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
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: CueColors.inkSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: CueColors.inkTertiary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
