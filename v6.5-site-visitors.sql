-- BizKipe Site Visitors
-- Anonymous visit counts for the admin page. No names, emails or IP addresses are stored.
-- Only the server (service role) can read or write this table.

create table if not exists public.site_visitors (
  visitor_id text primary key check (visitor_id ~ '^[A-Za-z0-9-]{16,64}$'),
  first_seen timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  last_page text not null default '/' check (char_length(last_page) <= 80),
  is_app boolean not null default false,
  app_installed_at timestamptz,
  signed_in boolean not null default false
);

create index if not exists site_visitors_last_seen_idx on public.site_visitors (last_seen desc);

alter table public.site_visitors enable row level security;
revoke all on public.site_visitors from anon, authenticated;
