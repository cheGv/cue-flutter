import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/today_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/client_roster_screen.dart';
import 'screens/client_profile_screen.dart';
import 'screens/assessing_screen.dart';
import 'screens/narrator_screen.dart';
import 'screens/slp_profile_screen.dart';
import 'screens/assessment_case_screen.dart';
import 'screens/new_assessment_case_screen.dart';
import 'screens/report_screen.dart';
import 'screens/session_capture_screen.dart';
import 'theme/cue_theme.dart';
import 'theme/theme_notifier.dart';
import 'utils/daily_chart_log.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://cgnjbjbargkxtcnafxaa.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNnbmpiamJhcmdreHRjbmFmeGFhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUyODQyNzcsImV4cCI6MjA5MDg2MDI3N30.AWmyJoSuXUi7X74vBN2E1Jv7mStsjepKqRFyA6iFfmE',
  );

  // Restore persisted theme before first frame.
  await themeNotifier.load();

  // Prune yesterday-and-older entries from the daily chart log so
  // Monday-first detection only reads today's opens.
  await DailyChartLog.pruneStaleEntries();

  final session = Supabase.instance.client.auth.currentSession;
  runApp(CueApp(hasSession: session != null));
}

// ── Deep-link infrastructure ──────────────────────────────────────────────────
//
// Phase 4.0.7.39 — friend-tester finding 1 ("refresh navigation breaks")
// closed by replicating the _AssessmentCaseDeepLinkLoader pattern across
// every Category 1 surface (chart, report, session-edit, study) and
// adding bare named routes for the five chrome destinations.
//
// Pattern: each loader is a StatefulWidget that holds an id, fetches its
// row, and forwards to the typed screen. Signed-out path redirects to
// `/login?return=<deep-link>` so login knows where to land. The shared
// `_DeepLinkSpinner` and `_DeepLinkErrorCard` keep the visual register
// consistent (per founder decision 1: middle-path — per-surface loaders,
// shared helpers).

class _DeepLinkSpinner extends StatelessWidget {
  const _DeepLinkSpinner();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _DeepLinkErrorCard extends StatelessWidget {
  final String message;
  const _DeepLinkErrorCard({required this.message});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(message,
                style: const TextStyle(color: Color(0xFF0E1C36))),
          ),
        ),
      );
}

/// Common signed-out redirect. Schedules a post-frame
/// `pushReplacementNamed('/login?return=<encoded>')`. Loaders call this
/// from `_load()` when `currentSession == null` and bail out before
/// hitting the DB. Per founder decision 3: no signed-out error cards.
void _redirectToLogin(BuildContext context, String returnPath) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    final encoded = Uri.encodeQueryComponent(returnPath);
    Navigator.pushReplacementNamed(context, '/login?return=$encoded');
  });
}

/// Resolves /assessing/:clientId by fetching the client row and handing
/// off to AssessmentCaseScreen. Reference implementation for the
/// pattern; predates 4.0.7.39 (4.0.7.24c). Updated in 39 to redirect
/// rather than render a signed-out error card.
class _AssessmentCaseDeepLinkLoader extends StatefulWidget {
  final String clientId;
  const _AssessmentCaseDeepLinkLoader({required this.clientId});

  @override
  State<_AssessmentCaseDeepLinkLoader> createState() =>
      _AssessmentCaseDeepLinkLoaderState();
}

class _AssessmentCaseDeepLinkLoaderState
    extends State<_AssessmentCaseDeepLinkLoader> {
  Map<String, dynamic>? _client;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      _redirectToLogin(context, '/assessing/${widget.clientId}');
      return;
    }
    try {
      final row = await Supabase.instance.client
          .from('clients')
          .select()
          .eq('id', widget.clientId)
          .maybeSingle();
      if (!mounted) return;
      if (row == null) {
        setState(() => _error = 'Assessment case not found.');
        return;
      }
      setState(() => _client = Map<String, dynamic>.from(row));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _DeepLinkErrorCard(message: _error!);
    if (_client == null) return const _DeepLinkSpinner();
    return AssessmentCaseScreen(client: _client!);
  }
}

/// Resolves /clients/:clientId → ClientProfileScreen. Highest-traffic
/// Category 1 surface; closes the chart-refresh-bounce friend-tester
/// signal directly.
class _ClientProfileDeepLinkLoader extends StatefulWidget {
  final String clientId;
  const _ClientProfileDeepLinkLoader({required this.clientId});

  @override
  State<_ClientProfileDeepLinkLoader> createState() =>
      _ClientProfileDeepLinkLoaderState();
}

class _ClientProfileDeepLinkLoaderState
    extends State<_ClientProfileDeepLinkLoader> {
  Map<String, dynamic>? _client;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      _redirectToLogin(context, '/clients/${widget.clientId}');
      return;
    }
    try {
      final row = await Supabase.instance.client
          .from('clients')
          .select()
          .eq('id', widget.clientId)
          .maybeSingle();
      if (!mounted) return;
      if (row == null) {
        setState(() => _error = 'Client not found.');
        return;
      }
      setState(() => _client = Map<String, dynamic>.from(row));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _DeepLinkErrorCard(message: _error!);
    if (_client == null) return const _DeepLinkSpinner();
    return ClientProfileScreen(client: _client!);
  }
}

/// Resolves /sessions/:sessionId → ReportScreen. Fetches the session
/// row + the joined client name. `autoGenerate` is hardcoded false on
/// the deep-link path — preserving the founder safety lock so a hard
/// refresh on a session report never re-fires the LLM proxy.
class _ReportDeepLinkLoader extends StatefulWidget {
  final int sessionId;
  const _ReportDeepLinkLoader({required this.sessionId});

  @override
  State<_ReportDeepLinkLoader> createState() => _ReportDeepLinkLoaderState();
}

class _ReportDeepLinkLoaderState extends State<_ReportDeepLinkLoader> {
  Map<String, dynamic>? _session;
  String? _clientName;
  String? _clientId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = Supabase.instance.client.auth.currentSession;
    if (auth == null) {
      _redirectToLogin(context, '/sessions/${widget.sessionId}');
      return;
    }
    try {
      final sb = Supabase.instance.client;
      final session = await sb
          .from('sessions')
          .select()
          .eq('id', widget.sessionId)
          .maybeSingle();
      if (!mounted) return;
      if (session == null) {
        setState(() => _error = 'Session not found.');
        return;
      }
      final clientId = session['client_id']?.toString();
      Map<String, dynamic>? client;
      if (clientId != null) {
        client = await sb
            .from('clients')
            .select('name')
            .eq('id', clientId)
            .maybeSingle();
      }
      if (!mounted) return;
      setState(() {
        _session = Map<String, dynamic>.from(session);
        _clientId = clientId;
        _clientName = (client?['name'] as String?) ?? '';
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _DeepLinkErrorCard(message: _error!);
    if (_session == null) return const _DeepLinkSpinner();
    return ReportScreen(
      session: _session!,
      clientName: _clientName ?? '',
      clientId: _clientId,
      // Founder safety lock: deep-link never auto-regenerates.
      autoGenerate: false,
    );
  }
}

/// Resolves /sessions/:sessionId/edit → SessionCaptureScreen edit mode.
/// Per founder decision 5 (option a): only edit-mode is deep-linkable;
/// create-mode stays Category 3. The screen's own `_loadExistingSession`
/// will populate controllers on mount once `existingSessionId` is set.
class _SessionCaptureEditDeepLinkLoader extends StatefulWidget {
  final int sessionId;
  const _SessionCaptureEditDeepLinkLoader({required this.sessionId});

  @override
  State<_SessionCaptureEditDeepLinkLoader> createState() =>
      _SessionCaptureEditDeepLinkLoaderState();
}

class _SessionCaptureEditDeepLinkLoaderState
    extends State<_SessionCaptureEditDeepLinkLoader> {
  String? _clientId;
  String? _clientName;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = Supabase.instance.client.auth.currentSession;
    if (auth == null) {
      _redirectToLogin(context, '/sessions/${widget.sessionId}/edit');
      return;
    }
    try {
      final sb = Supabase.instance.client;
      final session = await sb
          .from('sessions')
          .select('client_id')
          .eq('id', widget.sessionId)
          .maybeSingle();
      if (!mounted) return;
      if (session == null) {
        setState(() => _error = 'Session not found.');
        return;
      }
      final clientId = session['client_id']?.toString();
      if (clientId == null) {
        setState(() => _error = 'Session is not linked to a client.');
        return;
      }
      final client = await sb
          .from('clients')
          .select('name')
          .eq('id', clientId)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _clientId = clientId;
        _clientName = (client?['name'] as String?) ?? '';
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _DeepLinkErrorCard(message: _error!);
    if (_clientId == null) return const _DeepLinkSpinner();
    return SessionCaptureScreen(
      clientId: _clientId!,
      clientName: _clientName ?? '',
      existingSessionId: widget.sessionId,
    );
  }
}

class CueApp extends StatelessWidget {
  final bool hasSession;
  const CueApp({super.key, required this.hasSession});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, mode, child) => MaterialApp(
        title: 'Cue',
        debugShowCheckedModeBanner: false,
        themeMode: mode,
        theme:     CueTheme.dayTheme,
        darkTheme: CueTheme.nightTheme,
        // `home` stays as the implicit landing surface for `/`. Phase
        // 4.0.7.39 adds named routes for every chrome destination and
        // every Category 1 surface so refresh on any deep-linkable URL
        // lands on the same page rather than bouncing back to Today.
        home: hasSession ? const TodayScreen() : const LoginScreen(),
        onGenerateRoute: (settings) {
          final name = settings.name;
          if (name == null) return null;
          final uri = Uri.parse(name);

          // ── Auth surfaces ───────────────────────────────────────────
          if (uri.path == '/login') {
            final returnTo = uri.queryParameters['return'];
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => LoginScreen(returnTo: returnTo),
            );
          }
          if (uri.path == '/signup') {
            final returnTo = uri.queryParameters['return'];
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => SignupScreen(returnTo: returnTo),
            );
          }

          // ── Chrome destinations (Category 2) ────────────────────────
          if (uri.path == '/today') {
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const TodayScreen(),
            );
          }
          if (uri.path == '/clients' && uri.pathSegments.length == 1) {
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const ClientRosterScreen(),
            );
          }
          if (uri.path == '/assessing' && uri.pathSegments.length == 1) {
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const AssessingScreen(),
            );
          }
          if (uri.path == '/narrator') {
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const NarratorScreen(),
            );
          }
          if (uri.path == '/settings') {
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const SlpProfileScreen(),
            );
          }

          // ── Assessment intake + case (existing, pre-39) ─────────────
          if (uri.path == '/new-assessment') {
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const NewAssessmentCaseScreen(),
            );
          }
          if (uri.pathSegments.length == 2 &&
              uri.pathSegments[0] == 'assessing') {
            final clientId = uri.pathSegments[1];
            return MaterialPageRoute(
              settings: settings,
              builder: (_) =>
                  _AssessmentCaseDeepLinkLoader(clientId: clientId),
            );
          }

          // ── Category 1 surfaces (added 4.0.7.39) ────────────────────
          // Phase 5.1+5.2 — /clients/:clientId/study route REMOVED
          // (Cue Study retired). Hard refresh on an old /study URL falls
          // through to the catch-all return null below; the unknown-route
          // path lands the SLP back on /today via main.dart's default.
          // /clients/:clientId  →  ClientProfileScreen
          if (uri.pathSegments.length == 2 &&
              uri.pathSegments[0] == 'clients') {
            final clientId = uri.pathSegments[1];
            return MaterialPageRoute(
              settings: settings,
              builder: (_) =>
                  _ClientProfileDeepLinkLoader(clientId: clientId),
            );
          }
          // /sessions/:id/edit  →  SessionCaptureScreen edit-mode
          if (uri.pathSegments.length == 3 &&
              uri.pathSegments[0] == 'sessions' &&
              uri.pathSegments[2] == 'edit') {
            final sessionId = int.tryParse(uri.pathSegments[1]);
            if (sessionId == null) return null;
            return MaterialPageRoute(
              settings: settings,
              builder: (_) =>
                  _SessionCaptureEditDeepLinkLoader(sessionId: sessionId),
            );
          }
          // /sessions/:id  →  ReportScreen
          if (uri.pathSegments.length == 2 &&
              uri.pathSegments[0] == 'sessions') {
            final sessionId = int.tryParse(uri.pathSegments[1]);
            if (sessionId == null) return null;
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => _ReportDeepLinkLoader(sessionId: sessionId),
            );
          }

          return null;
        },
      ),
    );
  }
}
