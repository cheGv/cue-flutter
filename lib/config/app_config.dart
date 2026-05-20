// lib/config/app_config.dart
//
// Compile-time Supabase target selection.
//
// Defaults are PRODUCTION. Production behaviour is byte-identical when the
// app is launched with NO --dart-define overrides — the defaults below are
// the exact values that previously lived inline in main.dart.
//
// Sandbox is OPT-IN per launch:
//
//   flutter run \
//     --dart-define=SUPABASE_URL=https://uuqhusmgoiaxdvtgbmwh.supabase.co \
//     --dart-define=SUPABASE_ANON_KEY=<sandbox anon key>
//
// Sandbox anon key (legacy JWT anon key, RLS-protected / publishable —
// safe to embed, same class of key as the production default below):
//   eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV1cWh1c21nb2lheGR2dGdibXdoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkwMTc2NjIsImV4cCI6MjA5NDU5MzY2Mn0.XahAhkZKYU5b4feWg7bSEVbFPYyamUpGGraQvlrsvO4
//
// Both main.dart (for Supabase.initialize) and the debug recall test
// screen (for its environment guardrail) read these SAME constants, so the
// banner the harness shows always equals the client it actually talks to.

const String kSupabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://cgnjbjbargkxtcnafxaa.supabase.co',
);

const String kSupabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNnbmpiamJhcmdreHRjbmFmeGFhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUyODQyNzcsImV4cCI6MjA5MDg2MDI3N30.AWmyJoSuXUi7X74vBN2E1Jv7mStsjepKqRFyA6iFfmE',
);

// Known project refs — used by the debug recall test screen's environment
// guardrail to colour the target banner (red=prod, green=sandbox,
// amber=unknown) and to gate its Resolve button.
const String kProdProjectRef = 'cgnjbjbargkxtcnafxaa';
const String kSandboxProjectRef = 'uuqhusmgoiaxdvtgbmwh';
