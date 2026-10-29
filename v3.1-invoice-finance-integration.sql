-- BizKipe v3.1 Invoice-to-Finance Integration
-- Run after customer-dashboard-schema.sql and v3.0-financial-dashboard.sql.
-- A saved invoice can link to at most one financial entry per owner.
-- This does not verify payment or automatically deduct inventory.

alter table public.bizkipe_financial_entries
  add column if not exists source_document_id uuid null
  references public.saved_documents(id) on delete set null;

create unique index if not exists bizkipe_financial_entries_user_source_document_uidx
  on public.bizkipe_financial_entries (user_id, source_document_id)
  where source_document_id is not null;

create index if not exists bizkipe_financial_entries_user_source_document_idx
  on public.bizkipe_financial_entries (user_id, source_document_id);

-- Existing v3.0 RLS policies continue to protect financial entries by user_id.
-- The browser client only writes rows for the signed-in user and verifies invoice ownership.
