// lib/screens/settings/settings_shell.dart
//
// Phase 5 Settings — shell mounted at /settings.
//
// Two-pane on wide viewports: left list of 10 screens grouped into three
// sections, right pane renders the active screen body. On narrow viewports
// the list becomes a Settings index page; tapping a row navigates to that
// screen with a back affordance to return to the list.
//
// LayoutBuilder, never MediaQuery (per CLAUDE.md).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/cue_color_scheme.dart';
import '../../widgets/app_layout.dart';
import 'settings_screens.dart';

const double _kSplitBreak = 880;
const double _kNavWidth = 260;

class SettingsShell extends StatefulWidget {
  final String? initialScreen;

  const SettingsShell({super.key, this.initialScreen});

  @override
  State<SettingsShell> createState() => _SettingsShellState();
}

class _SettingsShellState extends State<SettingsShell> {
  String? _activeScreen;

  @override
  void initState() {
    super.initState();
    _activeScreen = widget.initialScreen;
  }

  void _select(String key) {
    if (key == _activeScreen) return;
    setState(() => _activeScreen = key);
  }

  void _backToIndex() {
    setState(() => _activeScreen = null);
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: 'Settings',
      activeRoute: 'settings',
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= _kSplitBreak;
          if (isWide) {
            // Wide: list + content always rendered. Default to first screen
            // when nothing is explicitly active.
            final activeKey = _activeScreen ?? kSettingsNavItems.first.key;
            return _TwoPane(activeKey: activeKey, onSelect: _select);
          }
          // Narrow: index OR screen, never both.
          final activeKey = _activeScreen;
          if (activeKey == null) {
            return _SettingsNavList(
              activeKey: null,
              onSelect: _select,
              showTopPadding: true,
            );
          }
          return _NarrowScreen(
            screenKey: activeKey,
            onBack: _backToIndex,
          );
        },
      ),
    );
  }
}

// ── Two-pane (wide) ──────────────────────────────────────────────────────

class _TwoPane extends StatelessWidget {
  final String activeKey;
  final void Function(String) onSelect;
  const _TwoPane({required this.activeKey, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _kNavWidth,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: cue.border, width: 0.5)),
            ),
            child: _SettingsNavList(
              activeKey: activeKey,
              onSelect: onSelect,
            ),
          ),
        ),
        Expanded(child: SettingsScreenBody(screenKey: activeKey)),
      ],
    );
  }
}

// ── Narrow screen view ───────────────────────────────────────────────────

class _NarrowScreen extends StatelessWidget {
  final String screenKey;
  final VoidCallback onBack;
  const _NarrowScreen({required this.screenKey, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: cue.border, width: 0.5)),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: Icon(Icons.arrow_back_rounded,
                    color: cue.textBody, size: 20),
                visualDensity: VisualDensity.compact,
                tooltip: 'Back to Settings',
              ),
              Text(
                'Settings',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: cue.textMuted,
                ),
              ),
            ],
          ),
        ),
        Expanded(child: SettingsScreenBody(screenKey: screenKey)),
      ],
    );
  }
}

// ── Nav list ─────────────────────────────────────────────────────────────

class _SettingsNavList extends StatelessWidget {
  final String? activeKey;
  final void Function(String) onSelect;
  final bool showTopPadding;

  const _SettingsNavList({
    required this.activeKey,
    required this.onSelect,
    this.showTopPadding = false,
  });

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);
    // Group items by SettingsGroup, preserving declared order.
    final groups = <SettingsGroup, List<SettingsNavItem>>{};
    for (final item in kSettingsNavItems) {
      groups.putIfAbsent(item.group, () => []).add(item);
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(0, showTopPadding ? 20 : 16, 0, 24),
      children: [
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            child: Text(
              settingsGroupLabel(entry.key).toUpperCase(),
              style: GoogleFonts.syne(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: cue.textMuted,
              ),
            ),
          ),
          for (final item in entry.value)
            _NavRow(
              label: item.label,
              isActive: item.key == activeKey,
              onTap: () => onSelect(item.key),
            ),
        ],
      ],
    );
  }
}

class _NavRow extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavRow({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);
    // Calm/steady olive active state per CLAUDE.md dual-accent doctrine.
    const olive = Color(0xFF5C6E3B);
    final activeBg = olive.withValues(alpha: cue.isDark ? 0.22 : 0.16);
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 1, 8, 1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? activeBg : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 13.5,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive ? cue.textPrimary : cue.textBody,
                  height: 1.4,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: isActive
                  ? cue.textPrimary
                  : cue.textMuted.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}
