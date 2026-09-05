-- Review defect C (controller half) — two corrections to
-- complete_ped_language_section, both found by adversarial review of the
-- created_at discrimination change:
--
-- 1. SET ONCE. The v1 function stamped <section>_completed_at = now() on EVERY
--    call, including a REPAIR of an already-declared section. That (a) rewrote
--    when she actually declared the section done, and (b) moved the stamp past
--    every row the bootstrap self-heal had seeded AFTER the declaration — rows
--    the anomaly check deliberately excuses as questions she was never shown —
--    so the repair banner re-fired on exactly the rows the repair left alone.
--    Now a fresh declaration stamps now(); a repair keeps the original stamp.
--
-- 2. RETURNS THE STAMP. The app needs the completion stamp AS THE SERVER
--    RECORDED IT (the same clock as every row's created_at), not a client
--    DateTime.now(). Reading it back in a second request after the RPC had
--    committed created a new failure class: a transient failure of that read
--    was indistinguishable from a failed write, so the controller rolled the
--    screen back while the record held the completion — the very divergence
--    the atomic RPC was introduced to eliminate. Returning the stamp from the
--    same transaction makes it one round trip and removes that class outright.
--
-- Everything else is unchanged from v1: one transaction for both writes
-- (both land or neither), SECURITY INVOKER so the caller's RLS governs both,
-- the rows predicate scoped to this assessment + the explicit id list.
--
-- A return type cannot be changed with CREATE OR REPLACE; drop and recreate.
--
-- Rollout, stated exactly. The app tolerates the v1 function: a void result
-- reaches the client as null, read as "stamp not supplied", and the controller
-- keeps its placeholder. But the two fixes are NOT live until this is applied,
-- and the created_at exclusion's guarantee DEPENDS on fix 1: under v1 a Repair
-- still re-stamps the section to now(), so on the NEXT open the self-heal rows
-- the repair deliberately left unmarked sit before the new stamp, the banner
-- re-fires for them, and a further Repair would write 'absent' on questions
-- never asked. Apply this before relying on the exclusion.

drop function if exists public.complete_ped_language_section(uuid, text, uuid[]);

create function public.complete_ped_language_section(
  p_assessment_id    uuid,
  p_section          text,
  p_unmarked_row_ids uuid[]
)
returns timestamptz
language plpgsql
set search_path = public
as $$
declare
  v_stamp    timestamptz;
  v_count    int;
  v_expected int;
begin
  if p_section not in ('speech', 'language', 'literacy') then
    raise exception 'complete_ped_language_section: invalid section %', p_section
      using errcode = '22023'; -- invalid_parameter_value
  end if;

  -- The rows the SLP left unmarked become an explicit 'absent'. Scoped to
  -- THIS assessment and to the caller-supplied id list — never a server-side
  -- status-IS-NULL filter, so a concurrent in-flight save is never clobbered.
  if array_length(p_unmarked_row_ids, 1) is not null then
    update public.ped_language_milestones
       set status          = 'absent',
           evidence_source = null,
           updated_at      = now()
     where ped_language_assessment_id = p_assessment_id
       and id = any (p_unmarked_row_ids);

    -- THE FILL MUST LAND ON EVERY REQUESTED ROW. If it did not — an id from
    -- another assessment, a row that vanished, a policy that hid it — this
    -- section must not be stamped done over rows still NULL: the banner would
    -- clear now and silently return on the next open. Raise instead, so the
    -- whole transaction rolls back and the caller sees a failed write.
    -- Distinct ids, so a duplicated id can never masquerade as a missing row.
    get diagnostics v_count = row_count;
    select count(distinct x) into v_expected from unnest(p_unmarked_row_ids) x;
    if v_count <> v_expected then
      raise exception
        'complete_ped_language_section: fill landed on % of % requested rows',
        v_count, v_expected
        using errcode = 'CU002';
    end if;
  end if;

  -- SET ONCE: coalesce keeps an existing declaration time; only a NULL stamp
  -- (a fresh declaration) takes now(). If THIS write fails, the rows write
  -- above rolls back with it. Static per-section columns, no dynamic SQL.
  update public.ped_language_assessments
     set speech_completed_at =
           case when p_section = 'speech'
                then coalesce(speech_completed_at, now())
                else speech_completed_at end,
         language_completed_at =
           case when p_section = 'language'
                then coalesce(language_completed_at, now())
                else language_completed_at end,
         literacy_completed_at =
           case when p_section = 'literacy'
                then coalesce(literacy_completed_at, now())
                else literacy_completed_at end,
         updated_at = now()
   where id = p_assessment_id
  returning case p_section
              when 'speech'   then speech_completed_at
              when 'language' then language_completed_at
              else                 literacy_completed_at
            end
       into v_stamp;

  if not found then
    raise exception 'complete_ped_language_section: no assessment %', p_assessment_id
      using errcode = 'P0002'; -- no_data_found
  end if;

  return v_stamp;
end;
$$;

grant execute on function
  public.complete_ped_language_section(uuid, text, uuid[]) to authenticated;

comment on function public.complete_ped_language_section(uuid, text, uuid[]) is
  'Atomic section completion for Pediatric Language capture: writes the '
  'unmarked rows to ''absent'' and stamps <section>_completed_at in ONE '
  'transaction (both land or neither). The stamp is SET ONCE — a repair of an '
  'already-declared section keeps the original declaration time — and is '
  'RETURNED as the server recorded it, so the app never compares a client '
  'clock against created_at. SECURITY INVOKER: the caller''s RLS governs '
  'both writes. Proof: test/sql/ped_language_atomic_completion_proof.sql.';
