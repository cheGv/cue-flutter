import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/client_roster_screen.dart';
import 'screens/login_screen.dart';
import 'theme/cue_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://cgnjbjbargkxtcnafxaa.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNnbmpiamJhcmdreHRjbmFmeGFhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUyODQyNzcsImV4cCI6MjA5MDg2MDI3N30.AWmyJoSuXUi7X74vBN2E1Jv7mStsjepKqRFyA6iFfmE',
  );

  final session = Supabase.instance.client.auth.currentSession;
  runApp(CueApp(hasSession: session != null));
}

class CueApp extends StatelessWidget {
  final bool hasSession;

  const CueApp({super.key, required this.hasSession});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cue AI',
      debugShowCheckedModeBanner: false,
      theme: CueTheme.theme,
      // Global fade page transitions are configured in CueTheme.theme
      // via pageTransitionsTheme — no custom onGenerateRoute needed.
      home: hasSession ? const ClientRosterScreen() : const LoginScreen(),
    );
  }
}
