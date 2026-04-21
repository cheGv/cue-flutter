import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/today_screen.dart';
import '../screens/client_roster_screen.dart';
import '../screens/narrator_screen.dart';
import '../screens/login_screen.dart';
import '../screens/settings_screen.dart';

const double _kSidebarFull = 220;
const double _kSidebarCollapsed = 56;
const double _kDesktopBreak = 1024;
const double _kTabletBreak = 768;

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

  const AppLayout({
    super.key,
    required this.title,
    required this.body,
    this.activeRoute = 'roster',
    this.floatingActionButton,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      floatingActionButton: floatingActionButton,
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < _kTabletBreak) {
            return const MobileWall();
          }

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
                  collapsed: collapsed,
                  activeRoute: activeRoute,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TopBar(title: title, actions: actions),
                    Expanded(child: body),
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

  const _TopBar({required this.title, required this.actions});

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        children: [
          if (canPop) ...[
            InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.grey.shade700,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const Spacer(),
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
    return Container(
      color: const Color(0xFF1B2B4B),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLogo(),
          const SizedBox(height: 8),
          ..._kNavItems.map((item) => _buildNavItem(context, item)),
          const Spacer(),
          _buildSignOut(context),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      height: 60,
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 20),
      alignment: collapsed ? Alignment.center : Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
      ),
      child: collapsed
          ? Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF00B4A6).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text(
                  'C',
                  style: TextStyle(
                    color: Color(0xFF00B4A6),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            )
          : const Text(
              'Cue',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
            ),
    );
  }

  Widget _buildNavItem(BuildContext context, _NavItem item) {
    final isActive = activeRoute == item.route;

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
              ? const Color(0xFF00B4A6).withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: collapsed
            ? Center(
                child: Icon(
                  item.icon,
                  color: isActive
                      ? const Color(0xFF00B4A6)
                      : Colors.white.withOpacity(0.6),
                  size: 22,
                ),
              )
            : Row(
                children: [
                  Icon(
                    item.icon,
                    color: isActive
                        ? const Color(0xFF00B4A6)
                        : Colors.white.withOpacity(0.6),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    item.label,
                    style: TextStyle(
                      color: isActive
                          ? const Color(0xFF00B4A6)
                          : Colors.white.withOpacity(0.7),
                      fontSize: 14,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
      ),
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
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
        (_) => false,
      );
    }
  }
}
