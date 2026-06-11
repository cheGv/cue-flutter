// lib/widgets/assessment/feeding_primitives.dart
//
// part of the feeding layer-module library (see feeding_assessment_surface.dart
// for the library doc + the off-ramp binding contract).
//
// The locked spine palette, type registers, and shared visual primitives —
// LIBRARY-PRIVATE on purpose: keeping them un-importable from other surfaces
// enforces the feeding-local scope of this proof-of-shape (no accidental
// cross-surface design-system coupling; SSD/CAS/voice migrate per-surface
// later, with primitive extraction decided AT that moment, not pre-empted).

part of 'feeding_assessment_surface.dart';

// Locked spine palette (+ the dual-accent pair) — matches the SSD surface.
const Color _ink = Color(0xFF1B2B4B); // kCueInk
const Color _inkSecondary = Color(0xFF5F5E5A); // body / secondary content
const Color _inkTertiary = Color(0xFF888780); // eyebrows / metadata
const Color _line = Color(0xFFE8E4DC); // kCueBorder hairline
const Color _olive = Color(0xFF5C6E3B); // calm default accent
const Color _oliveSoft = Color(0xFFE7EADB);
const Color _amber = Color(0xFFB45309); // urgent register (kCueAmber)
const Color _amberSoft = Color(0xFFF4E4C4);
const Color _coral = Color(0xFFC25450); // existing assessment-surface error tone
const Color _green = Color(0xFF1A7E5C); // WCAG-cleared green (Extract-button hue)

const List<String> _kPresenceValues = ['present', 'emerging', 'absent'];
const Map<String, String> _kPresenceValueToLabel = {
  'present': 'Present',
  'emerging': 'Emerging',
  'absent': 'Absent',
};

// Layer-1 colour coding per spec: present green / emerging amber / absent
// coral. (Only Layer 1 — the marks elsewhere stay in the calm olive register.)
const Map<String, Color> _kPresenceValueToColor = {
  'present': _green,
  'emerging': _amber,
  'absent': _coral,
};

const List<String> _kMarkingValues = [
  'at_level',
  'emerging',
  'below_level',
  'not_tested',
];

// ── Type system (spine registers — verbatim from the SSD surface) ───────

TextStyle _eyebrow({Color color = _inkTertiary, double size = 10.5}) =>
    GoogleFonts.jetBrainsMono(
        fontSize: size,
        fontWeight: FontWeight.w500,
        color: color,
        letterSpacing: size * 0.14);

TextStyle get _label => GoogleFonts.inter(
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    color: _ink,
    letterSpacing: -0.05);

TextStyle get _rowLabel => GoogleFonts.inter(
    fontSize: 11.5, fontWeight: FontWeight.w500, color: _inkSecondary);

TextStyle get _caption => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: _inkSecondary,
    height: 1.45);

TextStyle get _input => GoogleFonts.inter(
    fontSize: 13.5, fontWeight: FontWeight.w400, color: _ink);

// ── Gate: every public module renders through this ──────────────────────

/// Loading / error gate over the controller — the composer and each public
/// layer wrapper render through it, so a standalone-mounted layer is exactly
/// as bootstrap-safe as the composed surface.
Widget _controllerGated(
    FeedingAssessmentController controller, Widget Function() body) {
  return ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (controller.loading) {
        return const SizedBox(
            height: 100, child: Center(child: CircularProgressIndicator()));
      }
      final err = controller.error;
      if (err != null) {
        return _errorBox('Could not load feeding assessment: $err');
      }
      return body();
    },
  );
}

// ── Shared visual primitives ─────────────────────────────────────────────

Widget _section({
  required bool open,
  required VoidCallback onToggle,
  required int number,
  required String title,
  required String tagline,
  required Widget child,
}) {
  return Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: _line),
    ),
    child: Column(children: [
      InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(children: [
            Expanded(
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('SECTION $number — ${title.toUpperCase()}',
                    style: _eyebrow(color: _olive)),
                const SizedBox(height: 4),
                Text(tagline, style: _caption),
              ]),
            ),
            Icon(open ? Icons.expand_less : Icons.expand_more,
                color: _inkTertiary),
          ]),
        ),
      ),
      if (open) ...[
        const Divider(height: 1, color: _line),
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), child: child),
      ],
    ]),
  );
}

Widget _rowCard(
    {required List<Widget> children, required VoidCallback onRemove}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 4),
      decoration: BoxDecoration(
        color: _oliveSoft.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ...children,
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, size: 14, color: _coral),
            label: Text('Remove',
                style: GoogleFonts.inter(fontSize: 12, color: _coral)),
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          ),
        ),
      ]),
    ),
  );
}

Widget _addButton(String label, VoidCallback onTap) {
  return Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.add_rounded, size: 16, color: _olive),
      label: Text(label,
          style: GoogleFonts.inter(
              fontSize: 13, color: _olive, fontWeight: FontWeight.w600)),
      style:
          TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
    ),
  );
}

/// Calm guidance block — olive-soft ground, regular Inter (never italic on
/// a clinical surface).
Widget _ghostNote(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: _oliveSoft.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _oliveSoft),
        ),
        child: Text(text,
            style: GoogleFonts.inter(fontSize: 12.5, color: _ink, height: 1.5)),
      ),
    );

/// AMBER caution register — the urgent exception (norming / boundary
/// caveats). Left stripe + weighted text so it can never read as decoration.
Widget _cautionNote(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          color: _amberSoft.withValues(alpha: 0.45),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 3.5, color: _amber),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Text(text,
                      style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: _ink,
                          fontWeight: FontWeight.w600,
                          height: 1.5)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );

Widget _subText(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: _caption),
    );

Widget _textField(
  String label,
  TextEditingController ctrl, {
  bool multi = false,
  String? hint,
  required VoidCallback onSave,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: _label),
      const SizedBox(height: 4),
      Focus(
        onFocusChange: (f) {
          if (!f) onSave();
        },
        child: TextField(
          controller: ctrl,
          minLines: 1,
          maxLines: multi ? 3 : 1,
          style: _input,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(
                fontSize: 12, color: _inkTertiary.withValues(alpha: 0.8)),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ),
    ]),
  );
}

Widget _rowText(
  String label,
  TextEditingController ctrl, {
  String? hint,
  required VoidCallback onSave,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: _rowLabel),
      const SizedBox(height: 4),
      Focus(
        onFocusChange: (f) {
          if (!f) onSave();
        },
        child: TextField(
          controller: ctrl,
          style: _input,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(
                fontSize: 12, color: _inkTertiary.withValues(alpha: 0.8)),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ),
    ]),
  );
}

Widget _numField(
  String label,
  TextEditingController ctrl, {
  String? unit,
  required VoidCallback onSave,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: _label),
      const SizedBox(height: 4),
      Focus(
        onFocusChange: (f) {
          if (!f) onSave();
        },
        child: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))],
          style: _input,
          decoration: InputDecoration(
            suffixText: unit,
            suffixStyle: GoogleFonts.inter(fontSize: 12, color: _inkTertiary),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ),
    ]),
  );
}

/// Layer-1 chips — colour-coded per spec (present green / emerging amber /
/// absent coral). The colour names the MARK's register; the mark is hers.
Widget _codedChips(String? value, ValueChanged<String?> onChanged) {
  return Wrap(spacing: 6, runSpacing: 6, children: [
    for (final v in _kPresenceValues)
      GestureDetector(
        onTap: () => onChanged(v == value ? null : v),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: value == v
                ? _kPresenceValueToColor[v]!.withValues(alpha: 0.12)
                : Colors.white,
            border: Border.all(
                color: value == v ? _kPresenceValueToColor[v]! : _line),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(_kPresenceValueToLabel[v]!,
              style: GoogleFonts.inter(
                  fontSize: 12,
                  color: value == v ? _kPresenceValueToColor[v]! : _ink,
                  fontWeight: FontWeight.w500)),
        ),
      ),
  ]);
}

/// Calm olive selection chips (the SSD register) — for the ladder marking
/// and behaviour status, where the surface must not editorialise the call.
Widget _oliveChips(String label, List<String> options, String? value,
    ValueChanged<String?> onChanged) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: _rowLabel),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final o in options)
          GestureDetector(
            onTap: () => onChanged(o == value ? null : o),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: value == o
                    ? _oliveSoft.withValues(alpha: 0.7)
                    : Colors.white,
                border: Border.all(color: value == o ? _olive : _line),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(_humanize(o),
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      color: value == o ? _olive : _ink,
                      fontWeight: FontWeight.w500)),
            ),
          ),
      ]),
    ]),
  );
}

String _humanize(String code) => code
    .replaceAll('_', ' ')
    .replaceFirstMapped(RegExp(r'^.'), (m) => m[0]!.toUpperCase());

int? _parseInt(String s) {
  final t = s.trim();
  if (t.isEmpty) return null;
  return int.tryParse(t) ?? double.tryParse(t)?.round();
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

Widget _errorBox(String msg) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: _coral.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8)),
      child: Text(msg, style: GoogleFonts.inter(fontSize: 12.5, color: _ink)),
    );
