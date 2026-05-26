// lib/services/format_drafter_service.dart
//
// Phase C — Cue Mirror, Component Two (Format Drafter).
// Orchestrates a draft: assembles the client's canonical clinical data from the
// repositories, resolves the SLP's lexicon defaults for the template, calls the
// proxy's /format-draft endpoint (locked system prompt server-side, per §13 —
// the client sends only data + references, never a prompt), and persists the
// returned draft to format_drafts. On ANY error before persistence the draft
// is NOT written (no partial drafts). All collaborators are injectable so the
// service is unit-testable without live network / Supabase.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../models/format_draft.dart';
import '../models/format_draft_sentence.dart';
import '../models/substrate.dart';
import '../repositories/citations_repository.dart';
import '../repositories/client_chart_state_repository.dart';
import '../repositories/format_draft_sentences_repository.dart';
import '../repositories/format_drafts_repository.dart';
import '../repositories/format_template_lexicon_defaults_repository.dart';
import '../repositories/format_templates_repository.dart';
import '../repositories/ltg_repository.dart';
import '../repositories/sessions_repository.dart';
import '../repositories/stg_metrics_repository.dart';
import '../repositories/stg_repository.dart';
import '../repositories/substrate_repository.dart';

class FormatDrafterService {
  FormatDrafterService({
    http.Client? client,
    Future<String?> Function()? tokenProvider,
    String baseUrl = _defaultBase,
    FormatTemplatesRepository? templatesRepository,
    FormatDraftsRepository? draftsRepository,
    FormatDraftSentencesRepository? sentencesRepository,
    FormatTemplateLexiconDefaultsRepository? lexiconRepository,
    SessionsRepository? sessionsRepository,
    SubstrateRepository? substrateRepository,
    LtgRepository? ltgRepository,
    StgRepository? stgRepository,
    CitationsRepository? citationsRepository,
    StgMetricsRepository? metricsRepository,
    ClientChartStateRepository? chartStateRepository,
  })  : _client = client ?? http.Client(),
        _tokenProvider = tokenProvider ?? _defaultToken,
        _base = baseUrl,
        _templatesRepo = templatesRepository ?? FormatTemplatesRepository(),
        _draftsRepo = draftsRepository ?? FormatDraftsRepository(),
        _sentencesRepo =
            sentencesRepository ?? FormatDraftSentencesRepository(),
        _lexiconRepo =
            lexiconRepository ?? FormatTemplateLexiconDefaultsRepository(),
        _sessionsRepo = sessionsRepository ?? SessionsRepository(),
        _substrateRepo = substrateRepository ?? SubstrateRepository(),
        _ltgRepo = ltgRepository ?? LtgRepository(),
        _stgRepo = stgRepository ?? StgRepository(),
        _citationsRepo = citationsRepository ?? CitationsRepository(),
        _metricsRepo = metricsRepository ?? StgMetricsRepository(),
        _chartStateRepo = chartStateRepository ?? ClientChartStateRepository();

  static const _defaultBase = 'https://cue-ai-proxy.onrender.com';
  // Drafting reads a whole client's record through an LLM — allow a long ceiling.
  static const _draftTimeout = Duration(seconds: 120);
  // Export renders + uploads a .docx server-side; allow a generous ceiling.
  static const _exportTimeout = Duration(seconds: 60);

  final http.Client _client;
  final Future<String?> Function() _tokenProvider;
  final String _base;
  final FormatTemplatesRepository _templatesRepo;
  final FormatDraftsRepository _draftsRepo;
  final FormatDraftSentencesRepository _sentencesRepo;
  final FormatTemplateLexiconDefaultsRepository _lexiconRepo;
  final SessionsRepository _sessionsRepo;
  final SubstrateRepository _substrateRepo;
  final LtgRepository _ltgRepo;
  final StgRepository _stgRepo;
  final CitationsRepository _citationsRepo;
  final StgMetricsRepository _metricsRepo;
  final ClientChartStateRepository _chartStateRepo;

  static Future<String?> _defaultToken() async =>
      Supabase.instance.client.auth.currentSession?.accessToken;

  /// Pull every canonical primitive the drafter may draw on for this client,
  /// session data scoped to [after]..[before] (null = unbounded). Returns the
  /// `canonical_data` map the proxy expects.
  Future<Map<String, dynamic>> assembleCanonicalContext(
    String clientId, {
    DateTime? after,
    DateTime? before,
  }) async {
    final chartState = await _chartStateRepo.loadForClient(clientId);
    final sessions = await _sessionsRepo
        .loadForClientFiltered(clientId, after: after, before: before);
    final cells = await _substrateRepo.loadCellsForClient(clientId);
    final ltgs = await _ltgRepo.listForClient(clientId);
    final stgs = await _stgRepo.listForClient(clientId);
    final citations = await _citationsRepo.loadCitationsForClient(clientId);

    // Metrics are per-STG (no per-client loader); gather across this client's
    // STGs, oldest-first within each.
    final metrics = <Map<String, dynamic>>[];
    for (final stg in stgs) {
      final rows = await _metricsRepo.loadMetricsForStg(stg.id);
      metrics.addAll(rows.map((m) => m.toJson()));
    }

    return {
      'client_meta': chartState?.toJson() ?? const {},
      'substrate_cells': cells.map(_cellToMap).toList(),
      'long_term_goals': ltgs, // already raw maps
      'short_term_goals': stgs.map((s) => s.toJson()).toList(),
      'sessions': sessions.map((s) => s.toJson()).toList(),
      'citations': citations.map((c) => c.toJson()).toList(),
      'metrics': metrics,
    };
  }

  /// The SLP's swap/keep decisions for this template, shaped for the proxy.
  Future<List<Map<String, dynamic>>> resolveLexiconDefaults(
      String templateId) async {
    final defaults = await _lexiconRepo.listForTemplate(templateId);
    return defaults
        .map((d) => {
              'forbidden_term': d.forbiddenTerm,
              'decision': d.decision,
              'replacement_term': d.replacementTerm,
            })
        .toList();
  }

  /// Orchestrate a draft end-to-end: assemble context + lexicon, POST to
  /// /format-draft, persist on success, return the stored draft. Throws
  /// [FormatDrafterException] on any error; nothing is persisted on error.
  Future<FormatDraft> requestDraft({
    required String templateId,
    required String clientId,
    required String preset, // weekly | monthly | quarterly | all_sessions | custom
    DateTime? customStart,
    DateTime? customEnd,
  }) async {
    final token = await _tokenProvider();
    if (token == null) throw FormatDrafterException('You are not signed in.');

    final template = await _templatesRepo.get(templateId);
    if (template == null) {
      throw FormatDrafterException('That format template could not be found.');
    }

    final range = _resolveRange(preset, customStart, customEnd);
    final canonical = await assembleCanonicalContext(
      clientId,
      after: range.start,
      before: range.end,
    );
    final lexicon = await resolveLexiconDefaults(templateId);

    final body = {
      'template_id': templateId,
      'client_id': clientId,
      'date_range': {
        'preset': preset,
        'start': range.start?.toIso8601String(),
        'end': range.end?.toIso8601String(),
      },
      'locked_template': template.extractedTemplate.toJson(),
      'lexicon_defaults': lexicon,
      'canonical_data': canonical,
    };

    final resp = await _client
        .post(
          Uri.parse('$_base/format-draft'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        )
        .timeout(_draftTimeout);

    if (resp.statusCode != 200) {
      throw FormatDrafterException(_errorMessage(resp));
    }

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;

    // Phase D — the proxy is now the authoritative writer: it has already
    // persisted format_drafts (+ the sentence corpus) atomically and returns
    // the new draft_id. We read the persisted draft back rather than creating
    // it client-side (FormatDraftsRepository.create is retained but deprecated).
    final draftId = (decoded['draft_id'] as String?) ?? '';
    if (draftId.isEmpty) {
      throw FormatDrafterException(
          'The draft was generated but did not return an id. Please try again.');
    }
    final draft = await _draftsRepo.get(draftId);
    if (draft == null) {
      throw FormatDrafterException(
          'The generated draft could not be loaded. Please try again.');
    }
    return draft;
  }

  /// Reload a persisted draft + its sentence corpus (after generation or edit).
  Future<({FormatDraft? draft, List<FormatDraftSentence> sentences})> refresh(
      String draftId) async {
    final draft = await _draftsRepo.get(draftId);
    final sentences = await _sentencesRepo.listForDraft(draftId);
    return (draft: draft, sentences: sentences);
  }

  /// Autosave an uncommitted edit to text_in_progress. Does NOT sync to export.
  Future<FormatDraftSentence> autosaveSentence(
          String sentenceId, String text) =>
      _sentencesRepo.update(sentenceId, {
        'text_in_progress': text,
        'edited_at': DateTime.now().toUtc().toIso8601String(),
      });

  /// Commit a sentence edit: promote text_in_progress → text with [status]
  /// (clinician_edited | clinician_authored), then SYNC the parent section's
  /// content into format_drafts.draft_sections so Component Four's Word export
  /// reflects exactly what the clinician approved. Autosave never calls this.
  Future<FormatDraftSentence> commitSentenceEdit({
    required String draftId,
    required String sentenceId,
    required String sectionName,
    required String newText,
    required String status,
    List<dynamic>? sourceClaims, // null when clinician_authored
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final updated = await _sentencesRepo.update(sentenceId, {
      'text': newText,
      'text_in_progress': null,
      'status': status,
      'source_claims': sourceClaims,
      'saved_at': now,
      'edited_at': now,
    });
    await _syncSectionToExport(draftId, sectionName);
    return updated;
  }

  /// Author a static section as a single clinician-authored sentence (Part F),
  /// then sync it to the export.
  Future<FormatDraftSentence> authorStaticSection({
    required String draftId,
    required String sectionName,
    required String templateId,
    required String text,
  }) async {
    final created = await _sentencesRepo.create(
      draftId: draftId,
      sectionName: sectionName,
      sentenceOrder: 0,
      text: text,
      templateId: templateId,
      status: 'clinician_authored',
    );
    await _syncSectionToExport(draftId, sectionName);
    return created;
  }

  /// Rebuild a section's draft_sections.content from its committed sentences
  /// (in order) and write it back to format_drafts — the edit→export sync.
  Future<void> _syncSectionToExport(String draftId, String sectionName) async {
    final draft = await _draftsRepo.get(draftId);
    if (draft == null) return;
    final sentences = await _sentencesRepo.listForSection(draftId, sectionName);
    final rebuilt = sentences
        .map((s) => s.text.trim())
        .where((t) => t.isNotEmpty)
        .join(' ');
    final sections = draft.draftSections.map((sec) {
      final m = sec.toJson();
      if (sec.sectionName == sectionName) m['content'] = rebuilt;
      return m;
    }).toList();
    await _draftsRepo.update(draftId, {'draft_sections': sections});
  }

  /// Export a persisted draft to a downloadable file via the proxy. Sends only
  /// { draft_id, format } — no prompt, per §13. Returns the signed download URL
  /// + filename. The proxy is the single authoritative writer of the export
  /// metadata (exported_at / export_path / export_format) on the format_drafts
  /// row, so the client does not duplicate that write; a later repository load
  /// reflects it.
  Future<({String signedUrl, String filename})> exportDraft({
    required String draftId,
    String format = 'docx',
  }) async {
    final token = await _tokenProvider();
    if (token == null) throw FormatDrafterException('You are not signed in.');

    final resp = await _client
        .post(
          Uri.parse('$_base/format-draft-export'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'draft_id': draftId, 'format': format}),
        )
        .timeout(_exportTimeout);

    if (resp.statusCode != 200) {
      throw FormatDrafterException(_errorMessage(resp));
    }

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    // Phase D wk3 (E3) — sandbox/debug-only indicator of which renderer path the
    // proxy took (v2_content_fill | v1_no_geometry | v1_no_slots | v1_no_content).
    // assert() body runs in debug builds only; stripped from release.
    assert(() {
      final rp = decoded['render_path'];
      final w = decoded['warning'];
      debugPrint('[Cue Mirror] export render_path=$rp${w != null ? '  warning=$w' : ''}');
      return true;
    }());
    final url = (decoded['signed_url'] as String?) ?? '';
    if (url.isEmpty) {
      throw FormatDrafterException('The export did not return a download link.');
    }
    final filename = (decoded['filename'] as String?) ?? 'report.docx';
    return (signedUrl: url, filename: filename);
  }

  ({DateTime? start, DateTime? end}) _resolveRange(
      String preset, DateTime? customStart, DateTime? customEnd) {
    final now = DateTime.now();
    switch (preset) {
      case 'weekly':
        return (start: now.subtract(const Duration(days: 7)), end: now);
      case 'monthly':
        return (start: now.subtract(const Duration(days: 30)), end: now);
      case 'quarterly':
        return (start: now.subtract(const Duration(days: 90)), end: now);
      case 'custom':
        return (start: customStart, end: customEnd);
      case 'all_sessions':
      default:
        return (start: null, end: null);
    }
  }

  // SubstrateCell has no toJson(); project the fields the drafter needs (content
  // + layer + tags + source excerpts, each traceable by cell id).
  Map<String, dynamic> _cellToMap(SubstrateCell c) => {
        'id': c.id,
        'layer': c.layer?.toJson(),
        'sub_category': c.subCategory,
        'content': c.content,
        'attributes': c.attributes.map((a) => a.toJson()).toList(),
        'tags': c.tags.map((t) => t.tag).toList(),
        'sources': c.sources
            .map((s) => {
                  'source_type': s.sourceType?.toJson(),
                  'source_ref': s.sourceRef,
                  'excerpt': s.excerpt,
                  'date': s.date?.toIso8601String(),
                })
            .toList(),
      };

  String _errorMessage(http.Response resp) {
    try {
      final b = jsonDecode(resp.body) as Map<String, dynamic>;
      return (b['error'] as String?) ??
          'Request did not complete (${resp.statusCode}).';
    } catch (_) {
      return 'Request did not complete (${resp.statusCode}).';
    }
  }
}

class FormatDrafterException implements Exception {
  final String message;
  FormatDrafterException(this.message);
  @override
  String toString() => message;
}
