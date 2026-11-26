-- BizKipe Admin Activity Log
-- Records what is done in the admin page (payments verified, orders fulfilled, sign-ins, wrong-token attempts).
-- No tokens, passwords or IP addresses are stored; the address is kept only as a one-way hash.
-- Only the server (service role) can read or write this table.

create table if not exists public.admin_activity (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  action text not null check (char_length(action) between 1 and 40),
  detail text not null default '' check (char_length(detail) <= 300),
  order_id uuid,
  success boolean not null default true,
  ip_hash text not null default '' check (char_length(ip_hash) <= 64)
);

create index if not exists admin_activity_created_idx on public.admin_activity (created_at desc);
create index if not exists admin_activity_login_idx on public.admin_activity (action, ip_hash, created_at desc);

alter table public.admin_activity enable row level security;
revoke all on public.admin_activity from anon, authenticated;
