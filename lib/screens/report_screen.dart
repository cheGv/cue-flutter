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

  bool    _isLoading = false;
  String? _report;
  String? _error;
  final List<bool> _soapVisible = List.filled(4, false);

  @override
  void initState() {
    super.initState();
    // Stagger SOAP card entrance: 80 ms apart.
    for (int i = 0; i < 4; i++) {
      Future.delayed(Duration(milliseconds: i * 80), () {
        if (mounted) setState(() => _soapVisible[i] = true);
      });
    }
  }

  Future<void> _generateReport() async {
    setState(() { _isLoading = true; _error = null; _report = null; });
    try {
      final s           = widget.session;
      final bodyString  = jsonEncode({
        'clientName': widget.clientName,
        'session': {
          'date':             '${s['date'] ?? ''}',
          'goal':             '${s['target_behaviour'] ?? ''}',
          'activity':         '${s['activity_name'] ?? ''}',
          'totalTrials':      '${s['attempts'] ?? 0}',
          'independentTrials':'${s['independent_responses'] ?? 0}',
          'promptedTrials':   '${s['prompted_responses'] ?? 0}',
          'goalMet':          '${s['goal_met'] ?? ''}',
          'affect':           '${s['client_affect'] ?? ''}',
          'notes':            '${s['next_session_focus'] ?? ''}',
        },
      });

      final response = await http.post(
        Uri.parse(_proxyUrl),
        headers: {'Content-Type': 'application/json'},
        body: bodyString,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['content']?[0]?['text'] ?? data['report'] ?? response.body;
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
    final session       = widget.session;
    final sessionDate   = '${session['date'] ?? '—'}';
    final now           = DateTime.now();
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
            padding: const pw.EdgeInsets.fromLTRB(40, 20, 40, 18),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Cue AI',
                    style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white)),
                pw.SizedBox(height: 3),
                pw.Text('Clinical Session Report',
                    style: const pw.TextStyle(
                        fontSize: 10, color: PdfColors.white)),
              ],
            ),
          ),
          pw.Container(
            width: double.infinity,
            color: const PdfColor.fromInt(0xFFF8F9FC),
            padding: const pw.EdgeInsets.fromLTRB(40, 10, 40, 10),
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
              pw.Text('Generated by Cue AI | RCI-Certified SLP Documentation',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
              pw.Text(generatedDate,
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
            ],
          ),
        ),
      ),
    );

    final bytes   = await pdf.save();
    final content = base64Encode(bytes);
    final anchor  = html.AnchorElement(
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
    final widgets   = <pw.Widget>[];
    final headerRe  = RegExp(r'^([A-Z][A-Z /\-]+):(.*)$');

    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) { widgets.add(pw.SizedBox(height: 6)); continue; }
      final match = headerRe.firstMatch(line);
      if (match != null) {
        if (widgets.isNotEmpty) widgets.add(pw.SizedBox(height: 14));
        widgets.add(pw.Text('${match.group(1)!}:',
            style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: const PdfColor.fromInt(0xFF00B4A6))));
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
        .replaceAllMapped(RegExp(r'\*(.+?)\*'),     (m) => m.group(1) ?? '')
        .replaceAllMapped(RegExp(r'__(.+?)__'),     (m) => m.group(1) ?? '')
        .replaceAllMapped(RegExp(r'_(.+?)_'),       (m) => m.group(1) ?? '')
        .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^[-*+]\s+',  multiLine: true), '')
        .replaceAllMapped(RegExp(r'\[(.+?)\]\(.+?\)'), (m) => m.group(1) ?? '')
        .replaceAllMapped(RegExp(r'`(.+?)`'),       (m) => m.group(1) ?? '')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final session   = widget.session;
    final goalMet   = _formatGoalMet(session['goal_met'] as String?);
    final soapRaw   = session['soap_note'];
    Map<String, dynamic>? soap;
    if (soapRaw is String && soapRaw.isNotEmpty) {
      try { soap = jsonDecode(soapRaw) as Map<String, dynamic>; } catch (_) {}
    } else if (soapRaw is Map<String, dynamic>) {
      soap = soapRaw;
    }

    return Scaffold(
      backgroundColor: CueColors.softWhite,
      appBar: AppBar(
        title: Text(
          'Report — ${widget.clientName}',
          style: GoogleFonts.dmSans(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        backgroundColor: CueColors.inkNavy,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Session summary card (inkNavy) ──────────────────────────
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF243558),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF243558).withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.description_outlined,
                          color: CueColors.signalTeal, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Session ${session['date'] ?? '—'}',
                        style: GoogleFonts.dmSerifDisplay(
                          fontSize: 18,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if ((session['target_behaviour'] as String?) != null &&
                      (session['target_behaviour'] as String).isNotEmpty)
                    _SummaryRow(
                        label: 'Goal',
                        value: session['target_behaviour'] as String),
                  if ((session['activity_name'] as String?) != null &&
                      (session['activity_name'] as String).isNotEmpty)
                    _SummaryRow(
                        label: 'Activity',
                        value: session['activity_name'] as String),
                  _SummaryRow(
                    label: 'Trials',
                    value:
                        '${session['attempts'] ?? 0} attempts · '
                        '${session['independent_responses'] ?? 0} independent · '
                        '${session['prompted_responses'] ?? 0} prompted',
                  ),
                  _SummaryRow(label: 'Goal Met', value: goalMet),
                  _SummaryRow(
                      label: 'Affect',
                      value: _capitalize(session['client_affect'] as String?)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── SOAP cards (if session has soap_note) ───────────────────
            if (soap != null) ...[
              CueTheme.sectionLabel('SOAP Note'),
              const SizedBox(height: 12),
              ..._buildSoapCards(soap),
              const SizedBox(height: 20),
            ],

            // ── Generate button ─────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _isLoading ? null : _generateReport,
                style: FilledButton.styleFrom(
                  backgroundColor: CueColors.signalTeal,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome, color: Colors.white),
                label: Text(
                  _isLoading ? 'Generating…' : 'Generate Report',
                  style: GoogleFonts.dmSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Error ───────────────────────────────────────────────────
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: CueColors.errorRed.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: CueColors.errorRed.withOpacity(0.3)),
                ),
                child: Text(
                  _error!,
                  style: GoogleFonts.dmSans(
                      color: CueColors.errorRed, fontSize: 14),
                ),
              ),

            // ── Report output ───────────────────────────────────────────
            if (_report != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'AI Report',
                    style: GoogleFonts.dmSerifDisplay(
                        fontSize: 18, color: CueColors.inkNavy),
                  ),
                  FilledButton.icon(
                    onPressed: _downloadPdf,
                    style: FilledButton.styleFrom(
                      backgroundColor: CueColors.inkNavy,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 16,
                        color: Colors.white),
                    label: Text('Download PDF',
                        style: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: CueColors.surfaceWhite,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: CueColors.inkNavy.withOpacity(0.1)),
                  boxShadow: [
                    BoxShadow(
                      color: CueColors.inkNavy.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: MarkdownBody(
                  data: _report!,
                  styleSheet: MarkdownStyleSheet(
                    p: GoogleFonts.dmSans(
                        fontSize: 14, height: 1.6, color: CueColors.inkNavy),
                    h1: GoogleFonts.dmSerifDisplay(
                        fontSize: 20, color: CueColors.inkNavy),
                    h2: GoogleFonts.dmSerifDisplay(
                        fontSize: 17, color: CueColors.inkNavy),
                    h3: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: CueColors.inkNavy),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSoapCards(Map<String, dynamic> soap) {
    final keys   = ['subjective', 'objective', 'assessment', 'plan'];
    final labels = CueTheme.soapLabels;
    final colors = CueTheme.soapColors;

    return List.generate(keys.length, (i) {
      final text = soap[keys[i]]?.toString() ?? '';
      return AnimatedOpacity(
        opacity: _soapVisible[i] ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        child: AnimatedSlide(
          offset: _soapVisible[i] ? Offset.zero : const Offset(0, 0.15),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: CueColors.surfaceWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border(left: BorderSide(color: colors[i], width: 4)),
              boxShadow: [
                BoxShadow(
                  color: CueColors.inkNavy.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  labels[i].toUpperCase(),
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: colors[i],
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  text.isNotEmpty ? text : '—',
                  style: GoogleFonts.dmSans(
                      fontSize: 14, height: 1.55, color: CueColors.inkNavy),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  String _formatGoalMet(String? value) {
    switch (value) {
      case 'yes':       return 'Yes';
      case 'partially': return 'Partially';
      case 'not_yet':   return 'Not Yet';
      default:          return value ?? '—';
    }
  }

  String _capitalize(String? value) {
    if (value == null || value.isEmpty) return '—';
    return value[0].toUpperCase() + value.substring(1);
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              '$label:',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: CueColors.signalTeal,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.85)),
            ),
          ),
        ],
      ),
    );
  }
}
