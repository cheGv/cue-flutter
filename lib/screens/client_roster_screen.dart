import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_layout.dart';
import 'add_client_screen.dart';
import 'client_profile_screen.dart';

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

  Future<List<Map<String, dynamic>>> _fetchClients() async {
    final response = await _supabase
        .from('clients')
        .select()
        .isFilter('deleted_at', null)
        .order('name', ascending: true);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> _confirmDeleteClient(Map<String, dynamic> client) async {
    final clientName = client['name'] as String;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove client?'),
        content: Text(
          'This will remove $clientName from your roster. '
          'You can contact support to recover this record.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _supabase
          .from('clients')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', client['id']);

      setState(() {
        _clientsFuture = _fetchClients();
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$clientName removed from roster.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not remove client. Please try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: 'My Clients',
      activeRoute: 'roster',
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddClient,
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        tooltip: 'Add client',
        child: const Icon(Icons.person_add_outlined),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _clientsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
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
                  Icon(Icons.people_outline_rounded,
                      size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text(
                    'No clients yet',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add your first client using the + button.',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                  ),
                ],
              ),
            );
          }

          return _buildTable(clients);
        },
      ),
    );
  }

  Widget _buildTable(List<Map<String, dynamic>> clients) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Table header
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 48, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border:
                Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: const [
              Expanded(flex: 3, child: _HeaderCell('CLIENT')),
              Expanded(flex: 1, child: _HeaderCell('AGE')),
              Expanded(flex: 1, child: _HeaderCell('SESSIONS')),
              Expanded(flex: 2, child: _HeaderCell('COMMUNICATION')),
              SizedBox(width: 96),
            ],
          ),
        ),
        // Table rows
        Expanded(
          child: ListView.builder(
            itemCount: clients.length,
            itemBuilder: (ctx, i) => _ClientRow(
              client: clients[i],
              onDelete: () => _confirmDeleteClient(clients[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  const _HeaderCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Color(0xFF8A94A6),
        letterSpacing: 0.8,
      ),
    );
  }
}

class _ClientRow extends StatelessWidget {
  final Map<String, dynamic> client;
  final VoidCallback onDelete;

  const _ClientRow({required this.client, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final modality = client['communication_modality']?.toString() ?? '';
    final usesAac = client['uses_aac'] == true;

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ClientProfileScreen(client: client),
        ),
      ),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 48, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          border:
              Border(bottom: BorderSide(color: Colors.grey.shade100)),
        ),
        child: Row(
          children: [
            // Name + avatar
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.teal.shade100,
                    child: Text(
                      client['name'][0].toUpperCase(),
                      style: TextStyle(
                        color: Colors.teal.shade800,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    client['name'],
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                ],
              ),
            ),
            // Age
            Expanded(
              flex: 1,
              child: Text(
                '${client['age']}',
                style: const TextStyle(
                    fontSize: 14, color: Color(0xFF5A6475)),
              ),
            ),
            // Sessions
            Expanded(
              flex: 1,
              child: Text(
                '${client['total_sessions']}',
                style: const TextStyle(
                    fontSize: 14, color: Color(0xFF5A6475)),
              ),
            ),
            // Communication
            Expanded(
              flex: 2,
              child: usesAac
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      constraints: const BoxConstraints(maxWidth: 56),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.teal.shade200),
                      ),
                      child: Text(
                        'AAC',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.teal.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : Text(
                      modality.isNotEmpty ? modality : '—',
                      style: const TextStyle(
                          fontSize: 14, color: Color(0xFF5A6475)),
                    ),
            ),
            // Actions
            SizedBox(
              width: 96,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Remove client',
                    iconSize: 20,
                    color: Colors.grey.shade400,
                    onPressed: onDelete,
                  ),
                  Icon(Icons.chevron_right,
                      color: Colors.grey.shade400, size: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
