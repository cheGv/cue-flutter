import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;

class ReportScreen extends StatefulWidget {
  final Map<String, dynamic> session;
  final String clientName;

  const ReportScreen({
    super.key,
    required this.session,
    required this.clientName,
  });

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  static const _proxyUrl =
      'https://cue-ai-proxy.onrender.com/generate-report';

  bool _isLoading = false;
  String? _report;
  String? _error;

  Future<void> _generateReport() async {
    setState(() { _isLoading = true; _error = null; _report = null; });
    try {
      final s = widget.session;
      final date = '${s['date'] ?? ''}';
      final goal = '${s['target_behaviour'] ?? ''}';
      final activity = '${s['activity_name'] ?? ''}';
      final attempts = '${s['attempts'] ?? 0}';
      final independent = '${s['independent_responses'] ?? 0}';
      final prompted = '${s['prompted_responses'] ?? 0}';
      final goalMet = '${s['goal_met'] ?? ''}';
      final affect = '${s['client_affect'] ?? ''}';
      final notes = '${s['next_session_focus'] ?? ''}';
      final name = '${widget.clientName}';

      final bodyString = '{"clientName":"$name","session":{"date":"$date","goal":"$goal","activity":"$activity","totalTrials":"$attempts","independentTrials":"$independent","promptedTrials":"$prompted","goalMet":"$goalMet","affect":"$affect","notes":"$notes"}}';

      final response = await http.post(
        Uri.parse(_proxyUrl),
        headers: {'Content-Type': 'application/json'},
        body: bodyString,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['content']?[0]?['text'] ?? data['report'] ?? response.body;
        setState(() { _report = text.toString(); });
      } else {
        setState(() { _error = 'Server error ${response.statusCode}: ${response.body}'; });
      }
    } catch (e) {
      setState(() { _error = 'Failed to connect to AI service: $e'; });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;

    return Scaffold(
      appBar: AppBar(
        title: Text('Report – ${widget.clientName}'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Session summary card
            Card(
              color: Colors.teal.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Session: ${session['date'] ?? 'Unknown date'}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (session['target_behaviour'] != null &&
                        (session['target_behaviour'] as String).isNotEmpty)
                      _summaryRow(
                          'Goal', session['target_behaviour'] as String),
                    if (session['activity_name'] != null &&
                        (session['activity_name'] as String).isNotEmpty)
                      _summaryRow(
                          'Activity', session['activity_name'] as String),
                    _summaryRow(
                      'Trials',
                      '${session['attempts'] ?? 0} attempts · '
                          '${session['independent_responses'] ?? 0} independent · '
                          '${session['prompted_responses'] ?? 0} prompted',
                    ),
                    _summaryRow('Goal Met',
                        _formatGoalMet(session['goal_met'] as String?)),
                    _summaryRow('Affect',
                        _capitalize(session['client_affect'] as String?)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Generate button
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isLoading ? null : _generateReport,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.teal,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(
                  _isLoading ? 'Generating…' : 'Generate Report',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Error
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: Colors.red.shade800, fontSize: 14),
                ),
              ),

            // Report output
            if (_report != null) ...[
              Text(
                'AI Report',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.teal.shade100),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: MarkdownBody(
                  data: _report!,
                  styleSheet: MarkdownStyleSheet(
                    p: const TextStyle(fontSize: 14, height: 1.6),
                    h1: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                    h2: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                    h3: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.teal.shade700),
            ),
          ),
          Expanded(
            child: Text(value,
                style:
                    TextStyle(fontSize: 13, color: Colors.grey.shade800)),
          ),
        ],
      ),
    );
  }

  String _formatGoalMet(String? value) {
    switch (value) {
      case 'yes':
        return 'Yes';
      case 'partially':
        return 'Partially';
      case 'not_yet':
        return 'Not Yet';
      default:
        return value ?? '—';
    }
  }

  String _capitalize(String? value) {
    if (value == null || value.isEmpty) return '—';
    return value[0].toUpperCase() + value.substring(1);
  }
}
