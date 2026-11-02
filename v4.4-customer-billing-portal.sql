-- BizKipe v4.4: customer-facing invoice links and billing status workspace.
-- Run after customer-dashboard-schema.sql, v1.5-payment-tracking.sql and v3.1-invoice-finance-integration.sql.
create extension if not exists pgcrypto;

-- PostgreSQL requires the referenced composite key before creating the foreign key.
create unique index if not exists saved_documents_id_user_unique on public.saved_documents(id,user_id);

create table if not exists public.bizkipe_invoice_shares (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  saved_document_id uuid not null references public.saved_documents(id) on delete cascade,
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  expires_at timestamptz,
  revoked_at timestamptz,
  view_count integer not null default 0 check (view_count >= 0),
  last_viewed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint invoice_share_owner_fk foreign key (saved_document_id, user_id)
    references public.saved_documents(id, user_id) on delete cascade
);
create index if not exists bizkipe_invoice_shares_owner_doc_idx
  on public.bizkipe_invoice_shares(user_id,saved_document_id,created_at desc);

alter table public.bizkipe_invoice_shares enable row level security;
drop policy if exists "Owners manage own invoice shares" on public.bizkipe_invoice_shares;
create policy "Owners manage own invoice shares" on public.bizkipe_invoice_shares
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
revoke all on public.bizkipe_invoice_shares from anon;
grant select,insert,update,delete on public.bizkipe_invoice_shares to authenticated;

-- Public function returns only the fields needed to display an invoice. Raw tokens are
-- never stored; only their SHA-256 hashes are saved. No payment references are exposed.
create or replace function public.bizkipe_public_invoice(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $fn$
declare
  s public.bizkipe_invoice_shares%rowtype;
  d public.saved_documents%rowtype;
  paid numeric(12,2);
  ledger_paid numeric(14,2);
  result jsonb;
begin
  if p_token is null or length(p_token) < 40 or length(p_token) > 128 then
    return jsonb_build_object('ok',false,'message','This invoice link is invalid or unavailable.');
  end if;
  select * into s from public.bizkipe_invoice_shares
    where token_hash = encode(digest(p_token,'sha256'),'hex')
      and revoked_at is null and (expires_at is null or expires_at > now());
  if not found then
    return jsonb_build_object('ok',false,'message','This invoice link has expired or is no longer available.');
  end if;
  select * into d from public.saved_documents
    where id=s.saved_document_id and user_id=s.user_id and doc_type='invoice';
  if not found then return jsonb_build_object('ok',false,'message','Invoice unavailable.'); end if;
  select coalesce(sum(amount),0) into paid from public.document_payments
    where saved_document_id=d.id and user_id=d.user_id;
  -- Payments recorded in the Financial dashboard also count (the larger figure is used, never both).
  select coalesce(sum(amount_received),0) into ledger_paid from public.bizkipe_financial_entries
    where source_document_id=d.id and user_id=d.user_id and entry_type='sale';
  paid := greatest(paid, ledger_paid);
  update public.bizkipe_invoice_shares set view_count=view_count+1,last_viewed_at=now() where id=s.id;
  result := jsonb_build_object(
    'ok',true,
    'invoice',jsonb_build_object(
      'document_number',d.document_number,'title',d.title,'client_name',d.client_name,
      'client_email',d.client_email,'issue_date',d.issue_date,'due_date',d.due_date,
      'currency',d.currency,'subtotal',d.subtotal,'discount',d.discount,
      'tax_rate',d.tax_rate,'total',d.total,'status',d.status,
      'items',coalesce(d.document_data->'items','[]'::jsonb),
      'business_name',coalesce(d.document_data->>'businessName','BizKipe business'),
      'business_address',coalesce(d.document_data->>'businessAddress',''),
      'business_email',coalesce(d.document_data->>'businessEmail',''),
      'business_phone',coalesce(d.document_data->>'businessPhone',''),
      'notes',coalesce(d.document_data->>'notes',''),
      'amount_paid',paid,'balance',greatest(0,d.total-paid),
      'payment_state',case when paid >= d.total and d.total > 0 then 'paid' when paid > 0 then 'partially paid' when d.due_date < (now() at time zone 'Africa/Nairobi')::date then 'overdue' else 'unpaid' end
    )
  );
  return result;
end;
$fn$;
revoke all on function public.bizkipe_public_invoice(text) from public;
grant execute on function public.bizkipe_public_invoice(text) to anon, authenticated;
