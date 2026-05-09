import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// Phase 4.0.7.39 — chrome navigation switched to pushNamedAndRemoveUntil
// so the browser URL reflects the current screen and refresh lands the
// SLP back where she was. Direct screen imports for chrome destinations
// are no longer required at this layer.
import '../theme/theme_notifier.dart';
import '../theme/cue_theme.dart';
import 'cue_cuttlefish.dart';
// Phase 4.0.7.27c-split-fix2 — CueStudyFab default removed; only
// client-aware screens pass an explicit instance via cueStudyFab.
// Import retained for the doc comment reference but unused at runtime.
// ignore: unused_import
import 'cue_study_fab.dart';
const double _kSidebarFull      = 220;
const double _kSidebarCollapsed = 56;
const double _kDesktopBreak     = 1024;
// Phase 4.0.7.22a — bump from 600 → 768 so tablets and SLPs in
// landscape on phones still get the full mobile chrome (bottom nav +
// compact header). Above 768 we keep the desktop sidebar.
const double _kMobileBreak      = 768;

// Phase 4.0.7.22a-hotfix — `MobileWall` removed. Pre-pivot guard that
// blocked auth screens below 768 px with "Cue works best on desktop".
// Mobile chrome shipped in 2a75655 so the guard contradicted strategy.

// ── Main shell ─────────────────────────────────────────────────────────────────
class AppLayout extends StatelessWidget {
  final String title;
  final Widget body;
  final String activeRoute;
  final Widget? floatingActionButton;
  final List<Widget> actions;
  /// Cue Study FAB override. Phase 1 product law: Cue Study is per-
  /// client only — there is no global thread. So screens without
  /// client context (Today, Clients, Assessing, Narrator, Settings)
  /// don't render a FAB at all. Client-aware screens pass an
  /// explicit CueStudyFab(...) instance with the chart payload
  /// pre-bound. Phase 4.0.7.27c-split-fix2: previously the default
  /// rendered an empty CueStudyFab() that, on tap, fired a
  /// "Open a client's Chart..." snackbar — surfacing the empty-state
  /// copy as a global toast on every non-Cue-Study screen. The
  /// default is now SizedBox.shrink(); the empty-state copy moves
  /// to whichever screen actually surfaces a Cue Study empty view.
  final Widget? cueStudyFab;

  const AppLayout({
    super.key,
    required this.title,
    required this.body,
    this.activeRoute = 'roster',
    this.floatingActionButton,
    this.actions = const [],
    this.cueStudyFab,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < _kMobileBreak;

          // ── Mobile layout: bottom nav, no sidebar ──────────────────────────
          if (isMobile) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopBar(title: title, actions: actions, isMobile: true),
                Expanded(
                  child: Stack(
                    children: [
                      body,
                      // Per-screen FAB — bottom-right, above bottom nav
                      if (floatingActionButton != null)
                        Positioned(
                          bottom: 72,
                          right:  16,
                          child:  floatingActionButton!,
                        ),
                      // Cue Study FAB — bottom-left, above bottom nav
                      Positioned(
                        bottom: 72,
                        left:   16,
                        child:  cueStudyFab ?? const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
                _MobileBottomNav(activeRoute: activeRoute),
              ],
            );
          }

          // ── Desktop / tablet layout: sidebar + content ─────────────────────
          final sidebarWidth = constraints.maxWidth < _kDesktopBreak
              ? _kSidebarCollapsed
              : _kSidebarFull;
          final collapsed = sidebarWidth == _kSidebarCollapsed;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: sidebarWidth,
                child: _AppSidebar(
                  collapsed:   collapsed,
                  activeRoute: activeRoute,
                ),
              ),
              // Content area — Stack overlays both FABs over the content
              Expanded(
                child: Stack(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _TopBar(title: title, actions: actions),
                        Expanded(child: body),
                      ],
                    ),
                    // Per-screen FAB (e.g. narrator mic, add client) — bottom-right
                    if (floatingActionButton != null)
                      Positioned(
                        bottom: 32,
                        right:  16,
                        child:  floatingActionButton!,
                      ),
                    // Cue Study FAB — bottom-left; context-aware override when provided
                    Positioned(
                      bottom: 32,
                      left:   16,
                      child:  cueStudyFab ?? const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Top bar ────────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  final bool isMobile;

  const _TopBar({
    required this.title,
    required this.actions,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context) {
    final canPop  = Navigator.canPop(context);
    final hPad    = isMobile ? 8.0 : 32.0;
    final fontSize = isMobile ? 16.0 : 20.0;

    // Phase 4.0.8-step-B-surface-1.2 — when a screen passes empty
    // title AND there are no actions AND no back button, skip the
    // bar entirely. Today screen uses this so the greeting H1 is the
    // page identity (the spine's once-per-screen serif moment is the
    // header). Other screens with title strings keep their bar
    // unchanged.
    if (title.isEmpty && !canPop && actions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: Row(
        children: [
          if (canPop) ...[
            // 44×44 touch target on mobile
            SizedBox(
              width:  isMobile ? 44 : 36,
              height: isMobile ? 44 : 36,
              child: InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(8),
                child: Center(
                  child: Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.grey.shade700,
                    size: 20,
                  ),
                ),
              ),
            ),
            SizedBox(width: isMobile ? 4 : 12),
          ],
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize:   fontSize,
                fontWeight: FontWeight.w600,
                color:      const Color(0xFF1A1A2E),
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

// ── Sidebar ────────────────────────────────────────────────────────────────────
class _NavItem {
  final IconData icon;
  final String label;
  final String route;
  const _NavItem({required this.icon, required this.label, required this.route});
}

// Phase 4.0.7.24 — Assessing slot inserted between Clients and
// Narrator. Assessment-only engagement is a parallel surface to
// therapy clients, not a phase within Clients.
const _kNavItems = [
  _NavItem(icon: Icons.today_rounded,           label: 'Today',     route: 'today'),
  _NavItem(icon: Icons.people_outline_rounded,  label: 'Clients',   route: 'roster'),
  _NavItem(icon: Icons.assignment_outlined,     label: 'Assessing', route: 'assessing'),
  _NavItem(icon: Icons.mic_rounded,             label: 'Narrator',  route: 'narrator'),
  _NavItem(icon: Icons.settings_outlined,       label: 'Settings',  route: 'settings'),
];

class _AppSidebar extends StatelessWidget {
  final bool collapsed;
  final String activeRoute;

  const _AppSidebar({
    required this.collapsed,
    required this.activeRoute,
  });

  @override
  Widget build(BuildContext context) {
    final isNight = Theme.of(context).brightness == Brightness.dark;
    final sidebarColor =
        isNight ? CueColors.sidebarDark : CueColors.sidebar;
    return Container(
      color: sidebarColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLogo(isNight),
          const SizedBox(height: 8),
          ..._kNavItems.map((item) => _buildNavItem(context, item, isNight)),
          const Spacer(),
          _buildThemeToggle(context),
          _buildSignOut(context),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildLogo(bool isNight) {
    return Container(
      height: 60,
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 20),
      alignment: collapsed ? Alignment.center : Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: collapsed
          ? const Center(
              child: SizedBox(
                width:  22,
                height: 26,
                child: CueCuttlefish(size: 22, state: CueState.idle),
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: const [
                SizedBox(
                  width:  22,
                  height: 26,
                  child: CueCuttlefish(size: 22, state: CueState.idle),
                ),
                SizedBox(width: 8),
                Text(
                  'Cue',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildNavItem(
      BuildContext context, _NavItem item, bool isNight) {
    final isActive = activeRoute == item.route;

    // Phase 4.0.8-step-B-surface-1.2 — sidebar active state shifts
    // from amber to olive per the dual-accent semantic system. Amber
    // is reserved for urgent surfaces (yesterday-reminder, "Up next"
    // card stripe); navigation is calm/steady → olive.
    //
    // The saturated olive (#5C6E3B / kCueOlive) reads as muddy on
    // the dark navy sidebar. A desaturated lift (#B8C572) is used
    // here ONLY — sidebar-specific. NOT promoted to a token because
    // it has only one consumer; if a second emerges, factor to
    // kCueOliveSidebar at that point.
    const Color sidebarActiveText = Color(0xFFB8C572);
    final activeColor   = sidebarActiveText;
    final inactiveColor = isNight
        ? const Color(0xFFF0EBE1).withValues(alpha: 0.25)
        : Colors.white.withValues(alpha: 0.35);

    return GestureDetector(
      onTap: () => _navigate(context, item),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: EdgeInsets.symmetric(
          horizontal: collapsed ? 0 : 12,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          // Olive ground at 0.22α — calm-register active indicator.
          color: isActive
              ? const Color(0xFF5C6E3B).withValues(alpha: 0.22)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: collapsed
            ? Center(
                child: Icon(
                  item.icon,
                  color: isActive ? activeColor : inactiveColor,
                  size: 22,
                ),
              )
            : Row(
                children: [
                  Icon(
                    item.icon,
                    color: isActive ? activeColor : inactiveColor,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    item.label,
                    style: TextStyle(
                      color: isActive ? activeColor : inactiveColor,
                      fontSize: 14,
                      fontWeight: isActive
                          ? FontWeight.w500
                          : FontWeight.w400,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildThemeToggle(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (ctx, mode, child) {
        final isNight = mode == ThemeMode.dark;
        return GestureDetector(
          onTap: () => themeNotifier.toggle(),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 0 : 12,
              vertical: 10,
            ),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
            child: collapsed
                ? Center(
                    child: Icon(
                      isNight
                          ? Icons.light_mode_rounded
                          : Icons.dark_mode_rounded,
                      color: Colors.white.withValues(alpha: 0.45),
                      size: 20,
                    ),
                  )
                : Row(
                    children: [
                      Icon(
                        isNight
                            ? Icons.light_mode_rounded
                            : Icons.dark_mode_rounded,
                        color: Colors.white.withValues(alpha: 0.45),
                        size: 18,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        isNight ? 'Day mode' : 'Night mode',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildSignOut(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        await Supabase.instance.client.auth.signOut();
        if (context.mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/login',
            (_) => false,
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: EdgeInsets.symmetric(
          horizontal: collapsed ? 0 : 12,
          vertical: 10,
        ),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
        child: collapsed
            ? Center(
                child: Icon(
                  Icons.logout_rounded,
                  color: Colors.white.withOpacity(0.45),
                  size: 20,
                ),
              )
            : Row(
                children: [
                  Icon(
                    Icons.logout_rounded,
                    color: Colors.white.withOpacity(0.45),
                    size: 18,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Sign Out',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.45),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _navigate(BuildContext context, _NavItem item) {
    if (item.route == activeRoute) return;
    final path = _routePathFor(item.route);
    if (path == null) return;
    Navigator.pushNamedAndRemoveUntil(context, path, (_) => false);
  }
}

/// Maps the activeRoute key (used by AppLayout / bottom nav) to the
/// named-route path defined in main.dart's onGenerateRoute. Phase
/// 4.0.7.39 — single source of truth so sidebar + mobile nav stay in
/// sync. Returns null for unknown keys.
String? _routePathFor(String route) {
  switch (route) {
    case 'today':     return '/today';
    case 'roster':    return '/clients';
    case 'assessing': return '/assessing';
    case 'narrator':  return '/narrator';
    case 'settings':  return '/settings';
  }
  return null;
}

// ── Mobile bottom navigation bar ──────────────────────────────────────────────
class _MobileBottomNav extends StatelessWidget {
  final String activeRoute;
  const _MobileBottomNav({required this.activeRoute});

  // Phase 4.0.7.24 — 5th slot for Assessing. Tight at 320px (each tab
  // gets ~64px), but acceptable for V1; the "hide Settings on mobile,
  // move to a profile dropdown" alternative is deferred to 4.0.7.22n
  // mobile audit follow-up.
  static const _kNavIcons = [
    (icon: Icons.calendar_today_outlined, route: 'today'),
    (icon: Icons.people_outlined,         route: 'roster'),
    (icon: Icons.assignment_outlined,     route: 'assessing'),
    (icon: Icons.mic_outlined,            route: 'narrator'),
    (icon: Icons.settings_outlined,       route: 'settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFF0A1A2F),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: _kNavIcons.map((item) {
          final isActive = activeRoute == item.route;
          return Expanded(
            child: GestureDetector(
              onTap: () => _navigate(context, item.route),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                height: 56,
                child: Center(
                  child: Icon(
                    item.icon,
                    size: 24,
                    color: isActive
                        ? const Color(0xFF1D9E75)
                        : const Color(0xFF8A8A8A),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _navigate(BuildContext context, String route) {
    if (route == activeRoute) return;
    final path = _routePathFor(route);
    if (path == null) return;
    Navigator.pushNamedAndRemoveUntil(context, path, (_) => false);
  }
}
