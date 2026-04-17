import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_layout.dart';
import 'report_screen.dart';
import 'add_session_screen.dart';
import 'narrate_session_screen.dart';

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
    if (added == true) {
      setState(() => _sessionsFuture = _fetchSessions());
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
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;

    return AppLayout(
      title: client['name'],
      activeRoute: 'roster',
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'narrate_fab',
            onPressed: _openNarrateSession,
            backgroundColor: const Color(0xFF00695C),
            foregroundColor: Colors.white,
            tooltip: 'Narrate Session',
            child: const Icon(Icons.mic_rounded),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'add_session_fab',
            onPressed: _openAddSession,
            backgroundColor: const Color(0xFF00897B),
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add),
            label: const Text('Add Session'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Client info card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
            color: Colors.white,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: Colors.teal.shade100,
                  child: Text(
                    client['name'][0].toUpperCase(),
                    style: TextStyle(
                      fontSize: 26,
                      color: Colors.teal.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        client['name'],
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Age ${client['age']} · ${client['uses_aac'] == true ? 'AAC user' : 'No AAC'}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _statChip('${client['total_sessions']}', 'Sessions'),
                          if (client['diagnosis'] != null &&
                              (client['diagnosis'] as String).isNotEmpty) ...[
                            const SizedBox(width: 12),
                            _statChip(client['diagnosis'], 'Diagnosis'),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Sessions section
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(48, 24, 48, 12),
                  child: Text(
                    'Session History',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ),
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: _sessionsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return Center(
                            child: Text('Error: ${snapshot.error}'));
                      }

                      final sessions = snapshot.data!;

                      if (sessions.isEmpty) {
                        return const Center(
                            child: Text('No sessions yet.'));
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 48, vertical: 0),
                        itemCount: sessions.length,
                        itemBuilder: (context, index) {
                          final session = sessions[index];
                          return Card(
                            margin:
                                const EdgeInsets.only(bottom: 12),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                  color: Colors.grey.shade200),
                            ),
                            color: Colors.white,
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        session['date'] ?? '',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                          color: Color(0xFF1A1A2E),
                                        ),
                                      ),
                                      if (session['duration_minutes'] !=
                                          null)
                                        Container(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.teal.shade50,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            '${session['duration_minutes']} min',
                                            style: TextStyle(
                                              color: Colors.teal.shade700,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (session['notes'] != null &&
                                      (session['notes'] as String)
                                          .isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      session['notes'],
                                      style: TextStyle(
                                        color: Colors.grey.shade700,
                                        fontSize: 14,
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => ReportScreen(
                                              session: Map<String,
                                                  dynamic>.fromEntries(
                                                (session as Map)
                                                    .entries
                                                    .map((e) => MapEntry(
                                                        e.key.toString(),
                                                        e.value)),
                                              ),
                                              clientName:
                                                  (widget.client['name'] ??
                                                          '')
                                                      .toString(),
                                            ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(
                                          Icons.auto_awesome,
                                          size: 16),
                                      label:
                                          const Text('Generate Report'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.teal,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statChip(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold)),
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}
