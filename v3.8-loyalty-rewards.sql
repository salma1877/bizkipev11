-- BizKipe v3.8 — Loyalty points and rewards
-- Run once in Supabase SQL Editor after the existing BizKipe migrations.
-- Points are calculated by the app from manually recorded document_payments.
-- This migration stores per-user earning settings and redemption records only.

create table if not exists public.bizkipe_loyalty_settings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  currency text not null default 'KES' check (currency ~ '^[A-Z]{3}$'),
  spend_step numeric(12,2) not null default 100 check (spend_step > 0),
  points_per_step integer not null default 1 check (points_per_step between 1 and 100000),
  reward_threshold integer not null default 100 check (reward_threshold between 1 and 100000000),
  reward_name text not null default 'Loyalty reward' check (char_length(trim(reward_name)) between 1 and 100),
  updated_at timestamptz not null default now()
);

create table if not exists public.bizkipe_loyalty_redemptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  customer_name text not null check (char_length(trim(customer_name)) between 1 and 120),
  customer_key text not null check (char_length(trim(customer_key)) between 1 and 160),
  points integer not null check (points > 0),
  currency text not null default 'KES' check (currency ~ '^[A-Z]{3}$'),
  reward_name text not null check (char_length(trim(reward_name)) between 1 and 100),
  status text not null default 'pending' check (status in ('pending','fulfilled','cancelled')),
  redeemed_on date not null default current_date,
  note text not null default '' check (char_length(note) <= 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists bizkipe_loyalty_redemptions_owner_date_idx
  on public.bizkipe_loyalty_redemptions (user_id, redeemed_on desc);
create index if not exists bizkipe_loyalty_redemptions_owner_customer_idx
  on public.bizkipe_loyalty_redemptions (user_id, customer_key);

alter table public.bizkipe_loyalty_settings enable row level security;
alter table public.bizkipe_loyalty_redemptions enable row level security;

drop policy if exists "Users manage own loyalty settings" on public.bizkipe_loyalty_settings;
create policy "Users manage own loyalty settings" on public.bizkipe_loyalty_settings
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users manage own loyalty redemptions" on public.bizkipe_loyalty_redemptions;
create policy "Users manage own loyalty redemptions" on public.bizkipe_loyalty_redemptions
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

revoke all on table public.bizkipe_loyalty_settings from anon;
revoke all on table public.bizkipe_loyalty_redemptions from anon;
grant select, insert, update, delete on table public.bizkipe_loyalty_settings to authenticated;
grant select, insert, update, delete on table public.bizkipe_loyalty_redemptions to authenticated;
