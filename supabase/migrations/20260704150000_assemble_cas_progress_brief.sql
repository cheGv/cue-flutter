-- assemble_cas_progress_brief(p_stg_id uuid) → jsonb — the deterministic
-- four-block brief over cas_session_progress. Pure SQL, no AI, same
-- no-fabrication guarantee as assemble_recall_card: every value is copied
-- or counted from real rows; nothing is inferred.
--
-- Blocks: where_he_is (frontier/floor + sticky promotion + breakthrough/
-- emerging state), trend (verbatim per-level dial sequences over the
-- 3-session window), best_so_far (best accuracy, then lowest cue, then
-- harder level on ties — full history), next_move (the fork, named and
-- never recommended), watch_for (null + note until a capture field
-- feeds it).
--
-- Sticky frontier (locked 2026-07-04): a level promotes from frontier to
-- floor ONLY when 'accurate' in the 2 MOST RECENT CONSECUTIVE window
-- sessions (acc2). Accurate in the newest session alone stays frontier
-- with frontier_state='breakthrough'; partial/inaccurate stays
-- 'emerging'. A 1-session window can never have a floor — one session
-- cannot show consistency.
--
-- Applied to sandbox 2026-07-04 via MCP in two steps (history versions
-- 20260704145726 initial + 20260704151907 sticky-frontier revision).
-- This file captures the net (final) function so schema-as-code matches
-- schema-as-applied.
create or replace function public.assemble_cas_progress_brief(p_stg_id uuid)
returns jsonb
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
with win as (
  select s.id, s.date, s.created_at
    from public.sessions s
   where s.deleted_at is null
     and exists (select 1
                   from public.cas_session_progress p
                  where p.session_id = s.id
                    and p.stg_id = p_stg_id)
   order by s.date desc nulls last, s.created_at desc
   limit 3
),
seq as (
  select id, date,
         row_number() over (order by date asc nulls first, created_at asc) as seq
    from win
),
n as (select count(*)::int as n_sessions from seq),
rows as (
  select p.level_label, p.level_order, p.accuracy,
         case when p.cue_level_used = 'unknown'
              then coalesce(p.cue_level_used_raw, p.cue_level_used)
              else p.cue_level_used end as cue,
         q.seq, q.date as session_date,
         case p.accuracy
           when 'accurate'   then 0
           when 'partial'    then 1
           when 'inaccurate' then 2
         end as acc_rank,
         case p.cue_level_used
           when 'independent'    then 0
           when 'minimal'        then 1
           when 'moderate'       then 2
           when 'maximal'        then 3
           when 'hand_over_hand' then 4
         end as cue_rank
    from public.cas_session_progress p
    join seq q on q.id = p.session_id
   where p.stg_id = p_stg_id
),
latest as (select * from rows where seq = (select max(seq) from seq)),
prev as (
  select * from rows where seq = (select max(seq) from seq) - 1
),
acc2 as (
  select l.level_order
    from latest l
    join prev p on p.level_order = l.level_order
   where l.accuracy = 'accurate'
     and p.accuracy = 'accurate'
),
floor_row as (
  select * from latest
   where level_order in (select level_order from acc2)
   order by level_order desc
   limit 1
),
frontier_row as (
  select * from latest
   where accuracy is not null
     and level_order not in (select level_order from acc2)
     and level_order > coalesce((select level_order from floor_row), -2147483648)
   order by level_order asc
   limit 1
),
floor_hold as (
  select count(*)::int as accurate_count
    from rows r
   where r.level_order = (select level_order from floor_row)
     and r.accuracy = 'accurate'
),
mv as (
  select (select level_label from floor_row)    as fl_label,
         (select level_order from floor_row)    as fl_order,
         (select cue         from floor_row)    as fl_cue,
         (select cue_rank    from floor_row)    as fl_cue_rank,
         (select level_label from frontier_row) as fr_label,
         (select level_order from frontier_row) as fr_order,
         (select accuracy    from frontier_row) as fr_acc,
         (select cue         from frontier_row) as fr_cue,
         (select case when accuracy = 'accurate' then 'breakthrough'
                      else 'emerging' end
            from frontier_row)                  as fr_state
),
trend_cells as (
  select l.level_label, l.level_order, q.seq, r.accuracy, r.cue
    from (select distinct level_label, level_order from rows) l
   cross join seq q
    left join rows r on r.level_order = l.level_order and r.seq = q.seq
),
trend_per_level as (
  select level_label, level_order,
         jsonb_agg(to_jsonb(accuracy) order by seq) as accuracy_seq,
         jsonb_agg(to_jsonb(cue)      order by seq) as cue_seq
    from trend_cells
   group by level_label, level_order
),
best as (
  select p.level_label, p.level_order, p.accuracy, p.cue_level_used,
         s.date as session_date,
         case p.accuracy
           when 'accurate' then 0 when 'partial' then 1 when 'inaccurate' then 2
         end as acc_rank,
         case p.cue_level_used
           when 'independent' then 0 when 'minimal' then 1 when 'moderate' then 2
           when 'maximal' then 3 when 'hand_over_hand' then 4
         end as cue_rank
    from public.cas_session_progress p
    join public.sessions s on s.id = p.session_id
   where p.stg_id = p_stg_id
     and s.deleted_at is null
     and p.accuracy is not null
   order by acc_rank asc, cue_rank asc nulls last,
            level_order desc,
            s.date desc nulls last, p.created_at desc
   limit 1
)
select jsonb_build_object(
  'stg_id',          p_stg_id::text,
  'assembled_at',    to_jsonb(now()),
  'window_sessions', n.n_sessions,
  'session_dates',   coalesce((select jsonb_agg(to_jsonb(date) order by seq) from seq), '[]'::jsonb),
  'where_he_is', case when n.n_sessions = 0 then null else jsonb_build_object(
    'frontier_label',       mv.fr_label,
    'frontier_order',       mv.fr_order,
    'frontier_accuracy',    mv.fr_acc,
    'frontier_cue',         mv.fr_cue,
    'frontier_state',       mv.fr_state,
    'floor_label',          mv.fl_label,
    'floor_order',          mv.fl_order,
    'floor_cue',            mv.fl_cue,
    'floor_holding',        case when mv.fl_label is null then null
                                 else (floor_hold.accurate_count = n.n_sessions
                                       and n.n_sessions > 1) end,
    'floor_accurate_count', case when mv.fl_label is null then null
                                 else floor_hold.accurate_count end
  ) end,
  'trend', coalesce((
    select jsonb_agg(jsonb_build_object(
             'level_label',  level_label,
             'level_order',  level_order,
             'accuracy_seq', accuracy_seq,
             'cue_seq',      cue_seq
           ) order by level_order)
      from trend_per_level), '[]'::jsonb),
  'best_so_far', (
    select jsonb_build_object(
             'level_label',    level_label,
             'level_order',    level_order,
             'accuracy',       accuracy,
             'cue_level_used', cue_level_used,
             'session_date',   session_date)
      from best),
  'next_move', case
    when n.n_sessions = 0 then null
    when mv.fl_label is not null and mv.fr_label is not null
         and coalesce(mv.fl_cue_rank, 99) > 0 then jsonb_build_object(
      'options', jsonb_build_array(
        format('fade cue at %s (currently %s)', mv.fl_label, coalesce(mv.fl_cue, '—')),
        format('advance work at %s (currently %s @ %s)',
               mv.fr_label, mv.fr_acc, coalesce(mv.fr_cue, '—'))),
      'basis', format('%s accurate @ %s in the most recent session; %s %s @ %s',
               mv.fl_label, coalesce(mv.fl_cue, '—'),
               mv.fr_label, mv.fr_acc, coalesce(mv.fr_cue, '—')))
    when mv.fl_label is not null and mv.fr_label is not null then jsonb_build_object(
      'options', jsonb_build_array(
        format('advance work at %s (currently %s @ %s)',
               mv.fr_label, mv.fr_acc, coalesce(mv.fr_cue, '—')),
        format('hold %s at independent', mv.fl_label)),
      'basis', format('%s accurate @ independent in the most recent session; %s %s @ %s',
               mv.fl_label, mv.fr_label, mv.fr_acc, coalesce(mv.fr_cue, '—')))
    when mv.fl_label is not null and coalesce(mv.fl_cue_rank, 99) > 0 then jsonb_build_object(
      'options', jsonb_build_array(
        format('fade cue at %s (currently %s)', mv.fl_label, coalesce(mv.fl_cue, '—')),
        format('introduce the level above %s', mv.fl_label)),
      'basis', format('all recorded levels accurate in the most recent session; %s is the highest, @ %s',
               mv.fl_label, coalesce(mv.fl_cue, '—')))
    when mv.fl_label is not null then jsonb_build_object(
      'options', jsonb_build_array(
        format('introduce the level above %s', mv.fl_label)),
      'basis', format('all recorded levels accurate @ independent in the most recent session; %s is the highest',
               mv.fl_label))
    when mv.fr_label is not null then jsonb_build_object(
      'options', jsonb_build_array(
        format('increase cue support at %s (currently %s @ %s)',
               mv.fr_label, mv.fr_acc, coalesce(mv.fr_cue, '—')),
        format('shift work below %s', mv.fr_label)),
      'basis', format('no level accurate in the most recent session; lowest open level is %s, %s @ %s',
               mv.fr_label, mv.fr_acc, coalesce(mv.fr_cue, '—')))
    else null
  end,
  'watch_for',      null,
  'watch_for_note', 'awaits capture surface — no captured field feeds watch_for yet'
)
from n, mv, floor_hold;
$function$;
