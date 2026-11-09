-- BizKipe v5.7 — Customer Retention & Loyalty Campaign Planning
-- Additive and safe to run more than once. Run after the CRM, loyalty and v5.6 migrations.
-- Plans are internal records; no messages are sent.
do $fn$
begin
  create table if not exists public.bizkipe_retention_plans (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    plan_name text not null check (char_length(trim(plan_name)) between 1 and 120),
    segment text not null check (segment in ('loyalty_ready','high_value','at_risk','repeat','new')),
    channel text not null default 'WhatsApp' check (channel in ('WhatsApp','Email','SMS','In person','Other')),
    message_draft text not null default '' check (char_length(message_draft) <= 5000),
    audience_count integer not null default 0 check (audience_count >= 0),
    status text not null default 'draft' check (status in ('draft','planned','completed','archived')),
    notes text not null default '' check (char_length(notes) <= 1500),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
  );
  create index if not exists bizkipe_retention_plans_owner_date_idx on public.bizkipe_retention_plans(user_id, created_at desc);
  alter table public.bizkipe_retention_plans enable row level security;
  drop policy if exists "Users manage own BizKipe retention plans" on public.bizkipe_retention_plans;
  create policy "Users manage own BizKipe retention plans" on public.bizkipe_retention_plans for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
  revoke all on table public.bizkipe_retention_plans from anon;
  grant select, insert, update, delete on table public.bizkipe_retention_plans to authenticated;
end
$fn$;
