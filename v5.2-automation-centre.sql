-- BizKipe v5.2 — Automation Centre
-- Run once in the Supabase SQL Editor, after v3.6-customer-followups.sql.
-- Lets scheduled tasks use the "Internal task" action type. Existing rows are unchanged.
alter table public.bizkipe_customer_followups
  drop constraint if exists bizkipe_customer_followups_channel_check;
alter table public.bizkipe_customer_followups
  add constraint bizkipe_customer_followups_channel_check
  check (channel in ('WhatsApp','Email','Phone call','In person','Internal task','Other'));
