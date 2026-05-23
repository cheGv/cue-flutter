// lib/screens/session_planning_screen.dart
//
// Phase B — "Plan today's session" surface (Prompt 3, Bundle 1, PART B4).
// Seeded with the client's last next-session focus; saves a draft session
// (status = 'planned') or opens it for running. Read/write against the
// sandbox only. The editable form is extracted to [PlanningForm] (pure, no
// Supabase) so it's testable without an initialized client.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repositories/sessions_repository.dart';
import '../theme/cue_color_scheme.dart';
import '../theme/cue_text_styles.dart';
import '../widgets/app_layout.dart';

class SessionPlanningScreen extends StatefulWidget {
  final String clientId;
  final String clientName;
  final String? seedFocus;

  const SessionPlanningScreen({
    super.key,
    required this.clientId,
    required this.clientName,
    this.seedFocus,
  });

  @override
  State<SessionPlanningScreen> createState() => _SessionPlanningScreenState();
}

class _SessionPlanningScreenState extends State<SessionPlanningScreen> {
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Auth-null guard — same pattern as the chart screen.
    if (Supabase.instance.client.auth.currentUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ret = Uri.encodeQueryComponent('/clients/${widget.clientId}');
        Navigator.pushReplacementNamed(context, '/login?return=$ret');
      });
    }
  }

  Future<int?> _save(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _saving) return null;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      return await SessionsRepository().savePlannedSession(
        clientId: widget.clientId,
        clientName: widget.clientName,
        plannedFocus: trimmed,
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't save plan: $e")));
      return null;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onSaveDraft(String text) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final id = await _save(text);
    if (id == null) return;
    messenger.showSnackBar(const SnackBar(content: Text('Plan saved.')));
    navigator.pop(true); // signal the chart to refresh
  }

  Future<void> _onOpenSession(String text) async {
    final navigator = Navigator.of(context);
    final id = await _save(text);
    if (id == null) return;
    // Transition to session-running (SessionCaptureScreen edit mode).
    navigator.pushReplacementNamed('/sessions/$id/edit');
  }

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);
    return AppLayout(
      title: widget.clientName,
      activeRoute: 'roster',
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 768;
          final rr = CueReadingRoom.of(context, isCompact: isCompact);
          final hPad = isCompact ? 16.0 : 24.0;
          return ColoredBox(
            color: cue.chartPaper,
            child: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 48),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _BackToChart(clientId: widget.clientId),
                        const SizedBox(height: 8),
                        Text(
                          widget.clientName,
                          style: rr.name.copyWith(
                            fontSize: 24,
                            color: cue.sienna,
                          ),
                        ),
                        const SizedBox(height: 24),
                        PlanningForm(
                          seedFocus: widget.seedFocus,
                          busy: _saving,
                          onSaveDraft: _onSaveDraft,
                          onOpenSession: _onOpenSession,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BackToChart extends StatelessWidget {
  final String clientId;
  const _BackToChart({required this.clientId});

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);
    final rr = CueReadingRoom.of(context, isCompact: false);
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: () {
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          } else {
            Navigator.pushReplacementNamed(context, '/clients/$clientId');
          }
        },
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_back_rounded, size: 15, color: cue.sienna),
              const SizedBox(width: 6),
              Text('Back to chart', style: rr.historyLink),
            ],
          ),
        ),
      ),
    );
  }
}

/// The editable planning form — pure (no Supabase), so it's unit-testable.
class PlanningForm extends StatefulWidget {
  final String? seedFocus;
  final bool busy;
  final void Function(String text) onSaveDraft;
  final void Function(String text) onOpenSession;

  const PlanningForm({
    super.key,
    required this.seedFocus,
    required this.onSaveDraft,
    required this.onOpenSession,
    this.busy = false,
  });

  @override
  State<PlanningForm> createState() => _PlanningFormState();
}

class _PlanningFormState extends State<PlanningForm> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.seedFocus ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);
    final rr = CueReadingRoom.of(context, isCompact: false);
    final hasSeed = widget.seedFocus?.trim().isNotEmpty ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("PLAN TODAY'S SESSION", style: rr.sectionLabel),
        const SizedBox(height: 14),
        Text("What's the move for today?", style: rr.ladderLabel),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          minLines: 4,
          maxLines: null,
          style: rr.blockBody,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderSide: BorderSide(color: cue.border, width: 0.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: cue.border, width: 0.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: cue.sienna, width: 1),
            ),
            contentPadding: const EdgeInsets.all(14),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          hasSeed
              ? '— this carries forward from your last session'
              : "— no prior intent on file; write today's plan.",
          style: rr.emptyItalic,
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            OutlinedButton(
              onPressed:
                  widget.busy ? null : () => widget.onSaveDraft(_controller.text),
              style: OutlinedButton.styleFrom(
                foregroundColor: cue.sienna,
                side: BorderSide(color: cue.sienna, width: 0.5),
              ),
              child: const Text('Save as draft'),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: widget.busy
                  ? null
                  : () => widget.onOpenSession(_controller.text),
              style: FilledButton.styleFrom(
                backgroundColor: cue.sienna,
                foregroundColor: Colors.white,
              ),
              child: const Text('Open session'),
            ),
          ],
        ),
      ],
    );
  }
}
