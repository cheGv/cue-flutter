-- test/rls/rls_catalog_audit.sql
--
-- READ-ONLY RLS catalog audit. Safe to point at ANY project,
-- including production: it writes nothing, creates no fixtures, no
-- temp objects, takes no locks beyond ordinary catalog reads.
--
-- Write-path refusal is ENFORCED BY POSTGRES, not by self-inspection:
-- the first statement puts the transaction in READ ONLY mode, so any
-- write path in this script — present today or introduced by a future
-- edit — fails immediately with SQLSTATE 25006
-- (read_only_sql_transaction) before touching anything. That is the
-- refusal mechanism.
--
-- What it reports (one jsonb row):
--   sealed_count / rls_off_count      — the catalog posture
--   rls_off_tables                    — every rowsecurity=false table
--   allowlist_table_present           — whether public.rls_allowlist
--                                       exists on the audited project
--   unaccounted                       — rowsecurity=false tables with
--                                       no allowlist entry. On a
--                                       project WITHOUT the allowlist
--                                       table (e.g. production) this
--                                       is ALL rowsecurity=false
--                                       tables — the honest reading.
--   stale_allowlist                   — allowlist entries whose table
--                                       is now sealed or gone
--
-- The allowlist read is guarded by to_regclass + query_to_xml (a
-- dynamic query evaluated only when the table exists), so the script
-- parses and runs on projects that have never seen the allowlist
-- migration.

set transaction read only;

with cat as (
  select tablename, rowsecurity
    from pg_tables
   where schemaname = 'public'
),
allowlist as (
  select case
           when to_regclass('public.rls_allowlist') is not null then
             (select array(
                select (unnest(xpath(
                  '/table/row/table_name/text()',
                  query_to_xml('select table_name from public.rls_allowlist',
                               true, false, ''))))::text))
           else null
         end as names
)
select jsonb_build_object(
  'audit',                   'rls_catalog_audit',
  'audited_at',              now(),
  'database',                current_database(),
  'sealed_count',            (select count(*) from cat where rowsecurity),
  'rls_off_count',           (select count(*) from cat where not rowsecurity),
  'rls_off_tables',          coalesce((select jsonb_agg(tablename order by tablename)
                                         from cat where not rowsecurity), '[]'::jsonb),
  'allowlist_table_present', (select names is not null from allowlist),
  'unaccounted',             coalesce((select jsonb_agg(c.tablename order by c.tablename)
                                         from cat c cross join allowlist al
                                        where not c.rowsecurity
                                          and (al.names is null
                                               or not (c.tablename::text = any(al.names)))
                                      ), '[]'::jsonb),
  'stale_allowlist',         coalesce((select jsonb_agg(x order by x) from (
                                select a || ' (now sealed)' as x
                                  from allowlist al2 cross join unnest(coalesce(al2.names, '{}'::text[])) a
                                  join cat c on c.tablename::text = a and c.rowsecurity
                                union all
                                select a || ' (no longer exists)'
                                  from allowlist al3 cross join unnest(coalesce(al3.names, '{}'::text[])) a
                                 where a not in (select tablename::text from cat)) s), '[]'::jsonb)
) as rls_catalog_audit;
