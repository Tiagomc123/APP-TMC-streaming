-- Snapshot of sources imported from lib/legacy/domains.dart.
-- Applied to project xjqdiulxrprxegfrufyf on 2026-10-26.
-- Edit the live list in Supabase Dashboard > Table Editor > tmc_sources.

create table if not exists public.tmc_sources (
  id text primary key check (id ~ '^[a-z0-9_]+$'),
  label text not null,
  urls text[] not null default '{}',
  enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.tmc_sources enable row level security;
revoke all on table public.tmc_sources from anon, authenticated;
drop policy if exists tmc_sources_no_public_read on public.tmc_sources;
create policy tmc_sources_no_public_read
on public.tmc_sources for select to anon, authenticated using (false);

insert into public.tmc_sources (id, label, urls, enabled) values
  ('superflix_api', 'SuperFlixAPI', array['https://superflixapi.fun','https://superflixapi.pro','https://superflixapi.sbs','https://superflixapi.top','https://superflixapi.online','https://superflixapi.site','https://superflixapi.store','https://superflixapi.xyz','https://superflixapi.app','https://superflixapi.net','https://superflixapi.me','https://superflixapi.live'], true),
  ('pobreflix', 'PobreFlixHD', array['https://pobreflixhd.sbs','https://pobreflixhd.top','https://pobreflixhd.tv','https://pobreflixhd.online','https://pobreflixhd.site','https://pobreflixhd.xyz','https://pobreflixhd.app','https://pobreflixhd.net'], false),
  ('embedcine', 'EmbedCine', array['https://embedcine.com','https://embedcine.top','https://embedcine.xyz','https://embedcine.net','https://embedcine.tv'], true),
  ('warezcdn', 'WarezCDN', array['https://warezcdn.com','https://warezcdn.net','https://warezcdn.tv','https://warezcdn.xyz','https://warezcdn.top'], true),
  ('vidsrcxyz', 'VidSrc XYZ', array['https://vidsrc.xyz','https://vidsrc.net','https://vidsrc.vip','https://vidsrc.icu','https://vidsrc.pm'], false),
  ('vidsrccc', 'VidSrc CC', array['https://vidsrc.cc','https://vidsrc.to','https://vidsrc.me','https://vidsrc.sh'], false),
  ('vidsrcmov', 'VidSrc MOV', array['https://vidsrc.mov','https://vidsrc.buzz','https://vidsrc.hair'], false),
  ('vidlink', 'VidLink', array['https://vidlink.pro'], false),
  ('embedsu', 'Embed.su', array['https://embed.su'], false),
  ('moviesapi', 'MoviesAPI', array['https://moviesapi.club','https://moviesapi.to'], false),
  ('twembed', '2Embed', array['https://www.2embed.cc','https://www.2embed.to','https://www.2embed.skin','https://2embed.stream'], false),
  ('smashy', 'SmashyStream', array['https://player.smashy.stream'], false),
  ('autoembed', 'AutoEmbed', array['https://player.autoembed.cc','https://autoembed.co','https://autoembed.me','https://autoembed.app'], false),
  ('m111', '111Movies', array['https://111movies.com'], false),
  ('vidbinge', 'VidBinge', array['https://vidbinge.dev'], false),
  ('videasy', 'Videasy', array['https://player.videasy.net'], false),
  ('multiembed', 'MultiEmbed', array['https://multiembed.mov'], false),
  ('vidfast', 'VidFast', array['https://vidfast.pro'], false),
  ('vidcore', 'VidCore', array['https://vidcore.org'], false),
  ('embedwave', 'EmbedWave', array['https://embedwave.cc'], false),
  ('vixsrc', 'VixSrc', array['https://vixsrc.to'], false),
  ('nontongo', 'NontonGo', array['https://nontongo.win'], false),
  ('pontofinal', 'PontoFinal', array['https://pontofinal.org'], true),
  ('custom_01', 'Nova fonte 01', array[]::text[], false),
  ('custom_02', 'Nova fonte 02', array[]::text[], false),
  ('custom_03', 'Nova fonte 03', array[]::text[], false),
  ('custom_04', 'Nova fonte 04', array[]::text[], false),
  ('custom_05', 'Nova fonte 05', array[]::text[], false),
  ('custom_06', 'Nova fonte 06', array[]::text[], false),
  ('custom_07', 'Nova fonte 07', array[]::text[], false),
  ('custom_08', 'Nova fonte 08', array[]::text[], false),
  ('custom_09', 'Nova fonte 09', array[]::text[], false),
  ('custom_10', 'Nova fonte 10', array[]::text[], false)
on conflict (id) do nothing;
