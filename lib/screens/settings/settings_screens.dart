// lib/screens/settings/settings_screens.dart
//
// Phase 5 Settings — 10-screen placeholder set with the v0.4 §6 block
// scaffolding rendered as collapsible cards. Each card shows the block's
// intent in one line; expanding it reveals the "Coming soon." stub. Real
// per-block UI lands incrementally per build order in v0.4 §10.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/cue_color_scheme.dart';
import 'settings_card.dart';

// ── Nav metadata ─────────────────────────────────────────────────────────

enum SettingsGroup { whoIAm, howIPractice, whatsProtected }

class SettingsNavItem {
  final String key;
  final String label;
  final SettingsGroup group;
  const SettingsNavItem({
    required this.key,
    required this.label,
    required this.group,
  });
}

const List<SettingsNavItem> kSettingsNavItems = [
  SettingsNavItem(key: 'identity',      label: 'Identity & Credentialing', group: SettingsGroup.whoIAm),
  SettingsNavItem(key: 'clinical',      label: 'Clinical Defaults',        group: SettingsGroup.howIPractice),
  SettingsNavItem(key: 'ai',            label: 'AI Behavior',              group: SettingsGroup.howIPractice),
  SettingsNavItem(key: 'practice',      label: 'Practice Setup',           group: SettingsGroup.howIPractice),
  SettingsNavItem(key: 'notifications', label: 'Notifications',            group: SettingsGroup.howIPractice),
  SettingsNavItem(key: 'privacy',       label: 'Privacy & Consent',        group: SettingsGroup.whatsProtected),
  SettingsNavItem(key: 'security',      label: 'Security',                 group: SettingsGroup.whatsProtected),
  SettingsNavItem(key: 'audit',         label: 'Audit Log',                group: SettingsGroup.whatsProtected),
  SettingsNavItem(key: 'billing',       label: 'Billing',                  group: SettingsGroup.whatsProtected),
  SettingsNavItem(key: 'legal',         label: 'Legal & Help',             group: SettingsGroup.whatsProtected),
];

String settingsGroupLabel(SettingsGroup g) {
  switch (g) {
    case SettingsGroup.whoIAm:         return 'Who I am';
    case SettingsGroup.howIPractice:   return 'How I practice';
    case SettingsGroup.whatsProtected: return "What's protected";
  }
}

SettingsNavItem? findSettingsItem(String? key) {
  if (key == null) return null;
  for (final i in kSettingsNavItems) {
    if (i.key == key) return i;
  }
  return null;
}

// ── Screen body ──────────────────────────────────────────────────────────

class SettingsScreenBody extends StatelessWidget {
  final String screenKey;
  const SettingsScreenBody({super.key, required this.screenKey});

  @override
  Widget build(BuildContext context) {
    final cue = CueColorsResolved.of(context);
    final item = findSettingsItem(screenKey);
    final blocks = _blocksFor(screenKey);
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 48),
      children: [
        // Page H1 — Iowan italic per page-identity rule
        // (CLAUDE.md: "Iowan italic = page identity moments only").
        Text(
          item?.label ?? 'Settings',
          style: TextStyle(
            fontFamily: 'Iowan Old Style',
            fontFamilyFallback: const ['Georgia', 'Charter', 'serif'],
            fontSize: 28,
            fontStyle: FontStyle.italic,
            letterSpacing: -0.3,
            color: cue.textPrimary,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '— coming soon',
          style: GoogleFonts.dmSans(
            fontSize: 13,
            color: cue.textMuted,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 22),
        for (var i = 0; i < blocks.length; i++)
          SettingsCard(
            title: blocks[i].title,
            subtitle: blocks[i].subtitle,
            initiallyExpanded: i == 0,
          ),
      ],
    );
  }
}

class _BlockSpec {
  final String title;
  final String? subtitle;
  const _BlockSpec(this.title, [this.subtitle]);
}

List<_BlockSpec> _blocksFor(String key) {
  switch (key) {
    case 'identity':
      return const [
        _BlockSpec('Display',
            'App-facing identity — display name, profile photo. Never on signed documents.'),
        _BlockSpec('Legal Identity',
            'Legal first/middle/last name, salutation, professional designation. Appears on signed PDFs.'),
        _BlockSpec('Statutory Registration',
            'RCI category, registration number, dates, renewal reminders. Gates signed-PDF generation.'),
        _BlockSpec('Education & Certifications',
            'Primary qualification, other qualifications, specialized certifications. Drives degree-suffix auto-compose.'),
        _BlockSpec('Signature & Letterhead',
            'Drawn or uploaded signature, letterhead style. Header content sources Practice Setup.'),
      ];
    case 'clinical':
      return const [
        _BlockSpec('Practice Language & Communication',
            'Primary clinical language, parent summary languages, report formality, reading level.'),
        _BlockSpec('Note Structure',
            'Default note format, section ordering. S + A + P always required for completion.'),
        _BlockSpec('Goal Framework',
            'Goal hierarchy depth, EBP frameworks, mastery criterion. STG cap locked to 3.'),
        _BlockSpec('Session Defaults',
            'Duration, type, attendance setting.'),
        _BlockSpec('Templates',
            'Parent intake, consent form, parent summary, discharge summary.'),
      ];
    case 'ai':
      return const [
        _BlockSpec('Autodraft Behavior',
            'SOAP notes, parent summaries, goals, session prep brief. Scope: current session / +last 3 / full history.'),
        _BlockSpec('Tone & Voice',
            'Parent summary tone, note draft tone, terminology use. Voice clone activates Phase 1.5+.'),
        _BlockSpec('Grounding & Safety',
            'Confidence indicator, source grounding, anti-hallucination — always on. EBP retrieval source configurable.'),
        _BlockSpec('Edit Threshold & Telemetry',
            'Alert if editing more than X% of generated content. Per-session edit ratio Phase 1.5+.'),
        _BlockSpec('Disclaimers & Attribution',
            'AI attribution on parent-shared PDFs (cannot be set to none). Custom disclaimer text.'),
      ];
    case 'practice':
      return const [
        _BlockSpec('Clinic Identity',
            'Clinic name, type, year established, logo, tagline.'),
        _BlockSpec('Address & Locations',
            'Address line 1/2, area, city, state, pincode. India-only Phase 1.'),
        _BlockSpec('Contact',
            'Clinic phone, email, WhatsApp Business, website.'),
        _BlockSpec('Practice Hours & Calendar',
            'Working days, hours, lunch block, holiday calendar source, custom holidays.'),
        _BlockSpec('Receipt & Billing Defaults',
            'Business display name, default session fee, receipt prefix + counter, FY reset.'),
      ];
    case 'notifications':
      return const [
        _BlockSpec('Channels',
            'In-app inbox (always on), push, email digest. SMS + WhatsApp Phase 2.'),
        _BlockSpec('Per-category routing',
            'Session cycle, clinical lifecycle, credential compliance, operational signals. Each chooses loudness.'),
        _BlockSpec('Quiet hours & cadence',
            'Do-not-disturb window, working-days-only mode, digest frequency. Critical overrides system-defined.'),
      ];
    case 'privacy':
      return const [
        _BlockSpec('My data rights',
            'Export, delete account (30-day grace), grievance officer, nominee, processing purposes.'),
        _BlockSpec('Client consent management',
            'Default consent template, renewal cadence, withdrawal workflow. Minor consent always on.'),
        _BlockSpec('Data sharing with Cue',
            'Anonymized telemetry, crash reports, product updates. Canonical sharing surface.'),
        _BlockSpec('Retention preferences',
            'Audit log retention (default 7y), soft-deleted client purge, discharged client archive.'),
        _BlockSpec('Processing transparency',
            'Data categories processed, sub-processors, data residency, DPDP rights notice.'),
      ];
    case 'security':
      return const [
        _BlockSpec('Password',
            'Change password, last change, strength. No forced rotation (NIST SP 800-63B).'),
        _BlockSpec('Two-factor authentication',
            'TOTP enable, recovery codes, trusted device window. Mandatory above 5 active clients.'),
        _BlockSpec('Active sessions & devices',
            'Per-session sign-out, sign-out-all-others, trusted devices.'),
        _BlockSpec('Timeout & re-auth',
            'Idle timeout (default 15 min, medical-grade), re-auth for sensitive actions, remember-me duration.'),
        _BlockSpec('Login history & alerts',
            'Login history, export, alerts on new device or location, failed-attempts counter.'),
      ];
    case 'audit':
      return const [
        _BlockSpec('Activity feed',
            'Reverse-chronological events. PII-encrypted rows tap to view (re-auth gated). Cohort grouping always on.'),
        _BlockSpec('Filters',
            'Date range, event category, severity, search. Save filter (max 5).'),
        _BlockSpec('Export & forensic actions',
            'Export current view, full audit history archive, report suspicious activity, verify chain integrity.'),
      ];
    case 'billing':
      return const [
        _BlockSpec('Current plan',
            'Tier, price, billing cycle, renewal date. Upgrade / downgrade / cancel.'),
        _BlockSpec('Payment method',
            'Primary method display. Updates route to Razorpay-hosted flow. Auto-renew toggle.'),
        _BlockSpec('Invoices & receipts',
            'Invoice history, downloads, billing email, optional GSTIN. Invoice schema gated on GST verification.'),
        _BlockSpec('Usage & limits',
            'AI generations, storage used, usage history, fair-use status. No hard caps Phase 1.'),
      ];
    case 'legal':
      return const [
        _BlockSpec('Legal documents',
            'Beta Access Agreement, Terms of Service, Privacy Policy, DPDP rights, cookie policy, acceptance history.'),
        _BlockSpec('Help & support',
            'Contact support, report clinical concern, bug report, feature suggestion, knowledge base, Engrams library.'),
        _BlockSpec('About Cue',
            'App version, release notes, open source acknowledgments, built by.'),
      ];
    default:
      return const [_BlockSpec('Coming soon.')];
  }
}
