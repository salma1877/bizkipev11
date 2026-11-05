-- BizKipe v5.4 — Workflow history and notification preferences
-- Additive migration. Apply once after v5.3-workflow-rules.sql (run in the SQL Editor).
-- Browser notifications are generated only while a signed-in user opens the Notification Centre.
-- No background push service or customer messaging is configured by this migration.

create table if not exists public.bizkipe_workflow_activity (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  event_type text not null check (event_type in ('rule_created','rule_paused','rule_resumed','rule_deleted','tasks_generated','task_completed','task_cancelled','task_deleted','preferences_updated')),
  title text not null check (char_length(trim(title)) between 1 and 160),
  detail text not null default '' check (char_length(detail) <= 1000),
  related_id uuid null,
  created_at timestamptz not null default now()
);
create index if not exists bizkipe_workflow_activity_owner_date_idx
  on public.bizkipe_workflow_activity(user_id, created_at desc);
alter table public.bizkipe_workflow_activity enable row level security;
drop policy if exists "Users manage own BizKipe workflow activity" on public.bizkipe_workflow_activity;
create policy "Users manage own BizKipe workflow activity" on public.bizkipe_workflow_activity
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
revoke all on table public.bizkipe_workflow_activity from anon;
grant select, insert, update, delete on public.bizkipe_workflow_activity to authenticated;

create table if not exists public.bizkipe_notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  browser_notifications boolean not null default false,
  due_today_alerts boolean not null default true,
  overdue_alerts boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.bizkipe_notification_preferences enable row level security;
drop policy if exists "Users manage own BizKipe notification preferences" on public.bizkipe_notification_preferences;
create policy "Users manage own BizKipe notification preferences" on public.bizkipe_notification_preferences
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
revoke all on table public.bizkipe_notification_preferences from anon;
grant select, insert, update, delete on public.bizkipe_notification_preferences to authenticated;
