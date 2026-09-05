-- test/sql/ped_language_atomic_completion_proof.sql
--
-- Proof for public.complete_ped_language_section (v2, migration
-- 20260906090000). Four claims, each asserted against the DEPLOYED function:
--
--   1. SET ONCE   — a repair of an already-declared section keeps the ORIGINAL
--                   stamp (does not move it to now()), fills the rows, and
--                   returns that original stamp.
--   2. RETURNS    — a fresh declaration stamps now() and RETURNS the very value
--                   it wrote (server clock, same transaction).
--   3. COMPLETE   — the fill must land on EVERY requested id: an id that is not
--                   a row of this assessment raises SQLSTATE 'CU002' and NOTHING
--                   changes (no row filled, no stamp), so a section is never
--                   stamped done over rows still NULL.
--   4. ATOMIC     — a failure BETWEEN the two writes (a temporary BEFORE UPDATE
--                   trigger on the parent raising SQLSTATE 'CU001', i.e. the
--                   stamp write fails after the rows write) leaves the database
--                   UNCHANGED: both writes land or neither does.
--
-- Self-contained and non-destructive: seeds throwaway rows inside a
-- transaction and ROLLS BACK, leaving zero residue. Each handler catches ONLY
-- the SQLSTATE it expects and re-raises anything else (e.g. undefined_function,
-- or a v1 void function failing the SELECT INTO), so a missing/old deploy fails
-- loudly — never a false pass.
--
-- Run:  psql "$CUE_SANDBOX_DB_URL" -v ON_ERROR_STOP=1 \
--         -f test/sql/ped_language_atomic_completion_proof.sql
-- PASS: NOTICE  PROOF PASS: set_once=t returns=t complete=t atomic=t
-- FAIL: raises  PROOF FAIL: ... and, with ON_ERROR_STOP, exits non-zero.

begin;

do $proof$
declare
  v_client uuid;
  -- (1) repair case: pre-stamped section
  v_a   uuid := gen_random_uuid();
  v_a1  uuid := gen_random_uuid();
  v_a2  uuid := gen_random_uuid();
  v_orig timestamptz := '2026-08-01T00:00:00Z';
  v_ret_repair timestamptz;
  v_col_repair timestamptz;
  v_a2_status  text;
  -- (2) fresh case: NULL stamp
  v_b   uuid := gen_random_uuid();
  v_b1  uuid := gen_random_uuid();
  v_ret_fresh timestamptz;
  v_col_fresh timestamptz;
  -- (3) complete-fill case: one real id + one foreign id
  v_d   uuid := gen_random_uuid();
  v_d1  uuid := gen_random_uuid();
  v_d1_status text;
  v_col_d     timestamptz;
  v_raised_cu002 boolean := false;
  -- (4) atomic case
  v_c   uuid := gen_random_uuid();
  v_c1  uuid := gen_random_uuid();
  v_c2  uuid := gen_random_uuid();
  v_absent_c int;
  -- verdicts
  v_set_once boolean;
  v_returns  boolean;
  v_complete boolean;
  v_atomic   boolean;
begin
  -- Any existing client satisfies the FK; the whole transaction rolls back.
  select id into v_client from public.clients limit 1;
  if v_client is null then
    raise exception 'PROOF cannot run: no clients row to satisfy the FK';
  end if;

  -- ── (1) SET ONCE: a repair keeps the original stamp and returns it ────────
  insert into public.ped_language_assessments
    (id, client_id, band_key, derived_age_months, age_source, speech_completed_at)
  values (v_a, v_client, '2_to_3y', 30, 'dob', v_orig);
  insert into public.ped_language_milestones
    (id, ped_language_assessment_id, section, milestone_order, milestone_text, status,
     norm_reference, library_version)
  values
    (v_a1, v_a, 'speech', 1, 'proof a1', 'present', 'proof ref', '1.0.0'),
    (v_a2, v_a, 'speech', 2, 'proof a2', null,      'proof ref', '1.0.0');

  select public.complete_ped_language_section(v_a, 'speech', array[v_a2])
    into v_ret_repair;
  select speech_completed_at into v_col_repair
    from public.ped_language_assessments where id = v_a;
  select status into v_a2_status
    from public.ped_language_milestones where id = v_a2;

  v_set_once := (v_col_repair = v_orig)      -- stamp did NOT move
            and (v_ret_repair = v_orig)      -- and the original was returned
            and (v_a2_status  = 'absent');   -- but the fill still happened

  -- ── (2) RETURNS: a fresh declaration stamps now() and returns it ──────────
  insert into public.ped_language_assessments
    (id, client_id, band_key, derived_age_months, age_source)
  values (v_b, v_client, '2_to_3y', 30, 'dob');
  insert into public.ped_language_milestones
    (id, ped_language_assessment_id, section, milestone_order, milestone_text, status,
     norm_reference, library_version)
  values (v_b1, v_b, 'speech', 1, 'proof b1', null, 'proof ref', '1.0.0');

  select public.complete_ped_language_section(v_b, 'speech', array[v_b1])
    into v_ret_fresh;
  select speech_completed_at into v_col_fresh
    from public.ped_language_assessments where id = v_b;

  v_returns := (v_ret_fresh is not null) and (v_ret_fresh = v_col_fresh);

  -- ── (3) COMPLETE FILL: a foreign id must abort the whole completion ───────
  insert into public.ped_language_assessments
    (id, client_id, band_key, derived_age_months, age_source)
  values (v_d, v_client, '2_to_3y', 30, 'dob');
  insert into public.ped_language_milestones
    (id, ped_language_assessment_id, section, milestone_order, milestone_text, status,
     norm_reference, library_version)
  values (v_d1, v_d, 'speech', 1, 'proof d1', null, 'proof ref', '1.0.0');

  begin
    -- one real row of this assessment + one id that is not a row of it
    perform public.complete_ped_language_section(
      v_d, 'speech', array[v_d1, gen_random_uuid()]);
    raise exception 'PROOF setup wrong: a foreign id did not abort completion';
  exception
    when sqlstate 'CU002' then
      v_raised_cu002 := true; -- expected: fill landed on 1 of 2
    when others then
      raise;
  end;
  select status into v_d1_status
    from public.ped_language_milestones where id = v_d1;
  select speech_completed_at into v_col_d
    from public.ped_language_assessments where id = v_d;

  v_complete := v_raised_cu002
            and (v_d1_status is null)   -- the real row was NOT filled
            and (v_col_d is null);      -- and the section was NOT stamped

  -- ── (4) ATOMIC: inject a failure on the stamp write, assert no rows changed
  insert into public.ped_language_assessments
    (id, client_id, band_key, derived_age_months, age_source)
  values (v_c, v_client, '2_to_3y', 30, 'dob');
  insert into public.ped_language_milestones
    (id, ped_language_assessment_id, section, milestone_order, milestone_text, status,
     norm_reference, library_version)
  values
    (v_c1, v_c, 'speech', 1, 'proof c1', null, 'proof ref', '1.0.0'),
    (v_c2, v_c, 'speech', 2, 'proof c2', null, 'proof ref', '1.0.0');

  -- Installed AFTER cases 1-3 (they must update the parent normally).
  create function public._ped_lang_proof_boom() returns trigger
    language plpgsql as $boom$
    begin
      raise exception 'injected stamp-write failure' using errcode = 'CU001';
    end
  $boom$;
  create trigger _ped_lang_proof_boom
    before update on public.ped_language_assessments
    for each row execute function public._ped_lang_proof_boom();

  begin
    perform public.complete_ped_language_section(v_c, 'speech', array[v_c1, v_c2]);
    raise exception 'PROOF setup wrong: completion did not error under injection';
  exception
    when sqlstate 'CU001' then
      null; -- expected: the function aborted at the stamp write
    when others then
      raise; -- anything else is a real failure
  end;

  select count(*) into v_absent_c
    from public.ped_language_milestones
   where ped_language_assessment_id = v_c and status = 'absent';
  v_atomic := (v_absent_c = 0);

  -- ── verdict ──────────────────────────────────────────────────────────────
  if v_set_once and v_returns and v_complete and v_atomic then
    raise notice 'PROOF PASS: set_once=% returns=% complete=% atomic=%',
      v_set_once, v_returns, v_complete, v_atomic;
  else
    raise exception 'PROOF FAIL: set_once=% (col=% ret=% a2=%) returns=% (ret=% col=%) complete=% (raised=% d1=% stamp=%) atomic=% (absent=%)',
      v_set_once, v_col_repair, v_ret_repair, v_a2_status,
      v_returns, v_ret_fresh, v_col_fresh,
      v_complete, v_raised_cu002, v_d1_status, v_col_d,
      v_atomic, v_absent_c;
  end if;
end
$proof$;

rollback;
