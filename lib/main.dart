import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/today_screen.dart';
import 'screens/login_screen.dart';
import 'screens/assessment_case_screen.dart';
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

/// Phase 4.0.7.24c — resolves /assessing/:clientId by fetching the
/// client row from supabase, then handing off to AssessmentCaseScreen.
/// Renders a centered spinner while loading and a paper-style error
/// card if the client is missing or the user isn't authed. The
/// imperative push path inside AssessingScreen still passes a fully
/// loaded client map; this loader covers the hard-refresh / shared-URL
/// case.
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
      setState(() => _error = 'Sign in to view this assessment.');
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
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!,
                style: const TextStyle(color: Color(0xFF0E1C36))),
          ),
        ),
      );
    }
    if (_client == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return AssessmentCaseScreen(client: _client!);
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
        // Phase 4.0.7.24c — deep-link routing for the assessment case
        // screen. `home` stays as the default landing surface; the
        // named-route handler below resolves /assessing/:clientId so a
        // hard refresh inside an assessment stays put. Other screens
        // continue using imperative Navigator.push and are unaffected.
        home: hasSession ? const TodayScreen() : const LoginScreen(),
        onGenerateRoute: (settings) {
          final name = settings.name;
          if (name == null) return null;
          final uri = Uri.parse(name);
          // /assessing/:clientId → AssessmentCaseScreen
          if (uri.pathSegments.length == 2 &&
              uri.pathSegments[0] == 'assessing') {
            final clientId = uri.pathSegments[1];
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => _AssessmentCaseDeepLinkLoader(
                  clientId: clientId),
            );
          }
          return null;
        },
      ),
    );
  }
}
