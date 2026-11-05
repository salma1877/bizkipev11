-- BizKipe v5.3 — Smart Workflow Rules
-- Additive migration. Run once in the Supabase SQL Editor, after
-- v3.6-customer-followups.sql and v5.2-automation-centre.sql.

create table if not exists public.bizkipe_workflow_rules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  rule_name text not null check (char_length(trim(rule_name)) between 1 and 120),
  customer_name text not null check (char_length(trim(customer_name)) between 1 and 120),
  next_run_date date not null,
  anchor_day smallint check (anchor_day between 1 and 31),
  frequency text not null check (frequency in ('once','daily','weekly','monthly')),
  channel text not null default 'Internal task' check (channel in ('WhatsApp','Email','Phone call','In person','Internal task','Other')),
  phone text not null default '' check (char_length(phone) <= 30),
  email text not null default '' check (char_length(email) <= 254),
  reference text not null default '' check (char_length(reference) <= 120),
  note text not null check (char_length(trim(note)) between 1 and 1000),
  status text not null default 'active' check (status in ('active','paused','completed')),
  generated_count integer not null default 0 check (generated_count >= 0),
  last_generated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists bizkipe_workflow_rules_owner_due_idx
  on public.bizkipe_workflow_rules (user_id, status, next_run_date);
alter table public.bizkipe_workflow_rules enable row level security;
drop policy if exists "Users manage own BizKipe workflow rules" on public.bizkipe_workflow_rules;
create policy "Users manage own BizKipe workflow rules" on public.bizkipe_workflow_rules
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
revoke all on table public.bizkipe_workflow_rules from anon;
grant select, insert, update, delete on public.bizkipe_workflow_rules to authenticated;

-- A stable occurrence key stops the same rule date creating two tasks.
-- The index is deliberately not partial: the upsert in the page needs a plain
-- unique index, and tasks without a key (NULL) are never treated as duplicates.
alter table public.bizkipe_customer_followups
  add column if not exists generated_key text;
drop index if exists public.bizkipe_customer_followups_generated_key_uidx;
create unique index if not exists bizkipe_customer_followups_generated_key_uidx
  on public.bizkipe_customer_followups (user_id, generated_key);
