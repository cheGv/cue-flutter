-- Phase 4.0.9 — Clients screen fixture filtering.
--
-- Adds clients.is_fixture so seeded test / demo / "Domain Detector"
-- rows can be excluded from production builds. The roster service
-- (lib/services/clients_roster_service.dart) appends a
-- `WHERE is_fixture = false` filter when kReleaseMode is true; debug
-- builds still surface fixtures (with a dev-mode banner) so they remain
-- usable during development.

alter table public.clients
  add column if not exists is_fixture boolean not null default false;

update public.clients
   set is_fixture = true
 where name ilike '%Test%'
    or name ilike '%Domain Detector%'
    or name ilike '%fixture%';
