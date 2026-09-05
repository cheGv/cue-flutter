-- A's ROOT CAUSE (review 2026-08-02 / re-verified 2026-09-03) — make
-- Pediatric Language section completion ATOMIC.
--
-- completeSection() issued TWO non-transactional PostgREST updates: the
-- unmarked rows -> 'absent', then the parent <section>_completed_at stamp. A
-- failure between them left rows stamped 'absent' — a positive clinical claim
-- ("not yet doing this") the SLP never made — with NO parent stamp, while the
-- capture controller reverted only its in-memory state (no compensating
-- write). Screen and record diverged; the reader's absence_without_declaration
-- anomaly was the only thing that noticed after the fact.
--
-- This function performs BOTH writes in one transaction. A plpgsql function
-- body is a single transaction: an error on the stamp write rolls the rows
-- write back with it, so both land or neither does. The controller's
-- memory-only revert is then CORRECT rather than a lie — on failure the DB
-- never changed.
--
-- SECURITY INVOKER (the default — stated for the record): the caller's RLS
-- still governs both writes (slp_owns_via_assessment on the milestone rows,
-- slp_owns_via_client on the parent). No privilege escalation; the SLP can
-- already UPDATE exactly these rows through PostgREST today. The stamp is
-- server now() (was a client DateTime.now()), which also removes the
-- client/server clock skew the reader's post-declaration guard defends
-- against.

create or replace function public.complete_ped_language_section(
  p_assessment_id    uuid,
  p_section          text,
  p_unmarked_row_ids uuid[]
)
returns void
language plpgsql
set search_path = public
as $$
begin
  if p_section not in ('speech', 'language', 'literacy') then
    raise exception 'complete_ped_language_section: invalid section %', p_section
      using errcode = '22023'; -- invalid_parameter_value
  end if;

  -- The rows the SLP left unmarked become an explicit 'absent'. Scoped to
  -- THIS assessment and to the caller-supplied id list — never a server-side
  -- status-IS-NULL filter, so a concurrent in-flight save is never clobbered.
  -- Identical predicate to the retired two-call path.
  if array_length(p_unmarked_row_ids, 1) is not null then
    update public.ped_language_milestones
       set status          = 'absent',
           evidence_source = null,
           updated_at      = now()
     where ped_language_assessment_id = p_assessment_id
       and id = any (p_unmarked_row_ids);
  end if;

  -- The section's completion stamp. If THIS write fails, the rows write above
  -- rolls back with it — that is the whole point. Static per-section columns,
  -- so no dynamic SQL.
  update public.ped_language_assessments
     set speech_completed_at =
           case when p_section = 'speech'   then now() else speech_completed_at   end,
         language_completed_at =
           case when p_section = 'language' then now() else language_completed_at end,
         literacy_completed_at =
           case when p_section = 'literacy' then now() else literacy_completed_at end,
         updated_at = now()
   where id = p_assessment_id;

  if not found then
    raise exception 'complete_ped_language_section: no assessment %', p_assessment_id
      using errcode = 'P0002'; -- no_data_found
  end if;
end;
$$;

grant execute on function
  public.complete_ped_language_section(uuid, text, uuid[]) to authenticated;

comment on function public.complete_ped_language_section(uuid, text, uuid[]) is
  'Atomic section completion for Pediatric Language capture: writes the '
  'unmarked rows to ''absent'' and stamps <section>_completed_at in ONE '
  'transaction, so a partial failure leaves the record unchanged (the capture '
  'controller''s in-memory revert then matches the DB). Replaces the two '
  'non-transactional PostgREST updates that could orphan ''absent'' rows. '
  'SECURITY INVOKER — the caller''s RLS governs both writes. Proof: '
  'test/sql/ped_language_atomic_completion_proof.sql.';
