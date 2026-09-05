-- test/sql/ped_language_atomic_completion_proof.sql
--
-- Proof for the review's defect A: public.complete_ped_language_section is
-- ATOMIC. It simulates a failure BETWEEN the two writes (the unmarked rows ->
-- 'absent', then the parent <section>_completed_at stamp) and asserts the
-- database is UNCHANGED — both writes land or neither does.
--
-- Injection: a temporary BEFORE UPDATE trigger on ped_language_assessments
-- that raises with SQLSTATE 'CU001', i.e. the stamp write fails after the rows
-- write. If the function were the old two-call path, the rows would already be
-- 'absent'; because it is one transaction, they roll back to NULL.
--
-- Self-contained and non-destructive: seeds throwaway rows inside a
-- transaction and ROLLS BACK, leaving zero residue. Requires the migration
-- 20260905093000_ped_language_atomic_section_completion to be applied first
-- (it tests the DEPLOYED function; the 'CU001'-only handler re-raises anything
-- else — e.g. undefined_function — so a missing deploy fails loudly, never a
-- false pass).
--
-- Run:  psql "$CUE_SANDBOX_DB_URL" -v ON_ERROR_STOP=1 \
--         -f test/sql/ped_language_atomic_completion_proof.sql
-- PASS: prints  NOTICE  PROOF PASS: absent_rows_after_injected_failure=0 (atomic)
-- FAIL: raises  PROOF FAIL: absent_rows_after_injected_failure=2 (NON-atomic)
--       and, with ON_ERROR_STOP, exits non-zero.

begin;

do $proof$
declare
  v_client uuid;
  v_assess uuid := gen_random_uuid();
  v_r1     uuid := gen_random_uuid();
  v_r2     uuid := gen_random_uuid();
  v_absent int;
begin
  -- Any existing client satisfies the FK; the whole transaction rolls back.
  select id into v_client from public.clients limit 1;
  if v_client is null then
    raise exception 'PROOF cannot run: no clients row to satisfy the FK';
  end if;

  insert into public.ped_language_assessments
    (id, client_id, band_key, derived_age_months, age_source)
  values
    (v_assess, v_client, '2_to_3y', 30, 'dob');

  insert into public.ped_language_milestones
    (id, ped_language_assessment_id, section, milestone_order, milestone_text, status,
     norm_reference, library_version)
  values
    (v_r1, v_assess, 'speech', 1, 'proof milestone 1', null, 'proof ref', '1.0.0'),
    (v_r2, v_assess, 'speech', 2, 'proof milestone 2', null, 'proof ref', '1.0.0');

  -- Inject the mid-completion failure: any UPDATE of the parent raises.
  create function public._ped_lang_proof_boom() returns trigger
    language plpgsql as $boom$
    begin
      raise exception 'injected stamp-write failure' using errcode = 'CU001';
    end
  $boom$;
  create trigger _ped_lang_proof_boom
    before update on public.ped_language_assessments
    for each row execute function public._ped_lang_proof_boom();

  -- Call the function; the stamp write hits the trigger and it must abort.
  begin
    perform public.complete_ped_language_section(v_assess, 'speech', array[v_r1, v_r2]);
    raise exception 'PROOF setup wrong: completion did not error under injection';
  exception
    when sqlstate 'CU001' then
      null; -- expected: the function aborted at the stamp write
    when others then
      raise; -- anything else (e.g. undefined_function) is a real failure
  end;

  -- THE ASSERTION: with an atomic function the rows write rolled back too, so
  -- no row is 'absent'. A non-atomic function would leave both at 'absent'.
  select count(*) into v_absent
    from public.ped_language_milestones
   where ped_language_assessment_id = v_assess
     and status = 'absent';

  if v_absent = 0 then
    raise notice 'PROOF PASS: absent_rows_after_injected_failure=% (atomic)', v_absent;
  else
    raise exception 'PROOF FAIL: absent_rows_after_injected_failure=% (NON-atomic)', v_absent;
  end if;
end
$proof$;

rollback;
