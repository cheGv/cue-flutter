import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/session_archive_service.dart';
import '../widgets/app_layout.dart';
import '../widgets/cue_study_icon.dart';
import 'narrate_session_screen.dart';

const _bg   = Color(0xFFF2EFE9);
const _ink  = Color(0xFF0A0A0A);
const _teal = Color(0xFF1D9E75);
const _line = Color(0xFFD8D5CE);

class ReportScreen extends StatefulWidget {
  final Map<String, dynamic> session;
  final String clientName;
  final String? clientId;

  const ReportScreen({
    super.key,
    required this.session,
    required this.clientName,
    this.clientId,
  });

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

// TODO(cue-study-mode-5): Add Cue Study Mode 5 — progress interpretation — to this screen.
// Entry point: a "What does this observation mean?" text button shown after a session note
// is generated, using the clinician's observation text as input.
// System prompt is defined as _csProgressPrompt in ltg_edit_screen.dart — extract it to a
// shared constants file (e.g. lib/constants/cue_study_prompts.dart) before implementing here.
// Response renders in the standard dark-navy Cue Study card (see _csCard in ltg_edit_screen.dart).
class _ReportScreenState extends State<ReportScreen> {
  static const _proxyUrl =
      'https://cue-ai-proxy.onrender.com/generate-report';
  static const _parentUpdateProxyUrl =
      'https://cue-ai-proxy.onrender.com/pre-session-brief';

  static const _parentUpdateSystemPrompt =
      "You are a speech-language pathologist's communication assistant. "
      'Transform the clinical session note into a warm, jargon-free WhatsApp message for parents.\n'
      'Follow every rule without exception:\n\n'
      'Use only information present in the SOAP note. Never invent or assume clinical details.\n'
      'Replace all clinical terms with plain language. Examples: "phoneme" → "sound", '
      '"pragmatics" → "conversation skills", "AAC device" → "communication device", '
      '"articulation" → "clear speech", "dysarthria" → "speech clarity", '
      '"mean length of utterance" → "sentence length".\n'
      "Use the child's first name throughout — never \"your child\".\n"
      'Write exactly three short paragraphs:\n\n'
      'Para 1: What we worked on today (drawn from S or O)\n'
      'Para 2: One specific thing [Name] did really well (must be grounded in O section observations)\n'
      'Para 3: One simple, specific home practice suggestion (must come from A or P section)\n\n'
      'Tone: warm, hopeful, encouraging. Parents should feel proud, not anxious.\n'
      'Total length: 80–120 words. Must be readable on a phone screen.\n'
      'End with exactly: "Warm regards"  — do not add the SLP name (the app will append it).\n'
      'Output plain text only. No markdown, no asterisks, no bullet points, no headers.\n'
      'If the SOAP note is too sparse to write Para 2 or Para 3 with real specifics, '
      'write those paragraphs in general encouraging terms — do not fabricate specific observations.';

  final _supabase = Supabase.instance.client;
  bool _isLoading = false;
  String? _report;
  String? _error;
  String _reportFormat = 'SOAP';

  // SOAP editing (§9.2 attestation gate)
  late final TextEditingController _sCtrl;
  late final TextEditingController _oCtrl;
  late final TextEditingController _aCtrl;
  late final TextEditingController _pCtrl;
  bool _attested = false;
  bool _savingNote = false;
  bool _showNoteFields = false;

  // Parent Update
  String _parentUpdate = '';
  bool _parentUpdateLoading = false;
  String? _parentUpdateError;
  final TextEditingController _parentUpdateController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _sCtrl = TextEditingController();
    _oCtrl = TextEditingController();
    _aCtrl = TextEditingController();
    _pCtrl = TextEditingController();
    _loadReportFormat();
    // Pre-populate parent update if this session already has one saved
    final saved = widget.session['parent_update'] as String?;
    if (saved != null && saved.trim().isNotEmpty) {
      _parentUpdate = saved.trim();
      _parentUpdateController.text = _parentUpdate;
    }
    // Pre-populate SOAP fields if a note was already saved
    final savedNote = widget.session['soap_note'] as String?;
    if (savedNote != null && savedNote.trim().isNotEmpty) {
      _initFromSavedNote(savedNote.trim());
    }
  }

  void _initFromSavedNote(String savedNote) {
    try {
      final parsed = jsonDecode(savedNote) as Map<String, dynamic>;
      _sCtrl.text = parsed['s'] as String? ?? '';
      _oCtrl.text = parsed['o'] as String? ?? '';
      _aCtrl.text = parsed['a'] as String? ?? '';
      _pCtrl.text = parsed['p'] as String? ?? '';
    } catch (_) {
      _sCtrl.text = savedNote;
    }
    _showNoteFields = true;
  }

  Future<void> _loadReportFormat() async {
    try {
      final uid = _supabase.auth.currentUser?.id;
      if (uid == null) return;
      final row = await _supabase
          .from('slp_profiles')
          .select('report_format')
          .eq('clinician_id', uid)
          .maybeSingle();
      if (row != null && mounted) {
        final fmt = row['report_format'] as String?;
        if (fmt != null && fmt.isNotEmpty) {
          setState(() => _reportFormat = fmt);
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _sCtrl.dispose();
    _oCtrl.dispose();
    _aCtrl.dispose();
    _pCtrl.dispose();
    _parentUpdateController.dispose();
    super.dispose();
  }

  Future<void> _generateReport() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _report = null;
      _attested = false;
    });
    _sCtrl.clear();
    _oCtrl.clear();
    _aCtrl.clear();
    _pCtrl.clear();
    try {
      // Fetch active goals to enrich the report prompt
      List<Map<String, dynamic>> goals = [];
      if (widget.clientId != null) {
        try {
          final cid = widget.clientId!.toString();
          print('[ReportScreen] Fetching goals for clientId: $cid');
          final goalsResponse = await _supabase
              .from('goals')
              .select('goal_text, domain, target_accuracy')
              .eq('client_id', cid)
              .eq('status', 'active');
          goals = List<Map<String, dynamic>>.from(goalsResponse);
          print('[ReportScreen] Goals fetched: $goals');
        } catch (e) {
          // Non-blocking — report still generates without goals
          print('[ReportScreen] Goals fetch failed: $e');
        }
      } else {
        print('[ReportScreen] clientId is null — goals skipped');
      }

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

      final goalsList = goals
          .map((g) => {
                'domain': g['domain'],
                'goal': g['goal_text'],
                'target': '${g['target_accuracy']}%',
              })
          .toList();

      // Phase 4.0.7.9i-fix2: send transcript so the proxy can run
      // narrator-mode (MODE A) when structured fields are empty.
      // widget.session['transcript'] is the canonical source since
      // 4.0.7.8a (narrate_session_screen persists it before navigation
      // and on back-nav hydration).
      final transcript =
          (widget.session['transcript'] as String?)?.trim() ?? '';

      final bodyMap = {
        'clientName':   name,
        'reportFormat': _reportFormat,
        'transcript':   transcript,
        'session': {
          'date': date,
          'goal': goal,
          'activity': activity,
          'totalTrials': attempts,
          'independentTrials': independent,
          'promptedTrials': prompted,
          'goalMet': goalMet,
          'affect': affect,
          'notes': notes,
        },
        'goals': goalsList,
        'noMarkdown': true,
      };

      final response = await http.post(
        Uri.parse(_proxyUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(bodyMap),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text =
            data['content']?[0]?['text'] ?? data['report'] ?? response.body;
        final reportText = _cleanText(text.toString());

        // Phase 4.0.7.9i-fix2: parent_summary is now a structured JSON
        // field on the proxy response. Try the JSON path first; fall
        // back to the legacy text-section split for any non-JSON
        // responses (handles regressions and any in-flight callers).
        String parentSummary;
        String clinicalText;
        final reportTrimmed = reportText.trim();
        if (reportTrimmed.startsWith('{')) {
          try {
            final parsed = jsonDecode(reportTrimmed);
            if (parsed is Map<String, dynamic>) {
              parentSummary =
                  (parsed['parent_summary'] as String?)?.trim() ?? '';
              // The clinical text passed downstream is the full JSON —
              // _populateSoapFields handles JSON-first extraction itself.
              clinicalText = reportText;
            } else {
              final split = _splitClinicalAndParent(reportText);
              parentSummary = split.parent;
              clinicalText  = split.clinical;
            }
          } catch (_) {
            final split = _splitClinicalAndParent(reportText);
            parentSummary = split.parent;
            clinicalText  = split.clinical;
          }
        } else {
          final split = _splitClinicalAndParent(reportText);
          parentSummary = split.parent;
          clinicalText  = split.clinical;
        }

        setState(() {
          _report = reportText;
          _showNoteFields = true;
        });
        _populateSoapFields(clinicalText);

        // Persist the AI output immediately so a tab close ≠ data loss.
        // _persistGeneratedReport reads the SOAP form controllers (now
        // populated above) plus the parent_summary we just extracted.
        await _persistGeneratedReport(parentSummary: parentSummary);
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

  // ── Phase 4.0.7.9a helpers ──────────────────────────────────────────────────

  /// Split the AI-generated report text into a clinical half (containing
  /// S/O/A/P or DAR/COAST sections) and a parent communication half. The
  /// proxy prompt emits a `PAGE 2 — PARENT COMMUNICATION SUMMARY` header
  /// to delineate the two; we look for that or any tolerant variant. Pre-
  /// fix this content was concatenated into the P field by the SOAP
  /// parser and the parent block only landed in the PDF by lucky regex
  /// match downstream.
  ({String clinical, String parent}) _splitClinicalAndParent(String text) {
    final headerPatterns = <RegExp>[
      RegExp(r'PARENT\s+COMMUNICATION\s+SUMMARY', caseSensitive: false),
      RegExp(r'PARENT\s+SUMMARY',                 caseSensitive: false),
      RegExp(r'PAGE\s*2',                          caseSensitive: false),
    ];
    int? splitStart;
    int? bodyStart;
    for (final p in headerPatterns) {
      final m = p.firstMatch(text);
      if (m != null) {
        splitStart = m.start;
        // skip to end of the header line
        final nl = text.indexOf('\n', m.end);
        bodyStart = nl >= 0 ? nl + 1 : m.end;
        break;
      }
    }
    if (splitStart == null || bodyStart == null) {
      return (clinical: text, parent: '');
    }
    final clinical = text.substring(0, splitStart).trim();
    final parent   = text.substring(bodyStart).trim();
    return (clinical: clinical, parent: parent);
  }

  /// Persist the freshly-generated AI output. Single transactional PATCH
  /// with all five fields the report flow owns at this stage. Mirrors
  /// the values into widget.session so subsequent reads (PDF, SOAP form,
  /// _hasSavedNote getter) see consistent state without a round-trip.
  Future<void> _persistGeneratedReport({required String parentSummary}) async {
    final sessionId = widget.session['id'];
    if (sessionId == null) {
      print('[ReportScreen] persist skipped — session id is null');
      return;
    }
    try {
      final noteJson = jsonEncode({
        's': _sCtrl.text.trim(),
        'o': _oCtrl.text.trim(),
        'a': _aCtrl.text.trim(),
        'p': _pCtrl.text.trim(),
      });
      await _supabase.from('sessions').update({
        'soap_note':          noteJson,
        'parent_summary':     parentSummary,
        'ai_generated':       true,
        'clinician_attested': false,
        'attested_at':        null,
      }).eq('id', sessionId);

      // Mirror locally so the rest of this screen reads consistent state.
      widget.session['soap_note']          = noteJson;
      widget.session['parent_summary']     = parentSummary;
      widget.session['ai_generated']       = true;
      widget.session['clinician_attested'] = false;
      widget.session['attested_at']        = null;
    } catch (e) {
      print('[ReportScreen] persist on generation failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't save report — try regenerating"),
          ),
        );
      }
    }
  }

  // ── Note field labels (format-aware) ────────────────────────────────────────

  List<({String label, TextEditingController ctrl})> get _noteFields {
    switch (_reportFormat) {
      case 'DAR':
        return [
          (label: 'D — Data',     ctrl: _sCtrl),
          (label: 'A — Action',   ctrl: _oCtrl),
          (label: 'R — Response', ctrl: _aCtrl),
        ];
      case 'COAST':
        return [
          (label: 'C — Context',            ctrl: _sCtrl),
          (label: 'O — Observation',        ctrl: _oCtrl),
          (label: 'A — Assessment',         ctrl: _aCtrl),
          (label: 'S + T — Strategy/Target', ctrl: _pCtrl),
        ];
      case 'Narrative':
        return [
          (label: 'Narrative', ctrl: _sCtrl),
        ];
      default:
        return [
          (label: 'S — Subjective', ctrl: _sCtrl),
          (label: 'O — Objective',  ctrl: _oCtrl),
          (label: 'A — Assessment', ctrl: _aCtrl),
          (label: 'P — Plan',       ctrl: _pCtrl),
        ];
    }
  }

  // ── Note parsing ─────────────────────────────────────────────────────────────

  /// Phase 4.0.7.9i-fix2 — JSON-first SOAP populate. The proxy now
  /// returns strict JSON {s,o,a,p,parent_summary}; we try that path
  /// first and fall back to the legacy regex parser only if the
  /// response doesn't look like JSON or fails to parse. Empty-mode
  /// (MODE D) is detected and handled gracefully — all four fields
  /// blanked and a debug line logged so the SLP doesn't see hallucinated
  /// content for a session with no captured data.
  void _populateSoapFields(String text) {
    final trimmed = text.trim();

    if (trimmed.startsWith('{')) {
      try {
        final parsed = jsonDecode(trimmed);
        if (parsed is Map<String, dynamic>) {
          final s = (parsed['s'] as String?)?.trim() ?? '';
          final o = (parsed['o'] as String?)?.trim() ?? '';
          final a = (parsed['a'] as String?)?.trim() ?? '';
          final p = (parsed['p'] as String?)?.trim() ?? '';

          // Empty-mode: surface "no data captured" rather than silently
          // populating empty fields under a successful-looking response.
          if (s.isEmpty && o.isEmpty && a.isEmpty && p.isEmpty) {
            _sCtrl.text = '';
            _oCtrl.text = '';
            _aCtrl.text = '';
            _pCtrl.text = '';
            debugPrint('[ReportScreen] proxy returned empty SOAP — '
                'no data captured for this session');
            return;
          }

          _sCtrl.text = s;
          _oCtrl.text = o;
          _aCtrl.text = a;
          _pCtrl.text = p;
          return;
        }
      } catch (e) {
        debugPrint('[ReportScreen] JSON parse failed, falling back '
            'to regex: $e');
        // fall through to legacy regex path below
      }
    }

    _populateSoapFieldsLegacy(text);
  }

  /// Pre-4.0.7.9i regex parser. Retained verbatim for backwards
  /// compatibility with any legacy proxy responses or future regressions.
  void _populateSoapFieldsLegacy(String text) {
    switch (_reportFormat) {
      case 'DAR':
        final dar = _parseSections(text, {
          's': [RegExp(r'^D(?:ATA)?\s*[:\-]?\s*$', caseSensitive: false),
                RegExp(r'^D(?:ATA)?\s*[:\-]\s*',   caseSensitive: false)],
          'o': [RegExp(r'^A(?:CTION)?\s*[:\-]?\s*$', caseSensitive: false),
                RegExp(r'^A(?:CTION)?\s*[:\-]\s*',   caseSensitive: false)],
          'a': [RegExp(r'^R(?:ESPONSE)?\s*[:\-]?\s*$', caseSensitive: false),
                RegExp(r'^R(?:ESPONSE)?\s*[:\-]\s*',   caseSensitive: false)],
        });
        _sCtrl.text = dar['s'] ?? '';
        _oCtrl.text = dar['o'] ?? '';
        _aCtrl.text = dar['a'] ?? '';
        _pCtrl.text = '';
      case 'COAST':
        final coast = _parseSections(text, {
          's': [RegExp(r'^C(?:ONTEXT)?\s*[:\-]?\s*$',     caseSensitive: false),
                RegExp(r'^C(?:ONTEXT)?\s*[:\-]\s*',        caseSensitive: false)],
          'o': [RegExp(r'^O(?:BSERVATION)?\s*[:\-]?\s*$', caseSensitive: false),
                RegExp(r'^O(?:BSERVATION)?\s*[:\-]\s*',    caseSensitive: false)],
          'a': [RegExp(r'^A(?:SSESSMENT)?\s*[:\-]?\s*$',  caseSensitive: false),
                RegExp(r'^A(?:SSESSMENT)?\s*[:\-]\s*',     caseSensitive: false)],
          'p': [RegExp(r'^[ST](?:TRATEGY|ARGET)?\s*[:\-]?\s*$', caseSensitive: false),
                RegExp(r'^[ST](?:TRATEGY|ARGET)?\s*[:\-]\s*',   caseSensitive: false)],
        });
        _sCtrl.text = coast['s'] ?? '';
        _oCtrl.text = coast['o'] ?? '';
        _aCtrl.text = coast['a'] ?? '';
        _pCtrl.text = coast['p'] ?? '';
      case 'Narrative':
        _sCtrl.text = text.trim();
        _oCtrl.text = '';
        _aCtrl.text = '';
        _pCtrl.text = '';
      default:
        final soap = _parseSoap(text);
        _sCtrl.text = soap['s'] ?? '';
        _oCtrl.text = soap['o'] ?? '';
        _aCtrl.text = soap['a'] ?? '';
        _pCtrl.text = soap['p'] ?? '';
    }
  }

  // Generic section parser — sectionPatterns maps controller key → [header-only regex, inline regex]
  Map<String, String> _parseSections(
    String text,
    Map<String, List<RegExp>> sectionPatterns,
  ) {
    final keys   = sectionPatterns.keys.toList();
    final acc    = {for (final k in keys) k: StringBuffer()};
    String? cur;

    for (final raw in text.split('\n')) {
      final line = raw.trim();
      final up   = line.replaceAll(RegExp(r'[#*_]'), '').trim().toUpperCase();
      bool matched = false;
      for (final entry in sectionPatterns.entries) {
        final headerOnly = entry.value[0];
        final inline     = entry.value[1];
        if (headerOnly.hasMatch(up)) {
          cur = entry.key; matched = true; break;
        }
        if (line.isNotEmpty) {
          final inlineMatch = line.replaceAll(RegExp(r'^[#*_\s]*'), '');
          if (inline.hasMatch(inlineMatch)) {
            cur = entry.key; matched = true;
            final rest = inlineMatch.replaceFirst(inline, '').trim();
            if (rest.isNotEmpty) acc[cur]!.writeln(rest);
            break;
          }
        }
      }
      if (!matched && cur != null && line.isNotEmpty) {
        acc[cur]!.writeln(line);
      }
    }
    final result = {for (final k in keys) k: acc[k]!.toString().trim()};
    if (result.values.every((v) => v.isEmpty)) {
      return {keys.first: text.trim(), for (final k in keys.skip(1)) k: ''};
    }
    return result;
  }

  // Line-by-line SOAP section extractor. Falls back to full text in S if no
  // section headers are found (handles plain-text AI output gracefully).
  Map<String, String> _parseSoap(String text) {
    final acc = <String, StringBuffer>{
      's': StringBuffer(),
      'o': StringBuffer(),
      'a': StringBuffer(),
      'p': StringBuffer(),
    };
    String? cur;
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      final up = line.replaceAll(RegExp(r'[#*_]'), '').trim().toUpperCase();
      if (RegExp(r'^S(?:UBJECTIVE)?\s*[:\-]?\s*$').hasMatch(up)) {
        cur = 's'; continue;
      } else if (up.startsWith('S:') || up.startsWith('SUBJECTIVE:')) {
        cur = 's';
        final rest = line.replaceFirst(RegExp(r'^[#*_\s]*S(?:UBJECTIVE)?\s*[:\-]\s*', caseSensitive: false), '').trim();
        if (rest.isNotEmpty) acc['s']!.writeln(rest);
        continue;
      }
      if (RegExp(r'^O(?:BJECTIVE)?\s*[:\-]?\s*$').hasMatch(up)) {
        cur = 'o'; continue;
      } else if (up.startsWith('O:') || up.startsWith('OBJECTIVE:')) {
        cur = 'o';
        final rest = line.replaceFirst(RegExp(r'^[#*_\s]*O(?:BJECTIVE)?\s*[:\-]\s*', caseSensitive: false), '').trim();
        if (rest.isNotEmpty) acc['o']!.writeln(rest);
        continue;
      }
      if (RegExp(r'^A(?:SSESSMENT)?\s*[:\-]?\s*$').hasMatch(up)) {
        cur = 'a'; continue;
      } else if (up.startsWith('A:') || up.startsWith('ASSESSMENT:')) {
        cur = 'a';
        final rest = line.replaceFirst(RegExp(r'^[#*_\s]*A(?:SSESSMENT)?\s*[:\-]\s*', caseSensitive: false), '').trim();
        if (rest.isNotEmpty) acc['a']!.writeln(rest);
        continue;
      }
      if (RegExp(r'^P(?:LAN)?\s*[:\-]?\s*$').hasMatch(up)) {
        cur = 'p'; continue;
      } else if (up.startsWith('P:') || up.startsWith('PLAN:')) {
        cur = 'p';
        final rest = line.replaceFirst(RegExp(r'^[#*_\s]*P(?:LAN)?\s*[:\-]\s*', caseSensitive: false), '').trim();
        if (rest.isNotEmpty) acc['p']!.writeln(rest);
        continue;
      }
      if (cur != null && line.isNotEmpty) acc[cur]!.writeln(line);
    }
    final s = acc['s']!.toString().trim();
    final o = acc['o']!.toString().trim();
    final a = acc['a']!.toString().trim();
    final p = acc['p']!.toString().trim();
    if (s.isEmpty && o.isEmpty && a.isEmpty && p.isEmpty) {
      return {'s': text.trim(), 'o': '', 'a': '', 'p': ''};
    }
    return {'s': s, 'o': o, 'a': a, 'p': p};
  }

  // ── Phase 4.0.7.10b — archive (soft-delete) thin wrapper ───────────────
  // Dialog + PATCH lives in session_archive_service.dart; this screen
  // owns only the navigation choice (pop with `true` so the caller can
  // refresh its session list).
  Future<void> _archiveSession() async {
    final archived = await archiveSession(
      context: context,
      session: widget.session,
    );
    if (archived && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  // ── Save SOAP + optional attestation ────────────────────────────────────────

  Future<void> _saveSoapNote() async {
    setState(() => _savingNote = true);
    try {
      if (widget.session['clinician_attested'] == true) {
        await _supabase.from('sessions').update({
          'clinician_attested': false,
          'attested_at': null,
        }).eq('id', widget.session['id']);
      }
      // soap_note column is text — store as JSON string for structured retrieval
      final noteJson = jsonEncode({
        's': _sCtrl.text.trim(),
        'o': _oCtrl.text.trim(),
        'a': _aCtrl.text.trim(),
        'p': _pCtrl.text.trim(),
      });
      final updates = <String, dynamic>{
        'soap_note': noteJson,
        'ai_generated': true,
        if (_attested) ...{
          'clinician_attested': true,
          'attested_at': DateTime.now().toUtc().toIso8601String(),
          'attested_by': _supabase.auth.currentUser?.id,
        },
      };
      // sessions.id is bigint — pass as-is (Supabase Dart returns int)
      await _supabase
          .from('sessions')
          .update(updates)
          .eq('id', widget.session['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_attested
                ? 'Report saved and attested.'
                : 'Report saved.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingNote = false);
    }
  }

  // ── Parent Update ────────────────────────────────────────────────────────────

  bool get _hasSavedNote {
    final v = widget.session['soap_note'] as String?;
    return v != null && v.trim().isNotEmpty;
  }

  bool get _hasTranscript {
    final v = widget.session['transcript'] as String?;
    return v != null && v.trim().isNotEmpty;
  }

  bool get _hasTrialData =>
      _asInt(widget.session['attempts']) > 0 ||
      _asInt(widget.session['independent_responses']) > 0 ||
      _asInt(widget.session['prompted_responses']) > 0;

  bool get _sessionIsEmpty => !_hasSavedNote && !_hasTranscript && !_hasTrialData;

  bool get _soapIsEmpty =>
      _sCtrl.text.trim().isEmpty &&
      _oCtrl.text.trim().isEmpty &&
      _aCtrl.text.trim().isEmpty &&
      _pCtrl.text.trim().isEmpty;

  Future<void> _generateParentUpdate() async {
    setState(() {
      _parentUpdateLoading = true;
      _parentUpdateError = null;
    });
    try {
      final sb = StringBuffer();
      sb.writeln('Child: ${widget.clientName}');
      sb.writeln(
          'Session date: ${widget.session['date'] ?? 'not documented'}');
      sb.writeln('SOAP Note:');
      if (_sCtrl.text.trim().isNotEmpty) {
        sb.writeln('S: ${_sCtrl.text.trim()}');
      }
      if (_oCtrl.text.trim().isNotEmpty) {
        sb.writeln('O: ${_oCtrl.text.trim()}');
      }
      if (_aCtrl.text.trim().isNotEmpty) {
        sb.writeln('A: ${_aCtrl.text.trim()}');
      }
      if (_pCtrl.text.trim().isNotEmpty) {
        sb.writeln('P: ${_pCtrl.text.trim()}');
      }

      final response = await http.post(
        Uri.parse(_parentUpdateProxyUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': 'claude-opus-4-5',
          'system': _parentUpdateSystemPrompt,
          'user_message': sb.toString().trim(),
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final text = data['content']?[0]?['text']
            ?? data['text']
            ?? data['brief']
            ?? response.body;
        final generated = text.toString().trim();
        setState(() {
          _parentUpdate = generated;
          _parentUpdateController.text = generated;
        });
        _saveParentUpdate();
      } else {
        setState(() {
          _parentUpdateError =
              'Error ${response.statusCode}: ${response.body}';
        });
      }
    } catch (e) {
      setState(() {
        _parentUpdateError = 'Could not connect to AI service: $e';
      });
    } finally {
      if (mounted) setState(() => _parentUpdateLoading = false);
    }
  }

  Future<void> _saveParentUpdate() async {
    final text = _parentUpdateController.text.trim();
    if (text.isEmpty) return;
    try {
      await _supabase.from('sessions').update({
        'parent_update': text,
        'parent_update_generated_at':
            DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.session['id']);
      if (mounted) setState(() => _parentUpdate = text);
    } catch (_) {
      // Silent fail on auto-save — text is still visible to the SLP
    }
  }

  Future<void> _copyParentUpdate() async {
    final text = _parentUpdateController.text.trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    _saveParentUpdate();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copied to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _shareWhatsApp() async {
    final text = _parentUpdateController.text.trim();
    if (text.isEmpty) return;
    _saveParentUpdate();
    final uri =
        Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WhatsApp not available')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WhatsApp not available')),
        );
      }
    }
  }

  Future<void> _downloadPdf() async {
    final session = widget.session;
    final sessionDate = '${session['date'] ?? '—'}';
    final now = DateTime.now();
    final generatedDate =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    // CHANGE 2: PDF body now sources from the SLP-editable form
    // controllers, not the raw _report blob. Any in-form edits land in
    // the export. Format-aware via _noteFields (SOAP / DAR / COAST /
    // Narrative) so the section labels match what the SLP saw on screen.
    final clinicalSections = _buildPdfSections(
      s: _sCtrl.text,
      o: _oCtrl.text,
      a: _aCtrl.text,
      p: _pCtrl.text,
    );

    // CHANGE 3 fallback chain: SLP-edited controller wins; failing that
    // the persisted parent_summary column; failing that, omit page 2.
    String parentSummary = _parentUpdateController.text.trim();
    if (parentSummary.isEmpty) {
      final col = (widget.session['parent_summary'] as String?)?.trim();
      if (col != null && col.isNotEmpty) parentSummary = col;
    }
    if (parentSummary.isEmpty) {
      print('[ReportScreen] parent summary empty in both '
          '_parentUpdateController and session.parent_summary — '
          'omitting PDF page 2');
    }

    pw.Widget headerBar() => pw.Container(
          width: double.infinity,
          color: PdfColors.teal,
          padding: const pw.EdgeInsets.fromLTRB(40, 20, 40, 18),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Cue',
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
        );

    pw.Widget subBar() => pw.Container(
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
        );

    pw.Widget footerBar(pw.Context ctx) => pw.Container(
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
                'Generated by Cue | RCI-Certified SLP Documentation',
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
        );

    final pdf = pw.Document();

    // ── Page 1 — clinical SOAP / DAR / COAST / Narrative ─────────────
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        footer: footerBar,
        build: (context) => [
          headerBar(),
          subBar(),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(40, 24, 40, 24),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: clinicalSections,
            ),
          ),
        ],
      ),
    );

    // ── Page 2 — parent communication summary (only if non-empty) ────
    if (parentSummary.isNotEmpty) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          footer: footerBar,
          build: (context) => [
            headerBar(),
            subBar(),
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(40, 24, 40, 24),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'PARENT COMMUNICATION SUMMARY',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.teal800,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    parentSummary,
                    style: const pw.TextStyle(
                        fontSize: 11, lineSpacing: 2),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

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

  /// CHANGE 2: structured-input PDF section builder. Replaces the
  /// previous regex-driven "scan a single text blob for ALL-CAPS
  /// headers" approach. Iterates _noteFields so the labels respect the
  /// SLP's chosen report format (SOAP / DAR / COAST / Narrative).
  /// Empty fields are skipped — no blank section headers.
  List<pw.Widget> _buildPdfSections({
    required String s,
    required String o,
    required String a,
    required String p,
  }) {
    final values = <TextEditingController, String>{
      _sCtrl: s.trim(),
      _oCtrl: o.trim(),
      _aCtrl: a.trim(),
      _pCtrl: p.trim(),
    };
    final widgets = <pw.Widget>[];
    var first = true;
    for (final field in _noteFields) {
      final body = values[field.ctrl] ?? '';
      if (body.isEmpty) continue;
      if (!first) widgets.add(pw.SizedBox(height: 14));
      first = false;
      widgets.add(pw.Text(
        field.label.toUpperCase(),
        style: pw.TextStyle(
          fontSize: 11,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.teal800,
        ),
      ));
      widgets.add(pw.SizedBox(height: 4));
      widgets.add(pw.Text(
        body,
        style: const pw.TextStyle(fontSize: 11, lineSpacing: 2),
      ));
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
    return AppLayout(
      title:       'Report — ${widget.clientName}',
      activeRoute: 'roster',
      actions: [
        // Phase 4.0.7.10 — kebab → archive this session.
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            if (value == 'archive') _archiveSession();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'archive',
              child: Text('Archive this session'),
            ),
          ],
        ),
      ],
      body: LayoutBuilder(
        builder: (context, constraints) {
          final hPad = constraints.maxWidth > 600 ? 48.0 : 20.0;
          return Container(
            color: _bg,
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                  horizontal: hPad, vertical: 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // ── Generate Report — first thing the SLP sees ────────
                      if (_hasSavedNote)
                        // Fields already pre-populated — no button needed
                        const SizedBox.shrink()
                      else if (_sessionIsEmpty)
                        _buildEmptySessionState()
                      else
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _isLoading ? null : _generateReport,
                            style: FilledButton.styleFrom(
                              backgroundColor: _teal,
                              disabledBackgroundColor:
                                  _teal.withValues(alpha: 0.5),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 18, height: 18,
                                    child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2))
                                : const Icon(Icons.auto_awesome),
                            label: Text(
                              _isLoading ? 'Generating…' : 'Generate Report',
                              style: GoogleFonts.dmSans(
                                fontSize:   16,
                                fontWeight: FontWeight.w500,
                                color:      Colors.white,
                              ),
                            ),
                          ),
                        ),

                      // ── Error ─────────────────────────────────────────────
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color:        Colors.red.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Text(_error!,
                              style: TextStyle(
                                  color: Colors.red.shade800,
                                  fontSize: 14)),
                        ),
                      ],

                      // ── Session context card ───────────────────────────────
                      const SizedBox(height: 24),
                      _buildSummaryCard(widget.session),

                      // ── Report output + attestation (§9.2) ───────────────
                      if (_showNoteFields) ...[
                        const SizedBox(height: 32),
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Session Report',
                              style: GoogleFonts.dmSans(
                                fontSize:   18,
                                fontWeight: FontWeight.w600,
                                color:      _ink,
                              ),
                            ),
                            if (_report != null)
                              FilledButton.icon(
                                onPressed: _downloadPdf,
                                style: FilledButton.styleFrom(
                                  backgroundColor: _teal,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(10),
                                  ),
                                ),
                                icon: const Icon(
                                    Icons.download_rounded, size: 18),
                                label: Text(
                                  'Download PDF',
                                  style: GoogleFonts.dmSans(
                                    fontSize:   14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color:        Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border:       Border.all(color: _line),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (int i = 0;
                                  i < _noteFields.length;
                                  i++) ...[
                                if (i > 0) const SizedBox(height: 18),
                                _soapField(_noteFields[i].label,
                                    _noteFields[i].ctrl),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Attestation checkbox (§9.2 — must not be pre-checked)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Checkbox(
                              value:    _attested,
                              onChanged: (v) =>
                                  setState(() => _attested = v ?? false),
                              activeColor: _teal,
                            ),
                            const Expanded(
                              child: Text(
                                'I have reviewed and attest to this report',
                                style: TextStyle(
                                    fontSize: 14, color: _ink),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _savingNote ? null : _saveSoapNote,
                            style: FilledButton.styleFrom(
                              backgroundColor: _attested
                                  ? _teal
                                  : _teal.withValues(alpha: 0.45),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: _savingNote
                                ? const SizedBox(
                                    width: 18, height: 18,
                                    child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2))
                                : Text(
                                    _attested
                                        ? 'Save & Attest'
                                        : 'Save changes',
                                    style: GoogleFonts.dmSans(
                                      fontSize:   15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],

                      // ── Parent Update ─────────────────────────────────────
                      // Visible when note fields are shown OR a saved update
                      // exists from a previous visit.
                      if (_showNoteFields || _parentUpdate.isNotEmpty) ...[
                        const Divider(height: 1, color: _line),
                        const SizedBox(height: 24),
                        Text(
                          'PARENT UPDATE',
                          style: GoogleFonts.dmSans(
                            fontSize:   12,
                            fontWeight: FontWeight.w600,
                            color:      const Color(0xFF9CA3AF),
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed:
                                (_soapIsEmpty || _parentUpdateLoading)
                                    ? null
                                    : _generateParentUpdate,
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  const Color(0xFF1B2B4B),
                              disabledBackgroundColor:
                                  const Color(0xFF1B2B4B).withAlpha(77),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: _parentUpdateLoading
                                ? const SizedBox(
                                    width: 18, height: 18,
                                    child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2))
                                : const Icon(
                                    Icons.send_to_mobile_outlined,
                                    size: 18),
                            label: Text(
                              _parentUpdateLoading
                                  ? 'Writing update…'
                                  : 'Generate Parent Update',
                              style: const TextStyle(
                                fontSize:   16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        if (_parentUpdateError != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  _parentUpdateError!,
                                  style: const TextStyle(
                                    color:    Color(0xFFEF4444),
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: _generateParentUpdate,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ],
                        if (_parentUpdate.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Focus(
                            onFocusChange: (hasFocus) {
                              if (!hasFocus) _saveParentUpdate();
                            },
                            child: TextField(
                              controller: _parentUpdateController,
                              minLines:   4,
                              maxLines:   null,
                              style: GoogleFonts.dmSans(
                                fontSize: 14,
                                height:   1.6,
                                color:    _ink,
                              ),
                              decoration: InputDecoration(
                                filled:      true,
                                fillColor:   Colors.grey.shade50,
                                contentPadding:
                                    const EdgeInsets.all(12),
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: Colors.grey.shade200),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: Colors.grey.shade200),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: Color(0xFF1B2B4B)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _copyParentUpdate,
                                  icon:  const Icon(
                                      Icons.copy_outlined, size: 16),
                                  label: const Text('Copy'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor:
                                        const Color(0xFF1B2B4B),
                                    side: const BorderSide(
                                        color: Color(0xFF1B2B4B)),
                                    padding:
                                        const EdgeInsets.symmetric(
                                            vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _shareWhatsApp,
                                  icon:  const Icon(
                                      Icons.send_rounded, size: 16),
                                  label:
                                      const Text('Send via WhatsApp'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor:
                                        const Color(0xFF25D366),
                                    padding:
                                        const EdgeInsets.symmetric(
                                            vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 32),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptySessionState() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 32),
            const CueStudyIcon(size: 24),
            const SizedBox(height: 16),
            Text(
              'Use Narrator to document this session first, then generate your report.',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize:  13,
                fontStyle: FontStyle.italic,
                color:     const Color(0xFF8A8A8A),
                height:    1.6,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NarrateSessionScreen(
                    clientId:    widget.clientId ?? '',
                    clientName:  widget.clientName,
                    sessionId:   widget.session['id']?.toString(),
                    sessionDate: widget.session['date']?.toString(),
                  ),
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: _teal,
                side: const BorderSide(color: _teal),
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'Open Narrator',
                style: GoogleFonts.dmSans(
                  fontSize:   14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  int _asInt(dynamic v) =>
      v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;

  // Session context card — only renders trial data/goal/affect rows when
  // values are actually present. Minimal sessions (date only) show just the date.
  Widget _buildSummaryCard(Map<String, dynamic> session) {
    final targetBehaviour =
        (session['target_behaviour'] as String? ?? '').trim();
    final activityName =
        (session['activity_name'] as String? ?? '').trim();
    final attempts  = _asInt(session['attempts']);
    final indep     = _asInt(session['independent_responses']);
    final prompted  = _asInt(session['prompted_responses']);
    final hasTrials = attempts > 0 || indep > 0 || prompted > 0;
    final goalMet   = (session['goal_met']      as String? ?? '').trim();
    final affect    = (session['client_affect'] as String? ?? '').trim();

    final hasDetails = targetBehaviour.isNotEmpty ||
        activityName.isNotEmpty ||
        hasTrials ||
        goalMet.isNotEmpty ||
        affect.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border:       Border.all(color: _line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            session['date']?.toString() ?? 'Unknown date',
            style: GoogleFonts.dmSans(
              fontSize:   14,
              fontWeight: FontWeight.w600,
              color:      _ink,
            ),
          ),
          if (hasDetails) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing:    32,
              runSpacing: 8,
              children: [
                if (targetBehaviour.isNotEmpty)
                  _summaryItem('Goal', targetBehaviour),
                if (activityName.isNotEmpty)
                  _summaryItem('Activity', activityName),
                if (hasTrials)
                  _summaryItem(
                    'Trials',
                    '$attempts total · $indep independent · '
                    '$prompted prompted',
                  ),
                if (goalMet.isNotEmpty)
                  _summaryItem('Goal Met', _formatGoalMet(goalMet)),
                if (affect.isNotEmpty)
                  _summaryItem('Affect', _capitalize(affect)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _soapField(String label, TextEditingController ctrl) => Column(
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
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            minLines: 3,
            maxLines: null,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: Color(0xFF1A1A2E),
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.grey.shade50,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.teal),
              ),
            ),
          ),
        ],
      );

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
