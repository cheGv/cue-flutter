import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/today_screen.dart';
import 'screens/login_screen.dart';
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
        home: hasSession ? const TodayScreen() : const LoginScreen(),
      ),
    );
  }
}
