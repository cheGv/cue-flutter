#!/usr/bin/env node
// test/rls/rls_regression_harness.js
//
// STATUS (2026-07-28): kept for FUTURE CI USE. This Node edition needs
// CUE_SANDBOX_DB_URL (a direct sandbox Postgres URI) and HAS NOT been
// executed that way — the URI is not available in the dev environment.
// The VALIDATED harness is the connector edition alongside this file,
// test/rls/rls_regression_harness.sql (first green run 2026-07-28,
// 55/55; mutation-validated: dropping clinician_reads_own_generations
// failed exactly the one expected assertion). The two editions assert
// the same surface; keep their assertion lists and the allowlist in
// sync when either changes.
//
// RLS regression harness for the sealed sandbox table families:
//   ped_language_, feeding_, ssd_, cas_ (incl. cas_session_progress,
//   cas_progress_brief, cas_ddk_norms), generations, and the
//   reference-shape tables (substrate_relations, legal_documents).
//
// For every family it asserts, from three JWT contexts plus the
// service role:
//   - the OWNING clinician inserts/updates/reads back her own rows
//   - a SECOND authenticated clinician reads 0 rows, her update touches
//     0 rows, and her inserts are rejected with SQLSTATE 42501
//   - ANON reads 0 rows and every insert is rejected with 42501
//   - reference tables allow any authenticated SELECT and reject
//     authenticated writes (42501)
//   - generations rejects even the OWNER's insert (writes are
//     service-role only; the service_role write path is asserted too)
//   - the cas_progress_brief SECURITY DEFINER trigger still fires and
//     writes through the SELECT-only policy wall
//
// Method: one Postgres connection (the session user must be the table
// owner, e.g. `postgres` via the Supabase session pooler). Each context
// runs inside a transaction after
//   set_config('role', <role>, true) +
//   set_config('request.jwt.claims', '{"sub": <uuid>}', true)
// which is exactly how PostgREST establishes RLS identity — the same
// method used for the migration-time proofs on 2026-07-26.
//
// Run:
//   CUE_SANDBOX_DB_URL='postgresql://postgres.uuqhusmgoiaxdvtgbmwh:...' \
//     node test/rls/rls_regression_harness.js
// (or `npm test` from test/rls after `npm install`). Exit code 0 =
// every assertion passed; any failure prints `not ok` lines and exits 1.
//
// Safety rails: refuses to run unless the connection string contains
// the SANDBOX project ref AND the database itself carries the sandbox
// sentinel migration (belt + suspenders against a prod URI); takes a
// pg advisory lock so two concurrent runs cannot corrupt each other;
// expected-rejection probes ALWAYS roll back (a leaked probe row can
// never persist, even when RLS has regressed); all persistent fixture
// rows use fixed harness UUIDs (a11ce5ed-*) or 'rls-harness' markers;
// a pre-clean pass makes reruns idempotent after a crashed run;
// teardown deletes every fixture and the final assertion is a
// zero-residue audit.
//
// Documented residual risk: the fixture client is parented on a REAL
// clinician auth user (clients.clinician_id FK requires one), so for
// the duration of a run — or a crash window until the next run's
// pre-clean — that clinician's roster shows a client named
// "RLS HARNESS FIXTURE — do not touch". Anything a human attaches to
// it in that window is deleted with it at teardown. The loud name is
// the guard; do not run the harness during live clinical use of the
// sandbox. The cas_ddk_norms probe row is likewise briefly visible to
// authenticated app reads; its age band is 996-999 months so it can
// never match a real child and never drives the DDK banding UI.

'use strict';

const { Client } = require('pg');

const SANDBOX_REF = 'uuqhusmgoiaxdvtgbmwh';

// ── Fixture identity ─────────────────────────────────────────────────
// All uuids are fixed so pre-clean/teardown can target them exactly.
const F = {
  client:    'a11ce5ed-0000-4000-8000-000000000001',
  ltg:       'a11ce5ed-0000-4000-8000-000000000002',
  stg:       'a11ce5ed-0000-4000-8000-000000000003',
  // Second STG with NO progress rows and NO brief row: the
  // cas_progress_brief owner-INSERT probe aims here so a policy
  // regression surfaces as "unexpectedly SUCCEEDED", never as a
  // misattributed PK conflict on the trigger-created brief row.
  stg2:      'a11ce5ed-0000-4000-8000-000000000004',
  sessionId: 999999901, // sessions.id is bigint with no default

  plParent:  'a11ce5ed-0001-4000-8000-000000000001',
  plRow:     'a11ce5ed-0001-4000-8000-000000000002',

  fdParent:  'a11ce5ed-0002-4000-8000-000000000001',
  fdBand:    'a11ce5ed-0002-4000-8000-000000000002',
  fdBeh:     'a11ce5ed-0002-4000-8000-000000000003',

  ssdParent: 'a11ce5ed-0003-4000-8000-000000000001',
  ssdTs:     'a11ce5ed-0003-4000-8000-000000000002',
  ssdPp:     'a11ce5ed-0003-4000-8000-000000000003',
  ssdCw:     'a11ce5ed-0003-4000-8000-000000000004',
  ssdLe:     'a11ce5ed-0003-4000-8000-000000000005',
  ssdWw:     'a11ce5ed-0003-4000-8000-000000000006',

  casParent: 'a11ce5ed-0004-4000-8000-000000000001',
  casGrad:   'a11ce5ed-0004-4000-8000-000000000002',
  casDdk:    'a11ce5ed-0004-4000-8000-000000000003',
  casProg:   'a11ce5ed-0004-4000-8000-000000000004',

  genRow:    'a11ce5ed-0005-4000-8000-000000000001',
  normRow:   'a11ce5ed-0006-4000-8000-000000000001',
  legalRow:  'a11ce5ed-0006-4000-8000-000000000002',
  relRow:    'a11ce5ed-0006-4000-8000-000000000003',
};

const INTRUDER = '00000000-0000-4000-8000-0000000000ff';

// ── Assertion plumbing ───────────────────────────────────────────────
let testNo = 0;
let failures = 0;

function ok(desc) {
  testNo += 1;
  console.log(`ok ${testNo} - ${desc}`);
}

function notOk(desc, detail) {
  testNo += 1;
  failures += 1;
  console.log(`not ok ${testNo} - ${desc}`);
  if (detail) console.log(`  ---\n  ${String(detail).replace(/\n/g, '\n  ')}\n  ...`);
}

function assertEq(actual, expected, desc) {
  // pg returns count(*) as a string; normalise numbers for comparison.
  const a = typeof expected === 'number' ? Number(actual) : actual;
  if (a === expected) ok(desc);
  else notOk(desc, `expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
}

async function main() {
  const url = process.env.CUE_SANDBOX_DB_URL;
  if (!url) {
    console.error(
      'CUE_SANDBOX_DB_URL is not set.\n' +
      'Supply the SANDBOX Postgres connection string (Supabase dashboard → ' +
      'Connect → Session pooler URI for project ' + SANDBOX_REF + ').');
    process.exit(2);
  }
  if (!url.includes(SANDBOX_REF)) {
    console.error(
      'Refusing to run: the connection string does not reference the sandbox ' +
      `project (${SANDBOX_REF}). This harness writes fixture rows and must ` +
      'never point at production.');
    process.exit(2);
  }

  const db = new Client({ connectionString: url });
  // Without a listener, an idle-time connection error is an unhandled
  // 'error' event that crashes the process and skips teardown. With
  // one, the in-flight query still rejects and the finally runs.
  db.on('error', (e) => {
    console.error(`# connection error: ${e.message}`);
  });
  await db.connect();

  const q = (sql, params) => db.query(sql, params);

  // Belt + suspenders on top of the URI substring check: the database
  // itself must carry a sandbox-only sentinel (the ped_language tables
  // migration, which was never applied to prod).
  const sentinel = await q(
    `select exists(select 1 from supabase_migrations.schema_migrations
                   where name = 'ped_language_assessment_tables') as ok`);
  if (!sentinel.rows[0].ok) {
    console.error('Refusing to run: connected database lacks the sandbox ' +
      'sentinel migration (ped_language_assessment_tables). This does not ' +
      'look like the Cue sandbox.');
    await db.end();
    process.exit(2);
  }

  // One run at a time — concurrent runs would corrupt each other's
  // fixtures and emit false regression verdicts.
  const lock = await q(
    `select pg_try_advisory_lock(hashtext('cue_rls_harness')) as got`);
  if (!lock.rows[0].got) {
    console.error('Refusing to run: another harness run holds the advisory ' +
      'lock. Wait for it to finish (the lock releases on disconnect).');
    await db.end();
    process.exit(2);
  }

  // Runs fn inside a transaction under the given PostgREST-style
  // identity. Commits on success (fixture writes must persist across
  // contexts), rolls back on error.
  async function asCtx(role, sub, fn) {
    await q('begin');
    try {
      await q(
        `select set_config('role', $1, true),
                set_config('request.jwt.claims', $2, true)`,
        [role, JSON.stringify(sub ? { sub } : {})]);
      const out = await fn();
      await q('commit');
      return out;
    } catch (e) {
      // Guarded so a connection-fatal failure surfaces the ORIGINAL
      // error, not the rollback's follow-on failure.
      try { await q('rollback'); } catch (_) { /* connection is gone */ }
      throw e;
    }
  }

  // Asserts that running `sql` under the identity fails with 42501.
  // ALWAYS rolls back — including when the statement unexpectedly
  // succeeds. That success is precisely the regression this harness
  // exists to catch, and committing the probe there would leak a
  // random-id row that pre-clean/teardown/the residue audit cannot
  // reach (and, for ped_language probes, one that blocks the fixture
  // client's teardown delete — that FK has no cascade).
  async function expectRls(role, sub, sql, desc) {
    await q('begin');
    try {
      await q(
        `select set_config('role', $1, true),
                set_config('request.jwt.claims', $2, true)`,
        [role, JSON.stringify(sub ? { sub } : {})]);
      await q(sql);
      notOk(desc, 'statement unexpectedly SUCCEEDED (probe rolled back)');
    } catch (e) {
      if (e.code === '42501') ok(desc);
      else notOk(desc, `expected SQLSTATE 42501, got ${e.code}: ${e.message}`);
    } finally {
      try { await q('rollback'); } catch (_) { /* connection is gone */ }
    }
  }

  // Deletes every fixture row. Used both as pre-clean (idempotent
  // reruns after a crash) and as teardown. Runs as the session user
  // (table owner — bypasses RLS), dependency order.
  async function removeFixtures() {
    await q('reset role');
    await q(`delete from public.cas_session_progress where id = $1`, [F.casProg]);
    await q(`delete from public.cas_progress_brief where stg_id = $1`, [F.stg]);
    await q(`delete from public.ped_language_assessments where id = $1`, [F.plParent]);
    await q(`delete from public.feeding_assessments where id = $1`, [F.fdParent]);
    await q(`delete from public.ssd_assessments where id = $1`, [F.ssdParent]);
    await q(`delete from public.cas_assessments where id = $1`, [F.casParent]);
    await q(`delete from public.generations where id = $1`, [F.genRow]);
    await q(`delete from public.cas_ddk_norms where id = $1`, [F.normRow]);
    await q(`delete from public.legal_documents where id = $1`, [F.legalRow]);
    await q(`delete from public.substrate_relations where id = $1`, [F.relRow]);
    await q(`delete from public.cas_progress_brief where stg_id = $1`, [F.stg2]);
    await q(`delete from public.short_term_goals where id in ($1, $2)`, [F.stg, F.stg2]);
    await q(`delete from public.long_term_goals where id = $1`, [F.ltg]);
    await q(`delete from public.sessions where id = $1`, [F.sessionId]);
    await q(`delete from public.clients where id = $1`, [F.client]);
  }

  async function fixtureResidueCount() {
    const { rows } = await q(`
      select (select count(*) from public.cas_session_progress where id = $1)
           + (select count(*) from public.cas_progress_brief where stg_id = $2)
           + (select count(*) from public.ped_language_assessments where id = $3)
           + (select count(*) from public.ped_language_milestones where id = $4)
           + (select count(*) from public.feeding_assessments where id = $5)
           + (select count(*) from public.ssd_assessments where id = $6)
           + (select count(*) from public.cas_assessments where id = $7)
           + (select count(*) from public.generations where id = $8)
           + (select count(*) from public.cas_ddk_norms where id = $9)
           + (select count(*) from public.legal_documents where id = $10)
           + (select count(*) from public.substrate_relations where id = $11)
           + (select count(*) from public.short_term_goals where id in ($12, $16))
           + (select count(*) from public.long_term_goals where id = $13)
           + (select count(*) from public.sessions where id = $14)
           + (select count(*) from public.clients where id = $15)
           + (select count(*) from public.cas_progress_brief where stg_id = $16) as n`,
      [F.casProg, F.stg, F.plParent, F.plRow, F.fdParent, F.ssdParent,
       F.casParent, F.genRow, F.normRow, F.legalRow, F.relRow,
       F.stg, F.ltg, F.sessionId, F.client, F.stg2]);
    return Number(rows[0].n);
  }

  let owner = null;
  try {
    // ── Sanity + identity discovery ─────────────────────────────────
    const who = await q(`select current_database() as db`);
    console.log(`# connected to ${who.rows[0].db} (${SANDBOX_REF})`);

    const users = await q(
      `select id from auth.users order by created_at asc limit 1`);
    if (users.rows.length === 0) {
      console.error('No auth.users row exists — the harness needs one real ' +
        'clinician identity to own fixtures (clients.clinician_id has an FK ' +
        'to auth.users). Aborting.');
      process.exit(2);
    }
    owner = users.rows[0].id;
    console.log(`# owner identity: ${owner}  intruder: ${INTRUDER} (no user row needed)`);

    // ── Catalog-diff invariant ──────────────────────────────────────
    // Every public table must be sealed (rowsecurity=true) OR carry an
    // explicit reason in rls_allowlist.json. A table that is neither —
    // including one created after this harness was written — fails the
    // run. Stale allowlist entries (now sealed, or dropped) warn.
    console.log('# catalog-diff invariant');
    {
      const allow = require('./rls_allowlist.json').tables;
      const cat = await q(
        `select tablename, rowsecurity from pg_tables
         where schemaname = 'public' order by tablename`);
      const live = new Set(cat.rows.map((r) => r.tablename));
      const uncovered = cat.rows
        .filter((r) => !r.rowsecurity && !(r.tablename in allow))
        .map((r) => r.tablename);
      const stale = [
        ...cat.rows.filter((r) => r.rowsecurity && r.tablename in allow)
          .map((r) => `${r.tablename} (now sealed)`),
        ...Object.keys(allow).filter((t) => !live.has(t))
          .map((t) => `${t} (no longer exists)`),
      ];
      assertEq(uncovered.join(', '), '',
        'catalog diff: every public table is sealed or allowlisted');
      if (stale.length) {
        console.log(`# warning: stale allowlist entries: ${stale.join(', ')}`);
      }
    }

    // ── Pre-clean (idempotent reruns) + fixture spine ───────────────
    await removeFixtures();
    await q('reset role');
    await q(
      `insert into public.clients (id, clinician_id, name, age)
       values ($1, $2, 'RLS HARNESS FIXTURE — do not touch (auto-deleted)', 3)`,
      [F.client, owner]);
    await q(
      `insert into public.long_term_goals (id, client_id, user_id, domain, goal_text)
       values ($1, $2, $3, 'rls-harness', 'RLS harness fixture LTG')`,
      [F.ltg, F.client, owner]);
    await q(
      `insert into public.short_term_goals
         (id, long_term_goal_id, client_id, user_id, specific, measurable)
       values ($1, $2, $3, $4, 'RLS harness fixture STG', 'n/a')`,
      [F.stg, F.ltg, F.client, owner]);
    await q(
      `insert into public.short_term_goals
         (id, long_term_goal_id, client_id, user_id, specific, measurable)
       values ($1, $2, $3, $4, 'RLS harness fixture STG 2 (no brief)', 'n/a')`,
      [F.stg2, F.ltg, F.client, owner]);
    await q(
      `insert into public.sessions (id, client_id, user_id)
       values ($1, $2, $3)`, [F.sessionId, F.client, owner]);
    console.log('# fixture spine created (client, LTG, STG, session)');

    // ════ ped_language_ ════════════════════════════════════════════
    console.log('# family: ped_language_');
    await asCtx('authenticated', owner, async () => {
      await q(
        `insert into public.ped_language_assessments
           (id, client_id, clinician_id, band_key, derived_age_months, age_source)
         values ($1, $2, $3, '2_to_3y', 30, 'dob')`, [F.plParent, F.client, owner]);
      await q(
        `insert into public.ped_language_milestones
           (id, ped_language_assessment_id, section, milestone_order,
            milestone_text, norm_reference, library_version)
         values ($1, $2, 'speech', 999, 'RLS harness probe',
                 'RLS harness', '0.0.0-harness')`, [F.plRow, F.plParent]);
      await q(
        `update public.ped_language_assessments
           set capture_notes = 'harness-owner' where id = $1`, [F.plParent]);
      const r = await q(
        `select (select count(*) from public.ped_language_assessments where id = $1) as p,
                (select count(*) from public.ped_language_milestones  where id = $2) as c,
                (select capture_notes from public.ped_language_assessments where id = $1) as note`,
        [F.plParent, F.plRow]);
      assertEq(r.rows[0].p, 1, 'ped_language: owner sees her parent row');
      assertEq(r.rows[0].c, 1, 'ped_language: owner sees her milestone row');
      assertEq(r.rows[0].note, 'harness-owner', 'ped_language: owner update reads back');
    });
    await asCtx('authenticated', INTRUDER, async () => {
      const r = await q(
        `with upd as (update public.ped_language_assessments
                        set capture_notes = 'intruder' where id = $1 returning 1)
         select (select count(*) from public.ped_language_assessments where id = $1) as p,
                (select count(*) from public.ped_language_milestones  where id = $2) as c,
                (select count(*) from upd) as u`, [F.plParent, F.plRow]);
      assertEq(r.rows[0].p, 0, 'ped_language: intruder sees 0 parent rows');
      assertEq(r.rows[0].c, 0, 'ped_language: intruder sees 0 milestone rows');
      assertEq(r.rows[0].u, 0, 'ped_language: intruder update touches 0 rows');
    });
    await expectRls('authenticated', INTRUDER,
      `insert into public.ped_language_assessments
         (client_id, band_key, derived_age_months, age_source)
       values ('${F.client}', '2_to_3y', 30, 'dob')`,
      'ped_language: intruder insert rejected 42501');
    await asCtx('anon', null, async () => {
      const r = await q(
        `select (select count(*) from public.ped_language_assessments) as p,
                (select count(*) from public.ped_language_milestones) as c`);
      assertEq(r.rows[0].p, 0, 'ped_language: anon sees 0 parent rows');
      assertEq(r.rows[0].c, 0, 'ped_language: anon sees 0 milestone rows');
    });
    await expectRls('anon', null,
      `insert into public.ped_language_assessments
         (client_id, band_key, derived_age_months, age_source)
       values ('${F.client}', '2_to_3y', 30, 'dob')`,
      'ped_language: anon parent insert rejected 42501');
    await expectRls('anon', null,
      `insert into public.ped_language_milestones
         (ped_language_assessment_id, section, milestone_order,
          milestone_text, norm_reference, library_version)
       values ('${F.plParent}', 'speech', 998, 'anon probe', 'x', 'x')`,
      'ped_language: anon child insert rejected 42501');

    // ════ feeding_ ═════════════════════════════════════════════════
    console.log('# family: feeding_');
    await asCtx('authenticated', owner, async () => {
      await q(
        `insert into public.feeding_assessments (id, client_id, clinician_id, age_months)
         values ($1, $2, $3, 30)`, [F.fdParent, F.client, owner]);
      await q(
        `insert into public.feeding_ladder_bands
           (id, feeding_assessment_id, band_key, band_order, band_label, age_min_months,
            expected_texture, expected_self_feeding, expected_oral_motor,
            red_flag_prompt, off_ramp_band)
         values ($1, $2, 'rls_harness', 999, 'RLS harness band', 0,
                 'probe', 'probe', 'probe', 'probe', false)`, [F.fdBand, F.fdParent]);
      await q(
        `insert into public.feeding_behaviors
           (id, feeding_assessment_id, behavior_label, airway_sign)
         values ($1, $2, 'RLS harness behavior', false)`, [F.fdBeh, F.fdParent]);
      await q(
        `update public.feeding_assessments set capture_notes = 'harness-owner'
         where id = $1`, [F.fdParent]);
      const r = await q(
        `select (select count(*) from public.feeding_assessments  where id = $1) as p,
                (select count(*) from public.feeding_ladder_bands where id = $2) as b,
                (select count(*) from public.feeding_behaviors    where id = $3) as h,
                (select capture_notes from public.feeding_assessments where id = $1) as note`,
        [F.fdParent, F.fdBand, F.fdBeh]);
      assertEq(r.rows[0].p, 1, 'feeding: owner sees her parent row');
      assertEq(r.rows[0].b, 1, 'feeding: owner sees her ladder-band row');
      assertEq(r.rows[0].h, 1, 'feeding: owner sees her behavior row');
      assertEq(r.rows[0].note, 'harness-owner', 'feeding: owner update reads back');
    });
    await asCtx('authenticated', INTRUDER, async () => {
      const r = await q(
        `with upd as (update public.feeding_assessments
                        set capture_notes = 'intruder' where id = $1 returning 1)
         select (select count(*) from public.feeding_assessments  where id = $1) as p,
                (select count(*) from public.feeding_ladder_bands where id = $2) as b,
                (select count(*) from public.feeding_behaviors    where id = $3) as h,
                (select count(*) from upd) as u`, [F.fdParent, F.fdBand, F.fdBeh]);
      assertEq(r.rows[0].p, 0, 'feeding: intruder sees 0 parent rows');
      assertEq(Number(r.rows[0].b) + Number(r.rows[0].h), 0,
        'feeding: intruder sees 0 child rows');
      assertEq(r.rows[0].u, 0, 'feeding: intruder update touches 0 rows');
    });
    await expectRls('authenticated', INTRUDER,
      `insert into public.feeding_assessments (client_id, age_months)
       values ('${F.client}', 24)`,
      'feeding: intruder insert rejected 42501');
    await asCtx('anon', null, async () => {
      const r = await q(
        `select (select count(*) from public.feeding_assessments where id = '${F.fdParent}') as p`);
      assertEq(r.rows[0].p, 0, 'feeding: anon sees 0 rows');
    });
    await expectRls('anon', null,
      `insert into public.feeding_assessments (client_id, age_months)
       values ('${F.client}', 24)`,
      'feeding: anon parent insert rejected 42501');
    await expectRls('anon', null,
      `insert into public.feeding_behaviors
         (feeding_assessment_id, behavior_label, airway_sign)
       values ('${F.fdParent}', 'anon probe', false)`,
      'feeding: anon child insert rejected 42501');

    // ════ ssd_ ═════════════════════════════════════════════════════
    console.log('# family: ssd_');
    await asCtx('authenticated', owner, async () => {
      await q(
        `insert into public.ssd_assessments (id, client_id, clinician_id, age_months)
         values ($1, $2, $3, 48)`, [F.ssdParent, F.client, owner]);
      await q(
        `insert into public.ssd_target_sounds (id, ssd_assessment_id, target_phoneme)
         values ($1, $2, '/harness/')`, [F.ssdTs, F.ssdParent]);
      await q(
        `insert into public.ssd_phonological_processes (id, ssd_assessment_id, process_name)
         values ($1, $2, 'rls_harness')`, [F.ssdPp, F.ssdParent]);
      await q(
        `insert into public.ssd_consistency_words (id, ssd_assessment_id, word, word_order)
         values ($1, $2, 'rls-harness', 999)`, [F.ssdCw, F.ssdParent]);
      await q(
        `insert into public.ssd_length_effect (id, ssd_assessment_id, level_label, level_order)
         values ($1, $2, 'rls-harness', 999)`, [F.ssdLe, F.ssdParent]);
      await q(
        `insert into public.ssd_whole_word (id, ssd_assessment_id, word, word_order)
         values ($1, $2, 'rls-harness', 999)`, [F.ssdWw, F.ssdParent]);
      await q(
        `update public.ssd_assessments set capture_notes = 'harness-owner'
         where id = $1`, [F.ssdParent]);
      const r = await q(
        `select (select count(*) from public.ssd_assessments where id = $1) as p,
                (select count(*) from public.ssd_target_sounds where id = $2)
              + (select count(*) from public.ssd_phonological_processes where id = $3)
              + (select count(*) from public.ssd_consistency_words where id = $4)
              + (select count(*) from public.ssd_length_effect where id = $5)
              + (select count(*) from public.ssd_whole_word where id = $6) as c,
                (select capture_notes from public.ssd_assessments where id = $1) as note`,
        [F.ssdParent, F.ssdTs, F.ssdPp, F.ssdCw, F.ssdLe, F.ssdWw]);
      assertEq(r.rows[0].p, 1, 'ssd: owner sees her parent row');
      assertEq(r.rows[0].c, 5, 'ssd: owner sees all five child rows');
      assertEq(r.rows[0].note, 'harness-owner', 'ssd: owner update reads back');
    });
    await asCtx('authenticated', INTRUDER, async () => {
      const r = await q(
        `with upd as (update public.ssd_assessments
                        set capture_notes = 'intruder' where id = $1 returning 1)
         select (select count(*) from public.ssd_assessments where id = $1) as p,
                (select count(*) from public.ssd_target_sounds where ssd_assessment_id = $1)
              + (select count(*) from public.ssd_phonological_processes where ssd_assessment_id = $1)
              + (select count(*) from public.ssd_consistency_words where ssd_assessment_id = $1)
              + (select count(*) from public.ssd_length_effect where ssd_assessment_id = $1)
              + (select count(*) from public.ssd_whole_word where ssd_assessment_id = $1) as c,
                (select count(*) from upd) as u`, [F.ssdParent]);
      assertEq(r.rows[0].p, 0, 'ssd: intruder sees 0 parent rows');
      assertEq(r.rows[0].c, 0, 'ssd: intruder sees 0 child rows');
      assertEq(r.rows[0].u, 0, 'ssd: intruder update touches 0 rows');
    });
    await expectRls('authenticated', INTRUDER,
      `insert into public.ssd_assessments (client_id, age_months)
       values ('${F.client}', 36)`,
      'ssd: intruder insert rejected 42501');
    await asCtx('anon', null, async () => {
      const r = await q(
        `select (select count(*) from public.ssd_assessments where id = '${F.ssdParent}') as p`);
      assertEq(r.rows[0].p, 0, 'ssd: anon sees 0 rows');
    });
    await expectRls('anon', null,
      `insert into public.ssd_assessments (client_id, age_months)
       values ('${F.client}', 36)`,
      'ssd: anon parent insert rejected 42501');
    await expectRls('anon', null,
      `insert into public.ssd_target_sounds (ssd_assessment_id, target_phoneme)
       values ('${F.ssdParent}', '/anon/')`,
      'ssd: anon child insert rejected 42501');

    // ════ cas_ (assessment trio + session progress + brief) ════════
    console.log('# family: cas_');
    await asCtx('authenticated', owner, async () => {
      await q(
        `insert into public.cas_assessments (id, client_id, clinician_id, age_months)
         values ($1, $2, $3, 54)`, [F.casParent, F.client, owner]);
      await q(
        `insert into public.cas_length_gradient (id, cas_assessment_id, level_label, level_order)
         values ($1, $2, 'rls-harness', 999)`, [F.casGrad, F.casParent]);
      await q(
        `insert into public.cas_ddk (id, cas_assessment_id, task)
         values ($1, $2, 'pa')`, [F.casDdk, F.casParent]);
      const r = await q(
        `select (select count(*) from public.cas_assessments where id = $1) as p,
                (select count(*) from public.cas_length_gradient where id = $2)
              + (select count(*) from public.cas_ddk where id = $3) as c`,
        [F.casParent, F.casGrad, F.casDdk]);
      assertEq(r.rows[0].p, 1, 'cas: owner sees her assessment row');
      assertEq(r.rows[0].c, 2, 'cas: owner sees her gradient + ddk rows');
    });
    await expectRls('authenticated', INTRUDER,
      `insert into public.cas_assessments (client_id, age_months)
       values ('${F.client}', 40)`,
      'cas: intruder insert rejected 42501');
    await asCtx('authenticated', INTRUDER, async () => {
      const r = await q(
        `select (select count(*) from public.cas_assessments where id = '${F.casParent}') as p`);
      assertEq(r.rows[0].p, 0, 'cas: intruder sees 0 assessment rows');
    });
    await expectRls('anon', null,
      `insert into public.cas_length_gradient (cas_assessment_id, level_label, level_order)
       values ('${F.casParent}', 'anon', 998)`,
      'cas: anon child insert rejected 42501');

    // session progress + the DEFINER trigger through the SELECT-only wall
    await asCtx('authenticated', owner, async () => {
      await q(
        `insert into public.cas_session_progress
           (id, stg_id, session_id, client_id, level_label, level_order)
         values ($1, $2, $3, $4, 'rls-harness', 999)`,
        [F.casProg, F.stg, F.sessionId, F.client]);
      const r = await q(
        `with direct_write as (
           update public.cas_progress_brief set is_dirty = false
           where stg_id = $1 returning 1)
         select (select count(*) from public.cas_progress_brief where stg_id = $1) as visible,
                (select is_dirty from public.cas_progress_brief where stg_id = $1) as dirty,
                (select count(*) from direct_write) as direct`, [F.stg]);
      assertEq(r.rows[0].visible, 1,
        'cas_progress_brief: DEFINER trigger wrote the brief row (owner can SELECT it)');
      assertEq(r.rows[0].dirty, true,
        'cas_progress_brief: trigger set is_dirty=true through the SELECT-only wall');
      assertEq(r.rows[0].direct, 0,
        'cas_progress_brief: owner direct UPDATE touches 0 rows (no write policy)');
    });
    // Aimed at stg2, which has NO brief row — so a policy regression
    // surfaces as "unexpectedly SUCCEEDED", never as a PK conflict on
    // the trigger-created row.
    await expectRls('authenticated', owner,
      `insert into public.cas_progress_brief (stg_id, client_id, is_dirty)
       values ('${F.stg2}', '${F.client}', true)`,
      'cas_progress_brief: owner direct INSERT rejected 42501');
    await asCtx('authenticated', INTRUDER, async () => {
      const r = await q(
        `select (select count(*) from public.cas_session_progress where id = '${F.casProg}') as sp,
                (select count(*) from public.cas_progress_brief where stg_id = '${F.stg}') as br`);
      assertEq(r.rows[0].sp, 0, 'cas_session_progress: intruder sees 0 rows');
      assertEq(r.rows[0].br, 0, 'cas_progress_brief: intruder sees 0 rows');
    });
    await asCtx('anon', null, async () => {
      const r = await q(
        `select (select count(*) from public.cas_session_progress) as sp,
                (select count(*) from public.cas_progress_brief) as br`);
      assertEq(r.rows[0].sp, 0, 'cas_session_progress: anon sees 0 rows');
      assertEq(r.rows[0].br, 0, 'cas_progress_brief: anon sees 0 rows');
    });

    // ════ generations (writes are service-role only) ═══════════════
    console.log('# family: generations');
    await asCtx('service_role', null, async () => {
      await q(
        `insert into public.generations (id, clinician_id, endpoint, status)
         values ($1, $2, 'rls-harness', 'success')`, [F.genRow, owner]);
      ok('generations: service_role insert succeeds (proxy write path)');
    });
    await asCtx('authenticated', owner, async () => {
      const r = await q(
        `select count(*) as n from public.generations where id = '${F.genRow}'`);
      assertEq(r.rows[0].n, 1, 'generations: owner reads her own row');
    });
    await asCtx('authenticated', INTRUDER, async () => {
      const r = await q(
        `select count(*) as n from public.generations where id = '${F.genRow}'`);
      assertEq(r.rows[0].n, 0, 'generations: intruder reads 0 rows');
    });
    await asCtx('anon', null, async () => {
      const r = await q(`select count(*) as n from public.generations`);
      assertEq(r.rows[0].n, 0, 'generations: anon reads 0 rows');
    });
    await expectRls('authenticated', owner,
      `insert into public.generations (clinician_id, endpoint, status)
       values ('${owner}', 'owner-probe', 'success')`,
      'generations: EVEN THE OWNER insert rejected 42501 (service-role only)');
    await expectRls('anon', null,
      `insert into public.generations (clinician_id, endpoint, status)
       values ('${owner}', 'anon-probe', 'success')`,
      'generations: anon insert rejected 42501');

    // ════ reference tables ═════════════════════════════════════════
    console.log('# reference tables: cas_ddk_norms, substrate_relations, legal_documents');
    await q('reset role');
    // Age band 996-999 months (~83 years): can never match a real
    // child's age, so this probe row can never activate the CAS DDK
    // banding UI even while it is briefly live to authenticated reads.
    await q(
      `insert into public.cas_ddk_norms
         (id, task, age_months_min, age_months_max, mean_syl_per_sec,
          sd_syl_per_sec, source_citation)
       values ($1, 'amr', 996, 999, 4.2, 0.6, 'RLS harness probe — not a real norm')`,
      [F.normRow]);
    await q(
      `insert into public.legal_documents (id, doc_type, version, content, effective_from)
       values ($1, 'rls_harness', 'v0', 'RLS harness probe', now())`, [F.legalRow]);
    await q(
      `insert into public.substrate_relations
         (id, source_tag, target_tag, strength, direction, reasoning)
       values ($1, 'rls-harness-a', 'rls-harness-b', 'weak', 'mutual', 'harness probe')`,
      [F.relRow]);
    await asCtx('authenticated', INTRUDER, async () => {
      const r = await q(
        `select (select count(*) from public.cas_ddk_norms where id = '${F.normRow}') as n,
                (select count(*) from public.legal_documents where id = '${F.legalRow}') as l,
                (select count(*) from public.substrate_relations where id = '${F.relRow}') as s`);
      assertEq(r.rows[0].n, 1, 'cas_ddk_norms: any authenticated user can SELECT');
      assertEq(r.rows[0].l, 1, 'legal_documents: any authenticated user can SELECT');
      assertEq(r.rows[0].s, 1, 'substrate_relations: any authenticated user can SELECT');
    });
    await expectRls('authenticated', owner,
      `insert into public.cas_ddk_norms
         (task, age_months_min, age_months_max, mean_syl_per_sec,
          sd_syl_per_sec, source_citation)
       values ('smr', 36, 48, 3.1, 0.5, 'write probe')`,
      'cas_ddk_norms: authenticated write rejected 42501');
    await expectRls('authenticated', owner,
      `insert into public.legal_documents (doc_type, version, content, effective_from)
       values ('probe', 'v0', 'x', now())`,
      'legal_documents: authenticated write rejected 42501');
    await expectRls('authenticated', owner,
      `insert into public.substrate_relations
         (source_tag, target_tag, strength, direction, reasoning)
       values ('x', 'y', 'weak', 'mutual', 'probe')`,
      'substrate_relations: authenticated write rejected 42501');
    await asCtx('anon', null, async () => {
      const r = await q(
        `select (select count(*) from public.cas_ddk_norms where id = '${F.normRow}') as n,
                (select count(*) from public.legal_documents where id = '${F.legalRow}') as l,
                (select count(*) from public.substrate_relations where id = '${F.relRow}') as s`);
      assertEq(Number(r.rows[0].n) + Number(r.rows[0].l) + Number(r.rows[0].s), 0,
        'reference tables: anon sees 0 rows on all three');
    });
  } finally {
    // ── Teardown + zero-residue audit ───────────────────────────────
    try {
      await removeFixtures();
      const residue = await fixtureResidueCount();
      assertEq(residue, 0, 'teardown: zero fixture residue across all tables');
    } catch (e) {
      notOk('teardown: fixture cleanup failed', e.message);
    }
    await db.end();
  }

  console.log(`1..${testNo}`);
  if (failures > 0) {
    console.error(`\nFAILED: ${failures} of ${testNo} assertions. ` +
      'The RLS surface has regressed — do not ship.');
    process.exit(1);
  }
  console.log(`\nAll ${testNo} RLS assertions passed.`);
}

main().catch((e) => {
  console.error('\nHARNESS ERROR (not a clean assertion failure):');
  console.error(e.stack || e.message);
  process.exit(1);
});
