// lib/screens/assessment_generate_debug_screen.dart
//
// TEMP kDebugMode-gated dev trigger for Piece 2 Step 2 (requestAssessmentDraft).
// Generates a real assessment draft for the sandbox "Mythos" voice assessment
// through the app's OWN FormatDrafterService, against the LOCAL proxy
// (--dart-define=PROXY_BASE=http://localhost:3001) + sandbox login, then opens
// the new draft in the existing editable surface (Piece 3). Not wired into any
// production navigation; tree-shaken from release builds. Remove once Step 3
// (the real assessment-initiation UI) lands.

import 'package:flutter/material.dart';

import '../services/format_drafter_service.dart';

class AssessmentGenerateDebugScreen extends StatefulWidget {
  const AssessmentGenerateDebugScreen({super.key});

  @override
  State<AssessmentGenerateDebugScreen> createState() =>
      _AssessmentGenerateDebugScreenState();
}

class _AssessmentGenerateDebugScreenState
    extends State<AssessmentGenerateDebugScreen> {
  // Sandbox "Mythos" voice assessment — the one proven in the bridge handshake.
  static const _clientId = '803344ea-c6ce-45f4-bd8e-70fbe4a166c9';
  static const _assessmentId = '592a63f1-a780-4323-8f8d-181e497511b8';
  static const _protocol = 'voice';
  static const _templateId = '4aff4466-4ad2-4967-b345-16ca41fe0222'; // AIISH

  bool _busy = true;
  String _status =
      'Generating assessment draft via requestAssessmentDraft…\n'
      '(local proxy + sandbox; this calls the LLM, ~30-60s)';
  String? _draftId;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final draft = await FormatDrafterService().requestAssessmentDraft(
        templateId: _templateId,
        clientId: _clientId,
        protocol: _protocol,
        assessmentId: _assessmentId,
      );
      if (!mounted) return;
      setState(() {
        _draftId = draft.id;
        _busy = false;
        _status = 'Assessment draft created: ${draft.id}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'FAILED: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DEBUG - assessment generate')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy) const CircularProgressIndicator(),
              const SizedBox(height: 16),
              SelectableText(_status, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              if (_draftId != null)
                FilledButton(
                  onPressed: () => Navigator.of(context).pushReplacementNamed(
                    '/clients/$_clientId/draft-report/view/$_draftId',
                  ),
                  child: const Text('Open it in the editable surface'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
