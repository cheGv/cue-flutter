// lib/config/app_config.dart
//
// Compile-time Supabase target selection.
//
// FAIL-SAFE DEFAULT (Phase 4.0.7.28 hotfix): the default target is SANDBOX.
// A build with NO --dart-define resolves to sandbox, so local dev can never
// silently hit production. Production is an EXPLICIT opt-in:
//
//   --dart-define=APP_ENV=prod
//
// Local dev (default — sandbox):
//   flutter run -d chrome --web-port=5173
//
// Production build (explicit):
//   flutter build web --release --dart-define=APP_ENV=prod
//
// A --release build that is NOT given APP_ENV=prod FAILS TO COMPILE (see the
// _ReleaseEnvGuard const assert at the bottom of this file) — a dropped CI pin
// fails loud at build time instead of silently shipping production against the
// sandbox database.
//
// Anon keys below are legacy JWT publishable keys (RLS-protected, safe to
// embed — the same class of key for both projects). The prod pair was already
// committed here previously; this refactor only renames/reorganises it.

import 'package:flutter/foundation.dart';

/// Selected environment: 'sandbox' (default), 'prod' (explicit opt-in), or
/// 'demo' (explicit opt-in — a release-legal SANDBOX-backed build for public
/// SLP feedback deploys; synthetic data only).
const String kAppEnv = String.fromEnvironment('APP_ENV', defaultValue: 'sandbox');

/// True only when this build explicitly opted into production.
const bool kIsProd = kAppEnv == 'prod';

/// True only when this build explicitly opted into the demo register: a
/// release artifact that targets the SANDBOX. Resolves to the sandbox
/// URL/key below through the existing non-prod branch — 'demo' exists so the
/// release guard can bless the target EXPLICITLY, never via a dropped define.
const bool kIsDemo = kAppEnv == 'demo';

/// Cue proxy base URL. Defaults to the deployed proxy; overridable at build
/// time for LOCAL testing — e.g. --dart-define=PROXY_BASE=http://localhost:3001.
/// A build with NO --dart-define resolves to the real proxy, so production /
/// release behaviour is unchanged. Build-time switch only — not a deploy, not
/// a server change.
const String kProxyBaseUrl = String.fromEnvironment(
  'PROXY_BASE',
  defaultValue: 'https://cue-ai-proxy.onrender.com',
);

// ── Sandbox (default) — project uuqhusmgoiaxdvtgbmwh ─────────────────────────
const String kSupabaseUrlSandbox = 'https://uuqhusmgoiaxdvtgbmwh.supabase.co';
const String kSupabaseAnonKeySandbox =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV1cWh1c21nb2lheGR2dGdibXdoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkwMTc2NjIsImV4cCI6MjA5NDU5MzY2Mn0.XahAhkZKYU5b4feWg7bSEVbFPYyamUpGGraQvlrsvO4';

// ── Production (explicit opt-in) — project cgnjbjbargkxtcnafxaa ──────────────
const String kSupabaseUrlProd = 'https://cgnjbjbargkxtcnafxaa.supabase.co';
const String kSupabaseAnonKeyProd =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNnbmpiamJhcmdreHRjbmFmeGFhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUyODQyNzcsImV4cCI6MjA5MDg2MDI3N30.AWmyJoSuXUi7X74vBN2E1Jv7mStsjepKqRFyA6iFfmE';

/// Effective Supabase URL — sandbox unless APP_ENV=prod. Consumed by
/// main.dart's Supabase.initialize and the debug recall test screen's banner.
const String kSupabaseUrl = kIsProd ? kSupabaseUrlProd : kSupabaseUrlSandbox;

/// Effective Supabase anon key — sandbox unless APP_ENV=prod.
const String kSupabaseAnonKey =
    kIsProd ? kSupabaseAnonKeyProd : kSupabaseAnonKeySandbox;

// Known project refs — used by the debug recall test screen's environment
// guardrail to colour the target banner (red=prod, green=sandbox,
// amber=unknown) and to gate its Resolve button.
const String kProdProjectRef = 'cgnjbjbargkxtcnafxaa';
const String kSandboxProjectRef = 'uuqhusmgoiaxdvtgbmwh';

// ── Build-time release guard ─────────────────────────────────────────────────
// A --release build const-folds kReleaseMode to true. If such a build is
// produced WITHOUT an explicit APP_ENV of 'prod' or 'demo', the const
// assertion in this constructor evaluates to false at compile time and aborts
// `flutter build`. The guard blesses NAMED targets only — a release with no
// define (a dropped CI env-pin) still fails loud. Local debug runs
// (kReleaseMode == false) are unaffected and default to sandbox.
class _ReleaseEnvGuard {
  const _ReleaseEnvGuard()
      : assert(
          !(kReleaseMode && !(kIsProd || kIsDemo)),
          'BUILD GUARD: a --release build must be compiled with '
          '--dart-define=APP_ENV=prod (production) or APP_ENV=demo '
          '(sandbox-backed feedback build). Refusing to produce a release '
          'artifact with no explicit environment (a CI env-pin was likely '
          'dropped).',
        );
}

/// Compile-time guard instance. Referenced from main() so the compiler is
/// forced to evaluate it — and thus enforce the assert above — on every build.
const Object kReleaseEnvGuard = _ReleaseEnvGuard();
