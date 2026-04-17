import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../theme/cue_theme.dart';

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
  static const _proxyUrl = 'https://cue-ai-proxy.onrender.com/generate-report';

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
      final bodyString = jsonEncode({
        'clientName': widget.clientName,
        'session': {
          'date': '${s['date'] ?? ''}',
          'goal': '${s['target_behaviour'] ?? ''}',
          'activity': '${s['activity_name'] ?? ''}',
          'totalTrials': '${s['attempts'] ?? 0}',
          'independentTrials': '${s['independent_responses'] ?? 0}',
          'promptedTrials': '${s['prompted_responses'] ?? 0}',
          'goalMet': '${s['goal_met'] ?? ''}',
          'affect': '${s['client_affect'] ?? ''}',
          'notes': '${s['next_session_focus'] ?? ''}',
        },
      });

      final response = await http.post(
        Uri.parse(_proxyUrl),
        headers: {'Content-Type': 'application/json'},
        body: bodyString,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text =
            data['content']?[0]?['text'] ?? data['report'] ?? response.body;
        setState(() => _report = text.toString());
      } else {
        setState(() =>
            _error = 'Server error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      setState(() => _error = 'Failed to connect to AI service: $e');
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
            color: const PdfColor.fromInt(0xFF1B2B4B),
            padding: const pw.EdgeInsets.fromLTRB(40, 22, 40, 18),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Cue',
                    style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white)),
                pw.SizedBox(height: 4),
                pw.Text('Clinical Session Report',
                    style: const pw.TextStyle(
                        fontSize: 10, color: PdfColors.white)),
              ],
            ),
          ),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.fromLTRB(40, 14, 40, 14),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Client: ${widget.clientName}',
                    style: pw.TextStyle(
                        fontSize: 11, fontWeight: pw.FontWeight.bold)),
                pw.Text('Session Date: $sessionDate',
                    style: const pw.TextStyle(
                        fontSize: 11, color: PdfColors.grey700)),
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
              pw.Text('Generated by Cue | RCI-Certified SLP Documentation',
                  style:
                      const pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
              pw.Text(generatedDate,
                  style:
                      const pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
            ],
          ),
        ),
      ),
    );

    final bytes = await pdf.save();
    final content = base64Encode(bytes);
    final anchor =
        html.AnchorElement(href: 'data:application/pdf;base64,$content')
          ..setAttribute('download',
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
        widgets.add(pw.Text('${match.group(1)!}:',
            style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: const PdfColor.fromInt(0xFF1B2B4B))));
        final inline = match.group(2)?.trim() ?? '';
        if (inline.isNotEmpty) {
          widgets.add(pw.SizedBox(height: 3));
          widgets.add(pw.Text(inline,
              style: const pw.TextStyle(fontSize: 11, lineSpacing: 2)));
        }
        widgets.add(pw.SizedBox(height: 4));
      } else {
        widgets.add(pw.Text(line,
            style: const pw.TextStyle(fontSize: 11, lineSpacing: 2)));
      }
    }
    return widgets;
  }

  String _cleanText(String text) {
    return text
        .replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m.group(1) ?? '')
        .replaceAllMapped(RegExp(r'\*(.+?)\*'), (m) => m.group(1) ?? '')
        .replaceAllMapped(RegExp(r'__(.+?)__'), (m) => m.group(1) ?? '')
        .replaceAllMapped(RegExp(r'_(.+?)_'), (m) => m.group(1) ?? '')
        .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^[-*+]\s+', multiLine: true), '')
        .replaceAllMapped(
            RegExp(r'\[(.+?)\]\(.+?\)'), (m) => m.group(1) ?? '')
        .replaceAllMapped(RegExp(r'`(.+?)`'), (m) => m.group(1) ?? '')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final goalMet = _formatGoalMet(session['goal_met'] as String?);
    final soapRaw = session['soap_note'];
    Map<String, dynamic>? soap;
    if (soapRaw is String && soapRaw.isNotEmpty) {
      try {
        soap = jsonDecode(soapRaw) as Map<String, dynamic>;
      } catch (_) {}
    } else if (soapRaw is Map<String, dynamic>) {
      soap = soapRaw;
    }

    return Scaffold(
      backgroundColor: CueColors.background,
      appBar: AppBar(
        title: const Text('Report'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.clientName,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: CueColors.inkSecondary,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 4),

            // ── Summary card ─────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: CueColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: CueColors.divider),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session['date']?.toString() ?? '—',
                    style: GoogleFonts.fraunces(
                      fontSize: 28,
                      fontWeight: FontWeight.w500,
                      color: CueColors.inkPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if ((session['target_behaviour'] as String?)?.isNotEmpty ==
                      true)
                    _KV(label: 'Goal', value: session['target_behaviour']),
                  if ((session['activity_name'] as String?)?.isNotEmpty ==
                      true)
                    _KV(label: 'Activity', value: session['activity_name']),
                  _KV(
                    label: 'Trials',
                    value:
                        '${session['attempts'] ?? 0} attempts · ${session['independent_responses'] ?? 0} independent · ${session['prompted_responses'] ?? 0} prompted',
                  ),
                  _KV(label: 'Goal met', value: goalMet),
                  _KV(
                      label: 'Affect',
                      value: _capitalize(
                          session['client_affect'] as String?)),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // ── SOAP cards ───────────────────────────────────────────────
            if (soap != null) ...[
              CueTheme.eyebrow('SOAP Note'),
              const SizedBox(height: 12),
              ..._buildSoapCards(soap),
              const SizedBox(height: 32),
            ],

            // ── Generate button ──────────────────────────────────────────
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _isLoading ? null : _generateReport,
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_outlined,
                        color: Colors.white, size: 18),
                label: Text(_isLoading ? 'Generating…' : 'Generate Report'),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: CueColors.coral.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: CueColors.coral.withOpacity(0.3)),
                ),
                child: Text(
                  _error!,
                  style: GoogleFonts.inter(
                      color: CueColors.coral, fontSize: 14),
                ),
              ),
            ],

            if (_report != null) ...[
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'AI Report',
                    style: GoogleFonts.fraunces(
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      color: CueColors.inkPrimary,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _downloadPdf,
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: const Text('Download PDF'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: CueColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: CueColors.divider),
                ),
                child: MarkdownBody(
                  data: _report!,
                  styleSheet: MarkdownStyleSheet(
                    p: GoogleFonts.inter(
                        fontSize: 15,
                        height: 1.6,
                        color: CueColors.inkPrimary),
                    h1: GoogleFonts.fraunces(
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                        color: CueColors.inkPrimary),
                    h2: GoogleFonts.fraunces(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: CueColors.inkPrimary),
                    h3: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: CueColors.inkPrimary),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSoapCards(Map<String, dynamic> soap) {
    final keys = ['subjective', 'objective', 'assessment', 'plan'];
    final labels = CueTheme.soapLabels;

    return List.generate(keys.length, (i) {
      final text = soap[keys[i]]?.toString() ?? '';
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: CueColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: CueColors.divider),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              labels[i],
              style: GoogleFonts.fraunces(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: CueColors.inkPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              text.isNotEmpty ? text : '—',
              style: GoogleFonts.inter(
                fontSize: 15,
                height: 1.55,
                color: CueColors.inkPrimary,
              ),
            ),
          ],
        ),
      );
    });
  }

  String _formatGoalMet(String? value) {
    switch (value) {
      case 'yes':
        return 'Yes';
      case 'partially':
        return 'Partially';
      case 'not_yet':
        return 'Not yet';
      default:
        return value ?? '—';
    }
  }

  String _capitalize(String? value) {
    if (value == null || value.isEmpty) return '—';
    return value[0].toUpperCase() + value.substring(1);
  }
}

class _KV extends StatelessWidget {
  final String label;
  final dynamic value;

  const _KV({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: CueColors.inkSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value?.toString() ?? '—',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: CueColors.inkPrimary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
