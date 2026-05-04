import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/today_screen.dart';
import '../screens/client_roster_screen.dart';
import '../screens/narrator_screen.dart';
import '../screens/login_screen.dart';
import '../screens/slp_profile_screen.dart';
import '../theme/theme_notifier.dart';
import '../theme/cue_theme.dart';
import 'cue_cuttlefish.dart';
import 'cue_study_fab.dart';
const double _kSidebarFull      = 220;
const double _kSidebarCollapsed = 56;
const double _kDesktopBreak     = 1024;
// Phase 4.0.7.22a — bump from 600 → 768 so tablets and SLPs in
// landscape on phones still get the full mobile chrome (bottom nav +
// compact header). Above 768 we keep the desktop sidebar.
const double _kMobileBreak      = 768;

// ── Public mobile wall (reused by auth screens) ────────────────────────────────
class MobileWall extends StatelessWidget {
  const MobileWall({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF00897B),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: Text(
                    'C',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Cue',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Cue works best on desktop',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please open Cue on a computer for the full experience.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Main shell ─────────────────────────────────────────────────────────────────
class AppLayout extends StatelessWidget {
  final String title;
  final Widget body;
  final String activeRoute;
  final Widget? floatingActionButton;
  final List<Widget> actions;
  // When provided, replaces the global CueStudyFab (allows context-aware override).
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
                        child:  cueStudyFab ?? const CueStudyFab(),
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
                      child:  cueStudyFab ?? const CueStudyFab(),
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

const _kNavItems = [
  _NavItem(icon: Icons.today_rounded,         label: 'Today',    route: 'today'),
  _NavItem(icon: Icons.people_outline_rounded, label: 'Clients', route: 'roster'),
  _NavItem(icon: Icons.mic_rounded,            label: 'Narrator', route: 'narrator'),
  _NavItem(icon: Icons.settings_outlined,      label: 'Settings', route: 'settings'),
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
    final activeColor   = CueColors.amber;
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
          color: isActive
              ? activeColor.withValues(alpha: 0.10)
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
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
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
    if (item.route == 'today') {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const TodayScreen()),
        (_) => false,
      );
    } else if (item.route == 'roster') {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const ClientRosterScreen()),
        (_) => false,
      );
    } else if (item.route == 'narrator') {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const NarratorScreen()),
        (_) => false,
      );
    } else if (item.route == 'settings') {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const SlpProfileScreen()),
        (_) => false,
      );
    }
  }
}

// ── Mobile bottom navigation bar ──────────────────────────────────────────────
class _MobileBottomNav extends StatelessWidget {
  final String activeRoute;
  const _MobileBottomNav({required this.activeRoute});

  static const _kNavIcons = [
    (icon: Icons.calendar_today_outlined, route: 'today'),
    (icon: Icons.people_outlined,         route: 'roster'),
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
    switch (route) {
      case 'today':
        Navigator.pushAndRemoveUntil(context,
            MaterialPageRoute(builder: (_) => const TodayScreen()), (_) => false);
      case 'roster':
        Navigator.pushAndRemoveUntil(context,
            MaterialPageRoute(builder: (_) => const ClientRosterScreen()), (_) => false);
      case 'narrator':
        Navigator.pushAndRemoveUntil(context,
            MaterialPageRoute(builder: (_) => const NarratorScreen()), (_) => false);
      case 'settings':
        Navigator.pushAndRemoveUntil(context,
            MaterialPageRoute(builder: (_) => const SlpProfileScreen()), (_) => false);
    }
  }
}
