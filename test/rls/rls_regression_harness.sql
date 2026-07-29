-- test/rls/rls_regression_harness.sql
--
-- RLS regression harness — THE AUTHORITATIVE EDITION. This file is the
-- source of truth for the RLS assertion surface; any other runner
-- (including the unvalidated Node CI stub alongside it) must be
-- re-derived from this file before use.
--
-- Runs as a single SQL batch through any owner-level Postgres channel
-- (Supabase management-API SQL, supabase db execute, or psql as
-- postgres). One transaction end to end: fixtures are created, every
-- assertion runs, teardown deletes everything, and only then does the
-- batch commit — a crash rolls the whole run back, so no fixture can
-- ever persist. Expected-rejection probes run inside PL/pgSQL
-- sub-blocks and are ALWAYS rolled back via a sentinel errcode
-- (PT999), even when a policy regression lets the write through.
--
-- VALIDATED 2026-07-28 (first green run, via the Supabase management
-- API connector):
--   1..55  ALL 55 RLS ASSERTIONS PASSED
-- Mutation-validated same day: dropping clinician_reads_own_generations
-- failed EXACTLY ONE assertion ("not ok 45 - generations: owner reads
-- her own row [got: 0]"), all 54 others stayed green — assertions are
-- independent; policy restored, re-run green (55/55).
--
-- Guards: (1) the run targets the sandbox project by construction of
-- the channel; (2) in-database sentinel — aborts unless the
-- ped_language_assessment_tables migration exists (never applied to
-- prod); (3) pg_try_advisory_xact_lock forbids concurrent runs.
--
-- Coverage: catalog-diff against public.rls_allowlist (the versioned
-- in-database allowlist, migration 20260728: rls_allowlist_table —
-- the ONLY source; add/remove rows by migration in the same commit
-- that creates or seals a table);
-- ped_language_, feeding_, ssd_, cas_ (assessment trio +
-- cas_session_progress + cas_progress_brief SELECT-only wall + the
-- SECURITY DEFINER dirty-trigger writing through it), generations
-- (service-role-only writes, even the owner rejected), and the three
-- read-only reference tables. Output: TAP-style lines from the final
-- SELECT; any "not ok" line means the RLS surface regressed.

create temp table _rls_out(seq serial, line text) on commit drop;
do $$
declare
  v_owner uuid;
  v_r jsonb := '[]'::jsonb;
  v_probe text; v_n bigint; v_n2 bigint; v_n3 bigint; v_t text; v_b boolean;
  v_uncovered text; v_stale text; v_fail int := 0; v_tot int := 0; e jsonb;
  allow text[];
  c_client constant uuid := 'a11ce5ed-0000-4000-8000-000000000001';
  c_ltg    constant uuid := 'a11ce5ed-0000-4000-8000-000000000002';
  c_stg    constant uuid := 'a11ce5ed-0000-4000-8000-000000000003';
  c_stg2   constant uuid := 'a11ce5ed-0000-4000-8000-000000000004';
  c_sess   constant bigint := 999999901;
  c_pl     constant uuid := 'a11ce5ed-0001-4000-8000-000000000001';
  c_plrow  constant uuid := 'a11ce5ed-0001-4000-8000-000000000002';
  c_fd     constant uuid := 'a11ce5ed-0002-4000-8000-000000000001';
  c_fdband constant uuid := 'a11ce5ed-0002-4000-8000-000000000002';
  c_fdbeh  constant uuid := 'a11ce5ed-0002-4000-8000-000000000003';
  c_ssd    constant uuid := 'a11ce5ed-0003-4000-8000-000000000001';
  c_ts     constant uuid := 'a11ce5ed-0003-4000-8000-000000000002';
  c_pp     constant uuid := 'a11ce5ed-0003-4000-8000-000000000003';
  c_cw     constant uuid := 'a11ce5ed-0003-4000-8000-000000000004';
  c_le     constant uuid := 'a11ce5ed-0003-4000-8000-000000000005';
  c_ww     constant uuid := 'a11ce5ed-0003-4000-8000-000000000006';
  c_cas    constant uuid := 'a11ce5ed-0004-4000-8000-000000000001';
  c_grad   constant uuid := 'a11ce5ed-0004-4000-8000-000000000002';
  c_ddk    constant uuid := 'a11ce5ed-0004-4000-8000-000000000003';
  c_prog   constant uuid := 'a11ce5ed-0004-4000-8000-000000000004';
  c_gen    constant uuid := 'a11ce5ed-0005-4000-8000-000000000001';
  c_norm   constant uuid := 'a11ce5ed-0006-4000-8000-000000000001';
  c_legal  constant uuid := 'a11ce5ed-0006-4000-8000-000000000002';
  c_rel    constant uuid := 'a11ce5ed-0006-4000-8000-000000000003';
  c_intr   constant text := '00000000-0000-4000-8000-0000000000ff';
begin
  -- Guards
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where name = 'ped_language_assessment_tables') then
    raise exception 'GUARD: sandbox sentinel migration missing — refusing to run';
  end if;
  if not pg_try_advisory_xact_lock(hashtext('cue_rls_harness')) then
    raise exception 'GUARD: another harness run holds the advisory lock';
  end if;
  select id into v_owner from auth.users order by created_at asc limit 1;
  if v_owner is null then raise exception 'GUARD: no auth.users identity'; end if;

  -- Catalog-diff invariant, against the single-source in-database
  -- allowlist (public.rls_allowlist).
  select coalesce(array_agg(table_name), '{}'::text[]) into allow
    from public.rls_allowlist;
  select string_agg(tablename, ', ') into v_uncovered from pg_tables
   where schemaname='public' and not rowsecurity and tablename <> all (allow);
  v_r := v_r || jsonb_build_object('t', case when v_uncovered is null then 'ok' else 'not ok' end,
    'name', 'catalog diff: every public table is sealed or allowlisted', 'got', coalesce(v_uncovered, ''));
  select string_agg(x, ', ') into v_stale from (
    select tablename as x from pg_tables where schemaname='public' and rowsecurity and tablename = any(allow)
    union all
    select a from unnest(allow) a where a not in (select tablename from pg_tables where schemaname='public')) s;
  if v_stale is not null then
    v_r := v_r || jsonb_build_object('t','info','name','warning: stale allowlist entries','got',v_stale);
  end if;

  -- Fixture spine
  insert into public.clients (id, clinician_id, name, age)
  values (c_client, v_owner, 'RLS HARNESS FIXTURE — do not touch (auto-deleted)', 3);
  insert into public.long_term_goals (id, client_id, user_id, domain, goal_text)
  values (c_ltg, c_client, v_owner, 'rls-harness', 'RLS harness fixture LTG');
  insert into public.short_term_goals (id, long_term_goal_id, client_id, user_id, specific, measurable)
  values (c_stg, c_ltg, c_client, v_owner, 'RLS harness fixture STG', 'n/a');
  insert into public.short_term_goals (id, long_term_goal_id, client_id, user_id, specific, measurable)
  values (c_stg2, c_ltg, c_client, v_owner, 'RLS harness fixture STG 2 (no brief)', 'n/a');
  insert into public.sessions (id, client_id, user_id) values (c_sess, c_client, v_owner);

  -- ped_language_
  perform set_config('role','authenticated',true),
          set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
  insert into public.ped_language_assessments (id, client_id, clinician_id, band_key, derived_age_months, age_source)
  values (c_pl, c_client, v_owner, '2_to_3y', 30, 'dob');
  insert into public.ped_language_milestones (id, ped_language_assessment_id, section, milestone_order, milestone_text, norm_reference, library_version)
  values (c_plrow, c_pl, 'speech', 999, 'RLS harness probe', 'RLS harness', '0.0.0-harness');
  update public.ped_language_assessments set capture_notes='harness-owner' where id=c_pl;
  select count(*), (select count(*) from public.ped_language_milestones where id=c_plrow),
         (select capture_notes from public.ped_language_assessments where id=c_pl)
    into v_n, v_n2, v_t from public.ped_language_assessments where id=c_pl;
  v_r := v_r || jsonb_build_object('t', case when v_n=1 then 'ok' else 'not ok' end, 'name','ped_language: owner sees her parent row','got',v_n::text);
  v_r := v_r || jsonb_build_object('t', case when v_n2=1 then 'ok' else 'not ok' end, 'name','ped_language: owner sees her milestone row','got',v_n2::text);
  v_r := v_r || jsonb_build_object('t', case when v_t='harness-owner' then 'ok' else 'not ok' end, 'name','ped_language: owner update reads back','got',v_t);
  perform set_config('request.jwt.claims', json_build_object('sub', c_intr)::text, true);
  with upd as (update public.ped_language_assessments set capture_notes='intruder' where id=c_pl returning 1)
  select (select count(*) from public.ped_language_assessments where id=c_pl),
         (select count(*) from public.ped_language_milestones where id=c_plrow),
         (select count(*) from upd) into v_n, v_n2, v_n3;
  v_r := v_r || jsonb_build_object('t', case when v_n=0 then 'ok' else 'not ok' end, 'name','ped_language: intruder sees 0 parent rows','got',v_n::text);
  v_r := v_r || jsonb_build_object('t', case when v_n2=0 then 'ok' else 'not ok' end, 'name','ped_language: intruder sees 0 milestone rows','got',v_n2::text);
  v_r := v_r || jsonb_build_object('t', case when v_n3=0 then 'ok' else 'not ok' end, 'name','ped_language: intruder update touches 0 rows','got',v_n3::text);
  begin
    insert into public.ped_language_assessments (client_id, band_key, derived_age_months, age_source) values (c_client, '2_to_3y', 30, 'dob');
    v_probe := 'SUCCEEDED'; raise exception using errcode='PT999';
  exception when sqlstate 'PT999' then null; when others then v_probe := sqlstate; end;
  v_r := v_r || jsonb_build_object('t', case when v_probe='42501' then 'ok' else 'not ok' end, 'name','ped_language: intruder insert rejected 42501','got',v_probe);
  perform set_config('role','anon',true), set_config('request.jwt.claims','{}',true);
  select (select count(*) from public.ped_language_assessments), (select count(*) from public.ped_language_milestones) into v_n, v_n2;
  v_r := v_r || jsonb_build_object('t', case when v_n=0 then 'ok' else 'not ok' end, 'name','ped_language: anon sees 0 parent rows','got',v_n::text);
  v_r := v_r || jsonb_build_object('t', case when v_n2=0 then 'ok' else 'not ok' end, 'name','ped_language: anon sees 0 milestone rows','got',v_n2::text);
  begin
    insert into public.ped_language_assessments (client_id, band_key, derived_age_months, age_source) values (c_client, '2_to_3y', 30, 'dob');
    v_probe := 'SUCCEEDED'; raise exception using errcode='PT999';
  exception when sqlstate 'PT999' then null; when others then v_probe := sqlstate; end;
  v_r := v_r || jsonb_build_object('t', case when v_probe='42501' then 'ok' else 'not ok' end, 'name','ped_language: anon parent insert rejected 42501','got',v_probe);
  begin
    insert into public.ped_language_milestones (ped_language_assessment_id, section, milestone_order, milestone_text, norm_reference, library_version) values (c_pl, 'speech', 998, 'anon probe', 'x', 'x');
    v_probe := 'SUCCEEDED'; raise exception using errcode='PT999';
  exception when sqlstate 'PT999' then null; when others then v_probe := sqlstate; end;
  v_r := v_r || jsonb_build_object('t', case when v_probe='42501' then 'ok' else 'not ok' end, 'name','ped_language: anon child insert rejected 42501','got',v_probe);

  -- feeding_
  perform set_config('role','authenticated',true),
          set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
  insert into public.feeding_assessments (id, client_id, clinician_id, age_months) values (c_fd, c_client, v_owner, 30);
  insert into public.feeding_ladder_bands (id, feeding_assessment_id, band_key, band_order, band_label, age_min_months, expected_texture, expected_self_feeding, expected_oral_motor, red_flag_prompt, off_ramp_band)
  values (c_fdband, c_fd, 'rls_harness', 999, 'RLS harness band', 0, 'probe','probe','probe','probe', false);
  insert into public.feeding_behaviors (id, feeding_assessment_id, behavior_label, airway_sign) values (c_fdbeh, c_fd, 'RLS harness behavior', false);
  update public.feeding_assessments set capture_notes='harness-owner' where id=c_fd;
  select (select count(*) from public.feeding_assessments where id=c_fd),
         (select count(*) from public.feeding_ladder_bands where id=c_fdband) + (select count(*) from public.feeding_behaviors where id=c_fdbeh),
         (select capture_notes from public.feeding_assessments where id=c_fd) into v_n, v_n2, v_t;
  v_r := v_r || jsonb_build_object('t', case when v_n=1 then 'ok' else 'not ok' end, 'name','feeding: owner sees her parent row','got',v_n::text);
  v_r := v_r || jsonb_build_object('t', case when v_n2=2 then 'ok' else 'not ok' end, 'name','feeding: owner sees both child rows','got',v_n2::text);
  v_r := v_r || jsonb_build_object('t', case when v_t='harness-owner' then 'ok' else 'not ok' end, 'name','feeding: owner update reads back','got',v_t);
  perform set_config('request.jwt.claims', json_build_object('sub', c_intr)::text, true);
  with upd as (update public.feeding_assessments set capture_notes='intruder' where id=c_fd returning 1)
  select (select count(*) from public.feeding_assessments where id=c_fd),
         (select count(*) from public.feeding_ladder_bands where id=c_fdband) + (select count(*) from public.feeding_behaviors where id=c_fdbeh),
         (select count(*) from upd) into v_n, v_n2, v_n3;
  v_r := v_r || jsonb_build_object('t', case when v_n=0 and v_n2=0 then 'ok' else 'not ok' end, 'name','feeding: intruder sees 0 rows','got',v_n::text||'/'||v_n2::text);
  v_r := v_r || jsonb_build_object('t', case when v_n3=0 then 'ok' else 'not ok' end, 'name','feeding: intruder update touches 0 rows','got',v_n3::text);
  begin
    insert into public.feeding_assessments (client_id, age_months) values (c_client, 24);
    v_probe := 'SUCCEEDED'; raise exception using errcode='PT999';
  exception when sqlstate 'PT999' then null; when others then v_probe := sqlstate; end;
  v_r := v_r || jsonb_build_object('t', case when v_probe='42501' then 'ok' else 'not ok' end, 'name','feeding: intruder insert rejected 42501','got',v_probe);
  perform set_config('role','anon',true), set_config('request.jwt.claims','{}',true);
  select count(*) into v_n from public.feeding_assessments where id=c_fd;
  v_r := v_r || jsonb_build_object('t', case when v_n=0 then 'ok' else 'not ok' end, 'name','feeding: anon sees 0 rows','got',v_n::text);
  begin
    insert into public.feeding_assessments (client_id, age_months) values (c_client, 24);
    v_probe := 'SUCCEEDED'; raise exception using errcode='PT999';
  exception when sqlstate 'PT999' then null; when others then v_probe := sqlstate; end;
  v_r := v_r || jsonb_build_object('t', case when v_probe='42501' then 'ok' else 'not ok' end, 'name','feeding: anon parent insert rejected 42501','got',v_probe);
  begin
    insert into public.feeding_behaviors (feeding_assessment_id, behavior_label, airway_sign) values (c_fd, 'anon probe', false);
    v_probe := 'SUCCEEDED'; raise exception using errcode='PT999';
  exception when sqlstate 'PT999' then null; when others then v_probe := sqlstate; end;
  v_r := v_r || jsonb_build_object('t', case when v_probe='42501' then 'ok' else 'not ok' end, 'name','feeding: anon child insert rejected 42501','got',v_probe);

  -- ssd_
  perform set_config('role','authenticated',true),
          set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
  insert into public.ssd_assessments (id, client_id, clinician_id, age_months) values (c_ssd, c_client, v_owner, 48);
  insert into public.ssd_target_sounds (id, ssd_assessment_id, target_phoneme) values (c_ts, c_ssd, '/harness/');
  insert into public.ssd_phonological_processes (id, ssd_assessment_id, process_name) values (c_pp, c_ssd, 'rls_harness');
  insert into public.ssd_consistency_words (id, ssd_assessment_id, word, word_order) values (c_cw, c_ssd, 'rls-harness', 999);
  insert into public.ssd_length_effect (id, ssd_assessment_id, level_label, level_order) values (c_le, c_ssd, 'rls-harness', 999);
  insert into public.ssd_whole_word (id, ssd_assessment_id, word, word_order) values (c_ww, c_ssd, 'rls-harness', 999);
  update public.ssd_assessments set capture_notes='harness-owner' where id=c_ssd;
  select (select count(*) from public.ssd_assessments where id=c_ssd),
         (select count(*) from public.ssd_target_sounds where id=c_ts)+(select count(*) from public.ssd_phonological_processes where id=c_pp)
         +(select count(*) from public.ssd_consistency_words where id=c_cw)+(select count(*) from public.ssd_length_effect where id=c_le)
         +(select count(*) from public.ssd_whole_word where id=c_ww),
         (select capture_notes from public.ssd_assessments where id=c_ssd) into v_n, v_n2, v_t;
  v_r := v_r || jsonb_build_object('t', case when v_n=1 then 'ok' else 'not ok' end, 'name','ssd: owner sees her parent row','got',v_n::text);
  v_r := v_r || jsonb_build_object('t', case when v_n2=5 then 'ok' else 'not ok' end, 'name','ssd: owner sees all five child rows','got',v_n2::text);
  v_r := v_r || jsonb_build_object('t', case when v_t='harness-owner' then 'ok' else 'not ok' end, 'name','ssd: owner update reads back','got',v_t);
  perform set_config('request.jwt.claims', json_build_object('sub', c_intr)::text, true);
  with upd as (update public.ssd_assessments set capture_notes='intruder' where id=c_ssd returning 1)
  select (select count(*) from public.ssd_assessments where id=c_ssd),
         (select count(*) from public.ssd_target_sounds where ssd_assessment_id=c_ssd)+(select count(*) from public.ssd_phonological_processes where ssd_assessment_id=c_ssd)
         +(select count(*) from public.ssd_consistency_words where ssd_assessment_id=c_ssd)+(select count(*) from public.ssd_length_effect where ssd_assessment_id=c_ssd)
         +(select count(*) from public.ssd_whole_word where ssd_assessment_id=c_ssd),
         (select count(*) from upd) into v_n, v_n2, v_n3;
  v_r := v_r || jsonb_build_object('t', case when v_n=0 and v_n2=0 then 'ok' else 'not ok' end, 'name','ssd: intruder sees 0 rows','got',v_n::text||'/'||v_n2::text);
  v_r := v_r || jsonb_build_object('t', case when v_n3=0 then 'ok' else 'not ok' end, 'name','ssd: intruder update touches 0 rows','got',v_n3::text);
  begin
    insert into public.ssd_assessments (client_id, age_months) values (c_client, 36);
    v_probe := 'SUCCEEDED'; raise exception using errcode='PT999';
  exception when sqlstate 'PT999' then null; when others then v_probe := sqlstate; end;
  v_r := v_r || jsonb_build_object('t', case when v_probe='42501' then 'ok' else 'not ok' end, 'name','ssd: intruder insert rejected 42501','got',v_probe);
  perform set_config('role','anon',true), set_config('request.jwt.claims','{}',true);
  select count(*) into v_n from public.ssd_assessments where id=c_ssd;
  v_r := v_r || jsonb_build_object('t', case when v_n=0 then 'ok' else 'not ok' end, 'name','ssd: anon sees 0 rows','got',v_n::text);
  begin
    insert into public.ssd_assessments (client_id, age_months) values (c_client, 36);
    v_probe := 'SUCCEEDED'; raise exception using errcode='PT999';
  exception when sqlstate 'PT999' then null; when others then v_probe := sqlstate; end;
  v_r := v_r || jsonb_build_object('t', case when v_probe='42501' then 'ok' else 'not ok' end, 'name','ssd: anon parent insert rejected 42501','got',v_probe);
  begin
    insert into public.ssd_target_sounds (ssd_assessment_id, target_phoneme) values (c_ssd, '/anon/');
    v_probe := 'SUCCEEDED'; raise exception using errcode='PT999';
  exception when sqlstate 'PT999' then null; when others then v_probe := sqlstate; end;
  v_r := v_r || jsonb_build_object('t', case when v_probe='42501' then 'ok' else 'not ok' end, 'name','ssd: anon child insert rejected 42501','got',v_probe);

  -- cas_
  perform set_config('role','authenticated',true),
          set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
  insert into public.cas_assessments (id, client_id, clinician_id, age_months) values (c_cas, c_client, v_owner, 54);
  insert into public.cas_length_gradient (id, cas_assessment_id, level_label, level_order) values (c_grad, c_cas, 'rls-harness', 999);
  insert into public.cas_ddk (id, cas_assessment_id, task) values (c_ddk, c_cas, 'pa');
  select (select count(*) from public.cas_assessments where id=c_cas),
         (select count(*) from public.cas_length_gradient where id=c_grad)+(select count(*) from public.cas_ddk where id=c_ddk) into v_n, v_n2;
  v_r := v_r || jsonb_build_object('t', case when v_n=1 then 'ok' else 'not ok' end, 'name','cas: owner sees her assessment row','got',v_n::text);
  v_r := v_r || jsonb_build_object('t', case when v_n2=2 then 'ok' else 'not ok' end, 'name','cas: owner sees her gradient + ddk rows','got',v_n2::text);
  insert into public.cas_session_progress (id, stg_id, session_id, client_id, level_label, level_order)
  values (c_prog, c_stg, c_sess, c_client, 'rls-harness', 999);
  with dw as (update public.cas_progress_brief set is_dirty=false where stg_id=c_stg returning 1)
  select (select count(*) from public.cas_progress_brief where stg_id=c_stg),
         (select is_dirty from public.cas_progress_brief where stg_id=c_stg),
         (select count(*) from dw) into v_n, v_b, v_n3;
  v_r := v_r || jsonb_build_object('t', case when v_n=1 then 'ok' else 'not ok' end, 'name','cas_progress_brief: DEFINER trigger wrote the brief row (owner can SELECT it)','got',v_n::text);
  v_r := v_r || jsonb_build_object('t', case when v_b then 'ok' else 'not ok' end, 'name','cas_progress_brief: trigger set is_dirty=true through the SELECT-only wall','got',v_b::text);
  v_r := v_r || jsonb_build_object('t', case when v_n3=0 then 'ok' else 'not ok' end, 'name','cas_progress_brief: owner direct UPDATE touches 0 rows (no write policy)','got',v_n3::text);
  begin
    insert into public.cas_progress_brief (stg_id, client_id, is_dirty) values (c_stg2, c_client, true);
    v_probe := 'SUCCEEDED'; raise exception using errcode='PT999';
  exception when sqlstate 'PT999' then null; when others then v_probe := sqlstate; end;
  v_r := v_r || jsonb_build_object('t', case when v_probe='42501' then 'ok' else 'not ok' end, 'name','cas_progress_brief: owner direct INSERT rejected 42501','got',v_probe);
  perform set_config('request.jwt.claims', json_build_object('sub', c_intr)::text, true);
  begin
    insert into public.cas_assessments (client_id, age_months) values (c_client, 40);
    v_probe := 'SUCCEEDED'; raise exception using errcode='PT999';
  exception when sqlstate 'PT999' then null; when others then v_probe := sqlstate; end;
  v_r := v_r || jsonb_build_object('t', case when v_probe='42501' then 'ok' else 'not ok' end, 'name','cas: intruder insert rejected 42501','got',v_probe);
  select (select count(*) from public.cas_assessments where id=c_cas),
         (select count(*) from public.cas_session_progress where id=c_prog),
         (select count(*) from public.cas_progress_brief where stg_id=c_stg) into v_n, v_n2, v_n3;
  v_r := v_r || jsonb_build_object('t', case when v_n=0 then 'ok' else 'not ok' end, 'name','cas: intruder sees 0 assessment rows','got',v_n::text);
  v_r := v_r || jsonb_build_object('t', case when v_n2=0 then 'ok' else 'not ok' end, 'name','cas_session_progress: intruder sees 0 rows','got',v_n2::text);
  v_r := v_r || jsonb_build_object('t', case when v_n3=0 then 'ok' else 'not ok' end, 'name','cas_progress_brief: intruder sees 0 rows','got',v_n3::text);
  perform set_config('role','anon',true), set_config('request.jwt.claims','{}',true);
  select (select count(*) from public.cas_session_progress), (select count(*) from public.cas_progress_brief) into v_n, v_n2;
  v_r := v_r || jsonb_build_object('t', case when v_n=0 then 'ok' else 'not ok' end, 'name','cas_session_progress: anon sees 0 rows','got',v_n::text);
  v_r := v_r || jsonb_build_object('t', case when v_n2=0 then 'ok' else 'not ok' end, 'name','cas_progress_brief: anon sees 0 rows','got',v_n2::text);
  begin
    insert into public.cas_length_gradient (cas_assessment_id, level_label, level_order) values (c_cas, 'anon', 998);
    v_probe := 'SUCCEEDED'; raise exception using errcode='PT999';
  exception when sqlstate 'PT999' then null; when others then v_probe := sqlstate; end;
  v_r := v_r || jsonb_build_object('t', case when v_probe='42501' then 'ok' else 'not ok' end, 'name','cas: anon child insert rejected 42501','got',v_probe);

  -- generations
  perform set_config('role','service_role',true), set_config('request.jwt.claims','{}',true);
  insert into public.generations (id, clinician_id, endpoint, status) values (c_gen, v_owner, 'rls-harness', 'success');
  v_r := v_r || jsonb_build_object('t','ok','name','generations: service_role insert succeeds (proxy write path)','got','1');
  perform set_config('role','authenticated',true),
          set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
  select count(*) into v_n from public.generations where id=c_gen;
  v_r := v_r || jsonb_build_object('t', case when v_n=1 then 'ok' else 'not ok' end, 'name','generations: owner reads her own row','got',v_n::text);
  begin
    insert into public.generations (clinician_id, endpoint, status) values (v_owner, 'owner-probe', 'success');
    v_probe := 'SUCCEEDED'; raise exception using errcode='PT999';
  exception when sqlstate 'PT999' then null; when others then v_probe := sqlstate; end;
  v_r := v_r || jsonb_build_object('t', case when v_probe='42501' then 'ok' else 'not ok' end, 'name','generations: EVEN THE OWNER insert rejected 42501 (service-role only)','got',v_probe);
  perform set_config('request.jwt.claims', json_build_object('sub', c_intr)::text, true);
  select count(*) into v_n from public.generations where id=c_gen;
  v_r := v_r || jsonb_build_object('t', case when v_n=0 then 'ok' else 'not ok' end, 'name','generations: intruder reads 0 rows','got',v_n::text);
  perform set_config('role','anon',true), set_config('request.jwt.claims','{}',true);
  select count(*) into v_n from public.generations;
  v_r := v_r || jsonb_build_object('t', case when v_n=0 then 'ok' else 'not ok' end, 'name','generations: anon reads 0 rows','got',v_n::text);
  begin
    insert into public.generations (clinician_id, endpoint, status) values (v_owner, 'anon-probe', 'success');
    v_probe := 'SUCCEEDED'; raise exception using errcode='PT999';
  exception when sqlstate 'PT999' then null; when others then v_probe := sqlstate; end;
  v_r := v_r || jsonb_build_object('t', case when v_probe='42501' then 'ok' else 'not ok' end, 'name','generations: anon insert rejected 42501','got',v_probe);

  -- Reference tables
  perform set_config('role','none',true), set_config('request.jwt.claims','',true);
  insert into public.cas_ddk_norms (id, task, age_months_min, age_months_max, mean_syl_per_sec, sd_syl_per_sec, source_citation)
  values (c_norm, 'amr', 996, 999, 4.2, 0.6, 'RLS harness probe — not a real norm');
  insert into public.legal_documents (id, doc_type, version, content, effective_from)
  values (c_legal, 'rls_harness', 'v0', 'RLS harness probe', now());
  insert into public.substrate_relations (id, source_tag, target_tag, strength, direction, reasoning)
  values (c_rel, 'rls-harness-a', 'rls-harness-b', 'weak', 'mutual', 'harness probe');
  perform set_config('role','authenticated',true),
          set_config('request.jwt.claims', json_build_object('sub', c_intr)::text, true);
  select (select count(*) from public.cas_ddk_norms where id=c_norm)
       + (select count(*) from public.legal_documents where id=c_legal)
       + (select count(*) from public.substrate_relations where id=c_rel) into v_n;
  v_r := v_r || jsonb_build_object('t', case when v_n=3 then 'ok' else 'not ok' end, 'name','reference tables: any authenticated user can SELECT all three','got',v_n::text);
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
  begin
    insert into public.cas_ddk_norms (task, age_months_min, age_months_max, mean_syl_per_sec, sd_syl_per_sec, source_citation)
    values ('smr', 36, 48, 3.1, 0.5, 'write probe');
    v_probe := 'SUCCEEDED'; raise exception using errcode='PT999';
  exception when sqlstate 'PT999' then null; when others then v_probe := sqlstate; end;
  v_r := v_r || jsonb_build_object('t', case when v_probe='42501' then 'ok' else 'not ok' end, 'name','cas_ddk_norms: authenticated write rejected 42501','got',v_probe);
  begin
    insert into public.legal_documents (doc_type, version, content, effective_from) values ('probe', 'v0', 'x', now());
    v_probe := 'SUCCEEDED'; raise exception using errcode='PT999';
  exception when sqlstate 'PT999' then null; when others then v_probe := sqlstate; end;
  v_r := v_r || jsonb_build_object('t', case when v_probe='42501' then 'ok' else 'not ok' end, 'name','legal_documents: authenticated write rejected 42501','got',v_probe);
  begin
    insert into public.substrate_relations (source_tag, target_tag, strength, direction, reasoning) values ('x','y','weak','mutual','probe');
    v_probe := 'SUCCEEDED'; raise exception using errcode='PT999';
  exception when sqlstate 'PT999' then null; when others then v_probe := sqlstate; end;
  v_r := v_r || jsonb_build_object('t', case when v_probe='42501' then 'ok' else 'not ok' end, 'name','substrate_relations: authenticated write rejected 42501','got',v_probe);
  perform set_config('role','anon',true), set_config('request.jwt.claims','{}',true);
  select (select count(*) from public.cas_ddk_norms where id=c_norm)
       + (select count(*) from public.legal_documents where id=c_legal)
       + (select count(*) from public.substrate_relations where id=c_rel) into v_n;
  v_r := v_r || jsonb_build_object('t', case when v_n=0 then 'ok' else 'not ok' end, 'name','reference tables: anon sees 0 rows on all three','got',v_n::text);

  -- Teardown + zero-residue audit
  perform set_config('role','none',true), set_config('request.jwt.claims','',true);
  delete from public.cas_session_progress where id=c_prog;
  delete from public.cas_progress_brief where stg_id in (c_stg, c_stg2);
  delete from public.ped_language_assessments where id=c_pl;
  delete from public.feeding_assessments where id=c_fd;
  delete from public.ssd_assessments where id=c_ssd;
  delete from public.cas_assessments where id=c_cas;
  delete from public.generations where id=c_gen;
  delete from public.cas_ddk_norms where id=c_norm;
  delete from public.legal_documents where id=c_legal;
  delete from public.substrate_relations where id=c_rel;
  delete from public.short_term_goals where id in (c_stg, c_stg2);
  delete from public.long_term_goals where id=c_ltg;
  delete from public.sessions where id=c_sess;
  delete from public.clients where id=c_client;
  select (select count(*) from public.clients where id=c_client)
       + (select count(*) from public.sessions where id=c_sess)
       + (select count(*) from public.short_term_goals where id in (c_stg,c_stg2))
       + (select count(*) from public.long_term_goals where id=c_ltg)
       + (select count(*) from public.ped_language_assessments where id=c_pl)
       + (select count(*) from public.ped_language_milestones where id=c_plrow)
       + (select count(*) from public.feeding_assessments where id=c_fd)
       + (select count(*) from public.ssd_assessments where id=c_ssd)
       + (select count(*) from public.cas_assessments where id=c_cas)
       + (select count(*) from public.cas_session_progress where id=c_prog)
       + (select count(*) from public.cas_progress_brief where stg_id in (c_stg,c_stg2))
       + (select count(*) from public.generations where id=c_gen)
       + (select count(*) from public.cas_ddk_norms where id=c_norm)
       + (select count(*) from public.legal_documents where id=c_legal)
       + (select count(*) from public.substrate_relations where id=c_rel) into v_n;
  v_r := v_r || jsonb_build_object('t', case when v_n=0 then 'ok' else 'not ok' end, 'name','teardown: zero fixture residue across all tables','got',v_n::text);

  -- Emit TAP-style lines
  for e in select * from jsonb_array_elements(v_r) loop
    v_tot := v_tot + 1;
    if e->>'t' = 'not ok' then v_fail := v_fail + 1; end if;
    insert into _rls_out(line) values (
      case e->>'t' when 'info' then '# ' else (e->>'t') || ' ' || v_tot::text || ' - ' end
      || (e->>'name')
      || case when e->>'t' = 'not ok' or e->>'t' = 'info' then ' [got: ' || coalesce(e->>'got','') || ']' else '' end);
  end loop;
  insert into _rls_out(line) values ('1..' || v_tot::text);
  insert into _rls_out(line) values (
    case when v_fail = 0 then 'ALL ' || v_tot::text || ' RLS ASSERTIONS PASSED'
         else 'FAILED: ' || v_fail::text || ' of ' || v_tot::text || ' — RLS has regressed, do not ship' end);
end $$;
select jsonb_agg(line order by seq) as tap_output from _rls_out;
