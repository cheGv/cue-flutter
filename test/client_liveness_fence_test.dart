@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Delete affordances, Step 3 — liveness fence for capture loaders.
//
// The audit found that capture loaders key on client_id and never consult
// clients.deleted_at, so a soft-deleted client's assessments stayed
// reachable by id. ClientsQuery.requireLiveClient closes that; this fence
// keeps it closed: every lib/ file that READS a `*_assessments` parent
// table BY client_id must call requireLiveClient somewhere in the file.
// A new capture family that forgets the gate fails here, by name.
//
// Reads by assessment id (the bridge readers' readById) are not matched:
// they are reached only through a loader that already passed the gate, or
// through the assembler, which gates on its own.

final _fromAssessments = RegExp(
  r'''\.from\((['"])([a-z_]+_assessments)\1\)''',
);
const _writeOps = ['.update(', '.insert(', '.upsert(', '.delete('];

void main() {
  test('every client-keyed *_assessments READ in lib/ sits behind '
      'requireLiveClient', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue,
        reason: 'run from the package root (cwd should contain lib/)');

    final offenders = <String>[];
    final gatedFiles = <String>{};
    var clientKeyedReads = 0;

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      final lines = source.split('\n');

      for (var i = 0; i < lines.length; i++) {
        if (!_fromAssessments.hasMatch(lines[i])) continue;

        // The query chain: following lines until the next `.from(` or the
        // statement ends, capped at 14 lines.
        final chain = StringBuffer(lines[i]);
        for (var j = i + 1; j < lines.length && j <= i + 14; j++) {
          final l = lines[j];
          if (l.contains('.from(')) break;
          chain.write('\n');
          chain.write(l);
          if (l.trim().endsWith(';')) break;
        }
        final text = chain.toString();
        if (_writeOps.any(text.contains)) continue;
        if (!text.contains("'client_id'")) continue;

        clientKeyedReads++;
        if (source.contains('requireLiveClient(')) {
          gatedFiles.add(entity.path);
        } else {
          offenders.add('${entity.path}:${i + 1}');
        }
      }
    }

    // The five families on this branch: ald, cas, voice, ped_dysarthria,
    // ped_language. If this drops, the scanner is broken, which would
    // hide a leak.
    expect(clientKeyedReads, greaterThanOrEqualTo(5),
        reason: 'expected the known client-keyed loaders; found '
            '$clientKeyedReads');
    expect(gatedFiles.length, greaterThanOrEqualTo(5),
        reason: 'gated loader files: $gatedFiles');

    expect(
      offenders,
      isEmpty,
      reason: 'These client-keyed assessment reads never call '
          'requireLiveClient — a soft-deleted client would stay reachable '
          'here by id:\n${offenders.join('\n')}',
    );
  });

  // Join surfaces (daily_roster / sessions / goals embedding `clients`) sit
  // outside the ClientsQuery gate by design and wall trial rows at their
  // own call sites. The deleted wall must stand beside the trial wall at
  // every one of them: an embedded `.eq('clients.is_trial_case', false)`
  // needs `clients.deleted_at` in the same chain, and an embedded select
  // that reads `is_trial_case` for an app-side skip must read `deleted_at`
  // too. A soft-deleted client on today's roster would otherwise still get
  // a Today card and fire a brief — "hidden from lists" failing on the
  // first list the clinician sees.
  test('every embedded trial wall on a join surface has the deleted wall '
      'beside it', () {
    final libDir = Directory('lib');
    final offenders = <String>[];
    var wallSites = 0;

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (l.trimLeft().startsWith('//')) continue;

        if (l.contains("'clients.is_trial_case'")) {
          wallSites++;
          final chain = lines
              .sublist(i - 12 < 0 ? 0 : i - 12,
                  i + 6 > lines.length ? lines.length : i + 6)
              .join('\n');
          if (!chain.contains("'clients.deleted_at'")) {
            offenders.add('${entity.path}:${i + 1} (embedded filter)');
          }
          continue;
        }

        final embeddedSelect =
            RegExp(r'clients(?:!inner)?\(([^)]*)\)').firstMatch(l);
        if (embeddedSelect != null &&
            embeddedSelect.group(1)!.contains('is_trial_case')) {
          wallSites++;
          if (!embeddedSelect.group(1)!.contains('deleted_at')) {
            offenders.add('${entity.path}:${i + 1} (embedded select)');
          }
        }
      }
    }

    // today_screen ×2, clients_roster_service ×1, today_widgets_service ×5.
    expect(wallSites, greaterThanOrEqualTo(8),
        reason: 'expected the known join-surface trial walls; found '
            '$wallSites');
    expect(
      offenders,
      isEmpty,
      reason: 'These join surfaces wall trial rows but not soft-deleted '
          'clients:\n${offenders.join('\n')}',
    );
  });
}
