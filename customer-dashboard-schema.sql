-- BizKipe Customer Dashboard / Saved Documents (additive migration)
-- Run this in Supabase SQL Editor. It does not modify orders, Daraja, or Storage.
create extension if not exists pgcrypto;
create table if not exists public.saved_documents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  doc_type text not null default 'invoice' check (doc_type in ('invoice','quote')),
  document_number text not null default '',
  title text not null default 'Untitled document',
  client_name text not null default '',
  client_email text not null default '',
  issue_date date,
  due_date date,
  currency text not null default 'KES' check (currency in ('KES','USD','GBP','EUR')),
  subtotal numeric(12,2) not null default 0 check (subtotal >= 0),
  discount numeric(12,2) not null default 0 check (discount >= 0),
  tax_rate numeric(5,2) not null default 0 check (tax_rate >= 0 and tax_rate <= 100),
  total numeric(12,2) not null default 0 check (total >= 0),
  status text not null default 'draft' check (status in ('draft','sent','paid','overdue','accepted','declined')),
  document_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists saved_documents_user_updated_idx on public.saved_documents (user_id, updated_at desc);
create index if not exists saved_documents_user_client_idx on public.saved_documents (user_id, client_name);
alter table public.saved_documents enable row level security;
drop policy if exists "Users can read own saved documents" on public.saved_documents;
create policy "Users can read own saved documents" on public.saved_documents for select to authenticated using (auth.uid() = user_id);
drop policy if exists "Users can create own saved documents" on public.saved_documents;
create policy "Users can create own saved documents" on public.saved_documents for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Users can update own saved documents" on public.saved_documents;
create policy "Users can update own saved documents" on public.saved_documents for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "Users can delete own saved documents" on public.saved_documents;
create policy "Users can delete own saved documents" on public.saved_documents for delete to authenticated using (auth.uid() = user_id);

-- Grant table operations only to authenticated users; RLS still limits each row to its owner.
revoke all on table public.saved_documents from anon;
grant select, insert, update, delete on table public.saved_documents to authenticated;
