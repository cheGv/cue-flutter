import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../widgets/app_layout.dart';

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
    setState(() {
      _isLoading = true;
      _error = null;
      _report = null;
    });
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
      final name = widget.clientName;

      final bodyString =
          '{"clientName":"$name","session":{"date":"$date","goal":"$goal","activity":"$activity","totalTrials":"$attempts","independentTrials":"$independent","promptedTrials":"$prompted","goalMet":"$goalMet","affect":"$affect","notes":"$notes"}}';

      final response = await http.post(
        Uri.parse(_proxyUrl),
        headers: {'Content-Type': 'application/json'},
        body: bodyString,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text =
            data['content']?[0]?['text'] ?? data['report'] ?? response.body;
        setState(() {
          _report = text.toString();
        });
      } else {
        setState(() {
          _error =
              'Server error ${response.statusCode}: ${response.body}';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to connect to AI service: $e';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _downloadPdf() async {
    final session = widget.session;
    final sessionDate = '${session['date'] ?? '—'}';
    final now = DateTime.now();
    final generatedDate =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final cleanText = _cleanText(_report ?? '');

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (context) => [
          pw.Container(
            width: double.infinity,
            color: PdfColors.teal,
            padding: const pw.EdgeInsets.fromLTRB(40, 20, 40, 18),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Cue AI',
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  'Clinical Session Report',
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.white),
                ),
              ],
            ),
          ),
          pw.Container(
            width: double.infinity,
            color: PdfColors.teal50,
            padding: const pw.EdgeInsets.fromLTRB(40, 10, 40, 10),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Client: ${widget.clientName}',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'Session Date: $sessionDate',
                  style: const pw.TextStyle(
                      fontSize: 11, color: PdfColors.grey700),
                ),
              ],
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(40, 24, 40, 24),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: _buildPdfSections(cleanText),
            ),
          ),
        ],
        footer: (context) => pw.Container(
          padding: const pw.EdgeInsets.fromLTRB(40, 8, 40, 12),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Generated by Cue AI | RCI-Certified SLP Documentation',
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey),
              ),
              pw.Text(
                generatedDate,
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey),
              ),
            ],
          ),
        ),
      ),
    );

    final bytes = await pdf.save();
    final content = base64Encode(bytes);
    final anchor = html.AnchorElement(
        href: 'data:application/pdf;base64,$content')
      ..setAttribute(
          'download',
          '${widget.clientName.replaceAll(' ', '_')}_$sessionDate.pdf')
      ..style.display = 'none';
    html.document.body!.append(anchor);
    anchor.click();
    anchor.remove();
  }

  List<pw.Widget> _buildPdfSections(String text) {
    final widgets = <pw.Widget>[];
    final headerRe = RegExp(r'^([A-Z][A-Z /\-]+):(.*)$');

    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        widgets.add(pw.SizedBox(height: 6));
        continue;
      }
      final match = headerRe.firstMatch(line);
      if (match != null) {
        if (widgets.isNotEmpty) widgets.add(pw.SizedBox(height: 14));
        widgets.add(pw.Text(
          '${match.group(1)!}:',
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.teal800,
          ),
        ));
        final inline = match.group(2)?.trim() ?? '';
        if (inline.isNotEmpty) {
          widgets.add(pw.SizedBox(height: 3));
          widgets.add(pw.Text(
            inline,
            style: const pw.TextStyle(fontSize: 11, lineSpacing: 2),
          ));
        }
        widgets.add(pw.SizedBox(height: 4));
      } else {
        widgets.add(pw.Text(
          line,
          style: const pw.TextStyle(fontSize: 11, lineSpacing: 2),
        ));
      }
    }
    return widgets;
  }

  String _cleanText(String text) {
    return text
        .replaceAllMapped(
            RegExp(r'\*\*(.+?)\*\*'), (m) => m.group(1) ?? '')
        .replaceAllMapped(
            RegExp(r'\*(.+?)\*'), (m) => m.group(1) ?? '')
        .replaceAllMapped(
            RegExp(r'__(.+?)__'), (m) => m.group(1) ?? '')
        .replaceAllMapped(
            RegExp(r'_(.+?)_'), (m) => m.group(1) ?? '')
        .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^[-*+]\s+', multiLine: true), '')
        .replaceAllMapped(
            RegExp(r'\[(.+?)\]\(.+?\)'), (m) => m.group(1) ?? '')
        .replaceAllMapped(
            RegExp(r'`(.+?)`'), (m) => m.group(1) ?? '')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;

    return AppLayout(
      title: 'Report — ${widget.clientName}',
      activeRoute: 'roster',
      body: SingleChildScrollView(
        padding:
            const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Session summary card
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Session: ${session['date'] ?? 'Unknown date'}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 32,
                        runSpacing: 8,
                        children: [
                          if (session['target_behaviour'] != null &&
                              (session['target_behaviour'] as String)
                                  .isNotEmpty)
                            _summaryItem('Goal',
                                session['target_behaviour'] as String),
                          if (session['activity_name'] != null &&
                              (session['activity_name'] as String)
                                  .isNotEmpty)
                            _summaryItem('Activity',
                                session['activity_name'] as String),
                          _summaryItem(
                            'Trials',
                            '${session['attempts'] ?? 0} total · '
                                '${session['independent_responses'] ?? 0} independent · '
                                '${session['prompted_responses'] ?? 0} prompted',
                          ),
                          _summaryItem('Goal Met',
                              _formatGoalMet(session['goal_met'] as String?)),
                          _summaryItem('Affect',
                              _capitalize(session['client_affect'] as String?)),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Generate button
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isLoading ? null : _generateReport,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.teal,
                        padding:
                            const EdgeInsets.symmetric(vertical: 16),
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
                            fontSize: 16,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),

                // Error
                if (_error != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(
                          color: Colors.red.shade800, fontSize: 14),
                    ),
                  ),
                ],

                // Report output
                if (_report != null) ...[
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'AI Report',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _downloadPdf,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.teal.shade700,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.download_rounded,
                            size: 18),
                        label: const Text(
                          'Download PDF',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(24),
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
                            fontSize: 22,
                            fontWeight: FontWeight.bold),
                        h2: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                        h3: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.teal.shade600,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
              fontSize: 14, color: Color(0xFF1A1A2E)),
        ),
      ],
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
