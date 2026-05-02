// lib/screens/live_entry_fluency_screen.dart
//
// Phase 4.0.4 — Layer 03a live entry surface for developmental stuttering.
//
// In-room capture surface. Tablet-optimised. Big tap targets. The SLP
// drives the syllable counter and disfluency tiles while the child is
// speaking — minimum screen time per second of clinician attention.
//
// %SS is computed reactively on every count change via Cue Calc
// (services/cue_calc.dart) — pure local math, no LLM in this path
// (CLAUDE.md §13.14, §14.6).
//
// Persistence:
//   "save & resume later"      → sessions.population_payload with
//                                 live_entry_state = 'in_progress'.
//                                 No assessment_entries row yet.
//   "complete sample · save"   → sessions.population_payload with
//                                 live_entry_state = 'complete' AND a
//                                 new assessment_entries row with
//                                 mode = 'live_entry'.
//
// Recording timer is visual chrome only — counts elapsed seconds since
// screen mount. No audio access. Audio capture is a separate phase.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/cue_calc.dart';
import '../theme/cue_phase4_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Disfluency catalog — locked Phase 4.0.4.
// `bumpsStuttered` is true for stuttering-like disfluencies (per Yairi).
// `dimmed` matches the visual cue: dimmed tiles are NOT stuttering-like.
// ─────────────────────────────────────────────────────────────────────────────
class _DisfluencyDef {
  final String key;
  final String label;
  final bool bumpsStuttered;
  final bool dimmed;
  const _DisfluencyDef({
    required this.key,
    required this.label,
    required this.bumpsStuttered,
    required this.dimmed,
  });
}

const List<_DisfluencyDef> _disfluencies = [
  _DisfluencyDef(key: 'part_word',   label: 'part-word repetition', bumpsStuttered: true,  dimmed: false),
  _DisfluencyDef(key: 'prolongation',label: 'prolongation',         bumpsStuttered: true,  dimmed: false),
  _DisfluencyDef(key: 'block',       label: 'block',                bumpsStuttered: true,  dimmed: false),
  _DisfluencyDef(key: 'whole_word',  label: 'whole-word repetition',bumpsStuttered: true,  dimmed: false),
  _DisfluencyDef(key: 'interjection',label: 'interjection · other', bumpsStuttered: false, dimmed: true),
  _DisfluencyDef(key: 'revision',    label: 'revision · other',     bumpsStuttered: false, dimmed: true),
];

const List<({String key, String label})> _accessoryBehaviours = [
  (key: 'eye_blink',       label: 'eye blink'),
  (key: 'facial_tension',  label: 'facial tension'),
  (key: 'head_movement',   label: 'head movement'),
  (key: 'limb_movement',   label: 'limb movement'),
  (key: 'audible_tension', label: 'audible tension'),
];

// ─────────────────────────────────────────────────────────────────────────────

class LiveEntryFluencyScreen extends StatefulWidget {
  final String clientId;
  final String clientName;

  /// Optional context label rendered as the header subtitle, e.g.
  /// "conversational sample with mother". Kept simple for V1 — a future
  /// session may expand into a structured context object.
  final String? sampleContext;

  const LiveEntryFluencyScreen({
    super.key,
    required this.clientId,
    required this.clientName,
    this.sampleContext,
  });

  @override
  State<LiveEntryFluencyScreen> createState() =>
      _LiveEntryFluencyScreenState();
}

class _LiveEntryFluencyScreenState extends State<LiveEntryFluencyScreen> {
  final _supabase = Supabase.instance.client;

  // Counts ────────────────────────────────────────────────────────────────
  int _totalSyllables = 0;
  final Map<String, int> _disfluencyCounts = {
    for (final d in _disfluencies) d.key: 0,
  };
  final Set<String> _accessory = {};

  // Recording timer (visual chrome only — no audio) ───────────────────────
  Timer? _timer;
  int _elapsedSeconds = 0;

  // Persistence state ─────────────────────────────────────────────────────
  int? _sessionId; // sessions.id (bigint) — null until first save
  bool _saving = false;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ── Derived metrics ─────────────────────────────────────────────────────

  int get _stuttered {
    int sum = 0;
    for (final d in _disfluencies) {
      if (d.bumpsStuttered) sum += _disfluencyCounts[d.key] ?? 0;
    }
    return sum;
  }

  double get _percentSS => computePercentSyllablesStuttered(
        stutteredSyllables: _stuttered,
        totalSyllables: _totalSyllables,
      );

  // ── Counter mutations ───────────────────────────────────────────────────

  void _bumpSyllable(int delta) {
    setState(() {
      _totalSyllables = (_totalSyllables + delta).clamp(0, 1 << 30);
    });
  }

  void _tapDisfluency(String key) {
    setState(() {
      _disfluencyCounts[key] = (_disfluencyCounts[key] ?? 0) + 1;
    });
  }

  void _undoDisfluency(String key) {
    setState(() {
      final v = (_disfluencyCounts[key] ?? 0) - 1;
      _disfluencyCounts[key] = v < 0 ? 0 : v;
    });
  }

  void _toggleAccessory(String key) {
    setState(() {
      if (_accessory.contains(key)) {
        _accessory.remove(key);
      } else {
        _accessory.add(key);
      }
    });
  }

  // ── Payload ─────────────────────────────────────────────────────────────

  Map<String, dynamic> _buildPayload(String state) {
    return {
      'mode': 'live_entry',
      'live_entry_state': state, // 'in_progress' | 'complete'
      'sample_context': widget.sampleContext,
      'duration_seconds': _elapsedSeconds,
      'total_syllables': _totalSyllables,
      'stuttered_syllables': _stuttered,
      'percent_ss': _percentSS,
      'disfluency_counts': Map<String, int>.from(_disfluencyCounts),
      'accessory_behaviours_observed': _accessory.toList()..sort(),
    };
  }

  // ── Persistence ─────────────────────────────────────────────────────────

  Future<void> _save({required bool completing}) async {
    if (_saving) return;
    setState(() => _saving = true);

    final state = completing ? 'complete' : 'in_progress';
    final payload = _buildPayload(state);
    final uid = _supabase.auth.currentUser?.id;
    final dateStr = DateTime.now().toIso8601String().substring(0, 10);

    try {
      // 1. sessions row — INSERT first time, UPDATE on subsequent saves.
      if (_sessionId == null) {
        final inserted = await _supabase
            .from('sessions')
            .insert({
              'client_id':          widget.clientId,
              'date':               dateStr,
              'user_id':            ?uid,
              'population_payload': payload,
            })
            .select('id')
            .single();
        _sessionId = (inserted['id'] as num).toInt();
      } else {
        await _supabase
            .from('sessions')
            .update({'population_payload': payload})
            .eq('id', _sessionId!);
      }

      // 2. assessment_entries row — only on completion.
      if (completing) {
        try {
          await _supabase.from('assessment_entries').insert({
            'client_id':       widget.clientId,
            'session_id':      _sessionId,
            'mode':            'live_entry',
            'population_type': 'developmental_stuttering',
            'payload':         payload,
            'created_by':      ?uid,
          });
        } catch (e) {
          // Sessions update already landed — surface the inconsistency
          // honestly rather than silently claiming success.
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'Sample saved on the session row, but the assessment record failed: $e'),
              duration: const Duration(seconds: 6),
            ));
          }
          rethrow;
        }
      }

      if (!mounted) return;
      setState(() => _completed = completing);
      if (completing) {
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Saved — resume any time from this client\'s chart.'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not save: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCuePaper,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(),
                  const SizedBox(height: 24),
                  _heroTiles(),
                  const SizedBox(height: 16),
                  _syllableCounterRow(),
                  const SizedBox(height: 22),
                  _disfluencyHeader(),
                  const SizedBox(height: 12),
                  _disfluencyGrid(),
                  const SizedBox(height: 6),
                  Text(
                    'long-press a tile to undo a count',
                    style: TextStyle(fontSize: 12, color: kCueEyebrowInk),
                  ),
                  const SizedBox(height: 22),
                  _accessoryBehavioursSection(),
                  const SizedBox(height: 24),
                  Container(
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: kCueBorder, width: 0.5),
                      ),
                    ),
                    padding: const EdgeInsets.only(top: 16),
                    child: _bottomActions(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────

  Widget _header() {
    final mins = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'live · speech sample',
                style: TextStyle(
                  fontSize: 11,
                  color: kCueEyebrowInk,
                  letterSpacing: kCueEyebrowLetterSpacing(11),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.clientName,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 22,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w600,
                  color: kCueInk,
                  height: 1.1,
                ),
              ),
              if (widget.sampleContext != null &&
                  widget.sampleContext!.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  widget.sampleContext!,
                  style: TextStyle(fontSize: 13, color: kCueSubtitleInk),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: kCueAmber,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'recording · $mins:$secs',
              style: const TextStyle(
                fontSize: 13,
                color: kCueAmberDeep,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Hero tiles ──────────────────────────────────────────────────────────

  Widget _heroTiles() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 1,
          child: _heroTile(
            eyebrow: 'total syllables',
            value: _totalSyllables.toString(),
            background: kCuePaper,
            valueColor: kCueInk,
            eyebrowColor: kCueEyebrowInk,
            border: true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 1,
          child: _heroTile(
            eyebrow: 'stuttered',
            value: _stuttered.toString(),
            background: kCuePaper,
            valueColor: kCueInk,
            eyebrowColor: kCueEyebrowInk,
            border: true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: _heroTile(
            eyebrow: '%SS · live',
            value: _percentSS.toStringAsFixed(1),
            background: kCueAmberSurface,
            valueColor: kCueAmberText,
            eyebrowColor: kCueAmberDeeper,
            border: false,
          ),
        ),
      ],
    );
  }

  Widget _heroTile({
    required String eyebrow,
    required String value,
    required Color background,
    required Color valueColor,
    required Color eyebrowColor,
    required bool border,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(kCueTileRadius),
        border: border
            ? Border.all(color: kCueBorder, width: kCueCardBorderW)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            style: TextStyle(
              fontSize: 11,
              color: eyebrowColor,
              letterSpacing: kCueEyebrowLetterSpacing(11),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.playfairDisplay(
              fontSize: 30,
              fontWeight: FontWeight.w600,
              color: valueColor,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  // ── Syllable counter row ────────────────────────────────────────────────

  Widget _syllableCounterRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: kCuePaper,
        borderRadius: BorderRadius.circular(kCueTileRadius),
        border: Border.all(color: kCueBorder, width: kCueCardBorderW),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'tap each syllable as you hear it',
                  style: TextStyle(
                    fontSize: 11,
                    color: kCueEyebrowInk,
                    letterSpacing: kCueEyebrowLetterSpacing(11),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'syllable counter · drives the denominator',
                  style: TextStyle(fontSize: 13, color: kCueSubtitleInk),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Minus
          GestureDetector(
            onTap: () => _bumpSyllable(-1),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: kCueSurface,
                shape: BoxShape.circle,
                border: Border.all(color: kCueBorder, width: kCueCardBorderW),
              ),
              child: const Center(
                child: Text(
                  '−',
                  style: TextStyle(fontSize: 18, color: kCueMutedInk),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Count
          Container(
            constraints: const BoxConstraints(minWidth: 70),
            alignment: Alignment.center,
            child: Text(
              _totalSyllables.toString(),
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                color: kCueInk,
                height: 1.0,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Plus
          GestureDetector(
            onTap: () => _bumpSyllable(1),
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: kCueAmber,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text(
                  '+',
                  style: TextStyle(
                    fontSize: 24,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Disfluency grid ─────────────────────────────────────────────────────

  Widget _disfluencyHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'stuttering-like disfluencies',
          style: TextStyle(
            fontSize: 11,
            color: kCueEyebrowInk,
            letterSpacing: kCueEyebrowLetterSpacing(11),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'tap to count · long-press to undo · these add to the stuttered total',
          style: TextStyle(fontSize: 13, color: kCueSubtitleInk),
        ),
      ],
    );
  }

  Widget _disfluencyGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const cols = 3;
        const gap = 10.0;
        final tileWidth = (constraints.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: _disfluencies
              .map((d) => SizedBox(
                    width: tileWidth,
                    child: _disfluencyTile(d),
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _disfluencyTile(_DisfluencyDef d) {
    final count = _disfluencyCounts[d.key] ?? 0;
    final opacity = d.dimmed ? 0.55 : 1.0;
    return Opacity(
      opacity: opacity,
      child: GestureDetector(
        onTap: () => _tapDisfluency(d.key),
        onLongPress: () => _undoDisfluency(d.key),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: kCueSurface,
            borderRadius: BorderRadius.circular(kCueTileRadius),
            border: Border.all(color: kCueBorderStrong, width: kCueCardBorderW),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                d.label,
                style: const TextStyle(
                  fontSize: 11,
                  color: kCueInk,
                  height: 1.3,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                count.toString(),
                style: GoogleFonts.playfairDisplay(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  color: kCueInk,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Accessory behaviours ────────────────────────────────────────────────

  Widget _accessoryBehavioursSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'accessory behaviours observed',
          style: TextStyle(
            fontSize: 11,
            color: kCueEyebrowInk,
            letterSpacing: kCueEyebrowLetterSpacing(11),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _accessoryBehaviours.map((opt) {
            final selected = _accessory.contains(opt.key);
            return GestureDetector(
              onTap: () => _toggleAccessory(opt.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? kCueAmberSurface : kCueSurface,
                  borderRadius: BorderRadius.circular(kCueChipRadius),
                  border: Border.all(
                    color: selected ? kCueAmber : kCueBorder,
                    width: selected ? 1.2 : kCueCardBorderW,
                  ),
                ),
                child: Text(
                  opt.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: selected ? kCueAmberText : kCueEyebrowInk,
                    fontWeight:
                        selected ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Bottom actions ──────────────────────────────────────────────────────

  Widget _bottomActions() {
    return Row(
      children: [
        Expanded(
          flex: 1,
          child: GestureDetector(
            onTap: _saving || _completed
                ? null
                : () => _save(completing: false),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(kCueTileRadius),
                border:
                    Border.all(color: kCueBorder, width: kCueCardBorderW),
              ),
              child: Text(
                'save & resume later',
                style: TextStyle(
                  fontSize: 14,
                  color: kCueMutedInk,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: GestureDetector(
            onTap: _saving || _completed
                ? null
                : () => _save(completing: true),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: kCueInk,
                borderRadius: BorderRadius.circular(kCueTileRadius),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text(
                      'complete sample · save',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
