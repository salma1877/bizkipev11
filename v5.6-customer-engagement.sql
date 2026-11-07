-- BizKipe v5.6 — Customer Engagement Centre
-- Additive and safe to run more than once. Run after the customer CRM migration.
-- Campaign sending is manual; engagement events are entered by the business owner.
do $fn$
begin
  create table if not exists public.bizkipe_customer_campaigns (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    campaign_name text not null check (char_length(trim(campaign_name)) between 1 and 120),
    channel text not null check (channel in ('WhatsApp','Email','SMS','In person','Other')),
    audience_segment text not null default 'all' check (audience_segment in ('all','repeat','new','inactive','noinvoice')),
    message_subject text not null default '' check (char_length(message_subject) <= 180),
    message_body text not null check (char_length(trim(message_body)) between 1 and 5000),
    audience_count integer not null default 0 check (audience_count >= 0),
    status text not null default 'draft' check (status in ('draft','approved','sent','archived')),
    owner_notes text not null default '' check (char_length(owner_notes) <= 1500),
    sent_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
  );
  create index if not exists bizkipe_customer_campaigns_owner_date_idx on public.bizkipe_customer_campaigns(user_id, created_at desc);
  create unique index if not exists bizkipe_customer_campaigns_id_owner_uidx on public.bizkipe_customer_campaigns(id, user_id);
  alter table public.bizkipe_customer_campaigns enable row level security;
  drop policy if exists "Users manage own BizKipe customer campaigns" on public.bizkipe_customer_campaigns;
  create policy "Users manage own BizKipe customer campaigns" on public.bizkipe_customer_campaigns for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
  revoke all on table public.bizkipe_customer_campaigns from anon;
  grant select, insert, update, delete on public.bizkipe_customer_campaigns to authenticated;
  create table if not exists public.bizkipe_campaign_engagement_events (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    campaign_id uuid not null,
    customer_name text not null default '' check (char_length(customer_name) <= 120),
    event_type text not null check (event_type in ('sent','replied','converted','unsubscribed','other')),
    event_note text not null default '' check (char_length(event_note) <= 1000),
    occurred_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    constraint bizkipe_campaign_event_owner_match foreign key (campaign_id, user_id) references public.bizkipe_customer_campaigns(id, user_id) on delete cascade
  );
  create index if not exists bizkipe_campaign_events_owner_date_idx on public.bizkipe_campaign_engagement_events(user_id, occurred_at desc);
  create index if not exists bizkipe_campaign_events_campaign_idx on public.bizkipe_campaign_engagement_events(campaign_id, occurred_at desc);
  alter table public.bizkipe_campaign_engagement_events enable row level security;
  drop policy if exists "Users manage own BizKipe campaign engagement events" on public.bizkipe_campaign_engagement_events;
  create policy "Users manage own BizKipe campaign engagement events" on public.bizkipe_campaign_engagement_events for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
  revoke all on table public.bizkipe_campaign_engagement_events from anon;
  grant select, insert, update, delete on public.bizkipe_campaign_engagement_events to authenticated;
end
$fn$;
