-- BizKipe v3.6 — Customer follow-up planner
-- Run once in the Supabase SQL Editor. Additive migration; does not alter existing tables.

create table if not exists public.bizkipe_customer_followups (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  customer_name text not null check (char_length(trim(customer_name)) between 1 and 120),
  follow_up_date date not null,
  channel text not null default 'WhatsApp'
    check (channel in ('WhatsApp','Email','Phone call','In person','Other')),
  phone text not null default '' check (char_length(phone) <= 30),
  email text not null default '' check (char_length(email) <= 254),
  reference text not null default '' check (char_length(reference) <= 120),
  note text not null check (char_length(trim(note)) between 1 and 1000),
  status text not null default 'open'
    check (status in ('open','completed','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists bizkipe_customer_followups_owner_date_idx
  on public.bizkipe_customer_followups (user_id, status, follow_up_date);

alter table public.bizkipe_customer_followups enable row level security;
drop policy if exists "Users can read own BizKipe follow-ups" on public.bizkipe_customer_followups;
create policy "Users can read own BizKipe follow-ups" on public.bizkipe_customer_followups
  for select to authenticated using (auth.uid() = user_id);
drop policy if exists "Users can create own BizKipe follow-ups" on public.bizkipe_customer_followups;
create policy "Users can create own BizKipe follow-ups" on public.bizkipe_customer_followups
  for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Users can update own BizKipe follow-ups" on public.bizkipe_customer_followups;
create policy "Users can update own BizKipe follow-ups" on public.bizkipe_customer_followups
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "Users can delete own BizKipe follow-ups" on public.bizkipe_customer_followups;
create policy "Users can delete own BizKipe follow-ups" on public.bizkipe_customer_followups
  for delete to authenticated using (auth.uid() = user_id);

revoke all on table public.bizkipe_customer_followups from anon;
grant select, insert, update, delete on table public.bizkipe_customer_followups to authenticated;
