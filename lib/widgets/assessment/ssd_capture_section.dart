// lib/widgets/assessment/ssd_capture_section.dart
//
// Phase 4.0.7.24 — ROUGH STUB. Speech Sound Disorder capture surface.
// Same shape as VoiceCaptureSection: five sub-area chips, expandable
// text-field placeholders, "Run instrument" buttons. Clinical
// instrument fields (GFTA, KLPA, DEAP integration) are authored in
// 4.0.7.24b as a separate commit.
//
// The two stubs share enough pattern to extract a shared
// AssessmentCaptureSection base widget once a third domain ships
// (4.0.7.24c onward) — flagged for that commit.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color _ink       = Color(0xFF0E1C36);
const Color _inkGhost  = Color(0xFF6B7690);
const Color _line      = Color(0xFFE6DDCA);
const Color _teal      = Color(0xFF2A8F84);
const Color _tealSoft  = Color(0xFFD6E8E5);

class SsdCaptureSection extends StatefulWidget {
  final String clientId;
  const SsdCaptureSection({super.key, required this.clientId});

  @override
  State<SsdCaptureSection> createState() => _SsdCaptureSectionState();
}

class _SsdCaptureSectionState extends State<SsdCaptureSection> {
  static const List<({String code, String label})> _modes = [
    (code: 'articulation',     label: 'Articulation'),
    (code: 'phonology',        label: 'Phonology'),
    (code: 'stimulability',    label: 'Stimulability'),
    (code: 'intelligibility',  label: 'Intelligibility'),
    (code: 'oromotor',         label: 'Oromotor'),
  ];

  String? _expanded;
  final Map<String, TextEditingController> _ctrls = {
    for (final m in _modes) m.code: TextEditingController(),
  };

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _runInstrument(String mode) async {
    try {
      await Supabase.instance.client.from('assessment_entries').insert({
        'client_id':     widget.clientId,
        'clinical_area': 'speech-sound-disorders',
        'mode':          mode,
        'payload':       {'note': _ctrls[mode]?.text.trim() ?? ''},
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Saved $mode capture.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SPEECH SOUND DISORDER ASSESSMENT',
          style: GoogleFonts.syne(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _teal,
              letterSpacing: 1.6),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in _modes)
              _chip(m.code, m.label, _expanded == m.code),
          ],
        ),
        if (_expanded != null) ...[
          const SizedBox(height: 12),
          _expandedPanel(_expanded!),
        ],
      ],
    );
  }

  Widget _chip(String code, String label, bool active) {
    return GestureDetector(
      onTap: () =>
          setState(() => _expanded = active ? null : code),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? _tealSoft.withValues(alpha: 0.55) : Colors.white,
          border: Border.all(color: active ? _teal : _line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(label,
            style: GoogleFonts.dmSans(
                fontSize: 12,
                color: active ? _teal : _ink,
                fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _expandedPanel(String mode) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Capture observations for this section — instrument '
            'fields coming in 4.0.7.24b.',
            style: GoogleFonts.dmSans(
                fontSize: 12,
                color: _inkGhost,
                fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrls[mode],
            maxLines: 3,
            style: GoogleFonts.dmSans(fontSize: 13, color: _ink),
            decoration: const InputDecoration(
              hintText: 'Observations…',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => _runInstrument(mode),
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('Run instrument'),
              style: FilledButton.styleFrom(
                backgroundColor: _teal,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
