// lib/screens/format_mirror_test_screen.dart
//
// THROWAWAY debug harness (Phase D week 2, Cue Mirror format-mirroring engine).
// Reachable ONLY via the kDebugMode-gated route '/debug/mirror-test' (main.dart);
// tree-shaken out of release builds. Lets the clinician/dev pick an uploaded
// template, regenerate a verbatim .docx through the Mirror engine
// (/format-mirror-render), see the captured structural breakdown, and download
// the result to compare side-by-side against the original in Microsoft Word
// (the user-driven visual gate — Decision 3).
//
// GUARDRAIL (mirrors recall_resolver_test_screen.dart): the render action is
// DISABLED unless the launched Supabase target is the sandbox ref (read from
// app_config). Even pointed at production it refuses to run.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../models/format_template.dart';
import '../repositories/format_templates_repository.dart';
import '../services/format_extractor_service.dart';

class FormatMirrorTestScreen extends StatefulWidget {
  const FormatMirrorTestScreen({super.key});

  @override
  State<FormatMirrorTestScreen> createState() => _FormatMirrorTestScreenState();
}

class _FormatMirrorTestScreenState extends State<FormatMirrorTestScreen> {
  final _repo = FormatTemplatesRepository();
  final _service = FormatExtractorService();
  final _swapFrom = TextEditingController();
  final _swapTo = TextEditingController();

  List<FormatTemplate> _templates = const [];
  String? _selectedId;
  bool _loading = false;
  bool _rendering = false;
  String? _error;
  MirrorRenderResult? _result;

  bool get _isSandbox => kSupabaseUrl.contains(kSandboxProjectRef);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _swapFrom.dispose();
    _swapTo.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _repo.listForUser();
      setState(() {
        _templates = list;
        _loading = false;
        _selectedId ??= list.isNotEmpty ? list.first.id : null;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load templates: $e';
        _loading = false;
      });
    }
  }

  Future<void> _render() async {
    final id = _selectedId;
    if (id == null) return;
    setState(() {
      _rendering = true;
      _error = null;
      _result = null;
    });
    try {
      final r = await _service.renderMirrorTest(
        templateId: id,
        swapFrom: _swapFrom.text.trim().isEmpty ? null : _swapFrom.text.trim(),
        swapTo: _swapTo.text.trim().isEmpty ? null : _swapTo.text.trim(),
      );
      setState(() {
        _result = r;
        _rendering = false;
      });
      if (r.signedUrl.isNotEmpty) {
        await launchUrl(Uri.parse(r.signedUrl), webOnlyWindowName: '_blank');
      }
    } catch (e) {
      setState(() {
        _error = 'Render failed: $e';
        _rendering = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canRender = _isSandbox && _selectedId != null && !_rendering;
    return Scaffold(
      appBar: AppBar(title: const Text('Mirror test · sandbox debug')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _envBanner(),
            const SizedBox(height: 20),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              _templatePicker(),
            const SizedBox(height: 20),
            _swapFields(),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: canRender ? _render : null,
              icon: _rendering
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome),
              label: Text(_rendering ? 'Rendering…' : 'Regenerate mirror .docx'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_error!, style: const TextStyle(color: Color(0xFFB00020))),
              ),
            if (_result != null) _summaryView(_result!),
          ],
        ),
      ),
    );
  }

  Widget _envBanner() {
    final ok = _isSandbox;
    final color = ok ? const Color(0xFF1A7E5C) : const Color(0xFFB00020);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle_outline : Icons.warning_amber, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ok
                  ? 'Sandbox target ($kSandboxProjectRef) — Mirror test enabled.'
                  : 'NON-SANDBOX target — Mirror test DISABLED.\n$kSupabaseUrl',
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _templatePicker() {
    if (_templates.isEmpty) {
      return const Text('No templates yet — upload one through the format flow first.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Template', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        DropdownButton<String>(
          isExpanded: true,
          value: _selectedId,
          items: _templates
              .map((t) => DropdownMenuItem<String>(
                    value: t.id,
                    child: Text(
                      '${t.name.isEmpty ? '(unnamed)' : t.name}  ·  ${t.formatType}  ·  ${t.confirmationStatus}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _selectedId = v),
        ),
      ],
    );
  }

  Widget _swapFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Optional content swap — proves content can differ while the format stays identical',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _swapFrom,
                decoration: const InputDecoration(labelText: 'Replace text', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _swapTo,
                decoration: const InputDecoration(labelText: 'With', border: OutlineInputBorder()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _summaryView(MirrorRenderResult r) {
    Map<String, dynamic> sub(String key) =>
        r.summary[key] is Map ? Map<String, dynamic>.from(r.summary[key] as Map) : const {};
    final ps = sub('page_setup');
    final df = sub('default_font');
    final counts = sub('counts');
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Structural breakdown', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('File:  ${r.filename}'),
          Text('Page:  ${ps['width']} × ${ps['height']}  ${ps['orientation']}'),
          Text('Default font:  ${df['family']}  ${df['size']}'),
          Text('Tables: ${counts['tables']}   Images: ${counts['images']}   Main-table columns: ${counts['main_table_columns']}'),
          const SizedBox(height: 12),
          if (r.signedUrl.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => launchUrl(Uri.parse(r.signedUrl), webOnlyWindowName: '_blank'),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download again'),
            ),
          const SizedBox(height: 8),
          const Text(
            'Open this file in Microsoft Word and compare it side-by-side with the original — '
            'page setup, table grid, fonts, and any logo should match exactly.',
            style: TextStyle(fontSize: 12, color: Color(0xFF6B6B6B)),
          ),
        ],
      ),
    );
  }
}
