-- BizKipe v4.5 Customer Self-Service Portal
-- Run after customer-dashboard-schema.sql, v1.5-payment-tracking.sql and v4.4-customer-billing-portal.sql.
-- Security: the table is closed to the public; only the owner can manage links. The public page can call
-- ONE function, which needs the secret link and returns only this customer's non-draft invoices and quotations.
-- Customers receive read-only access through a high-entropy private link shared manually by the business.
create extension if not exists pgcrypto;

create table if not exists public.bizkipe_customer_portal_links (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  customer_email text not null check (char_length(customer_email) between 3 and 254),
  customer_name text not null default '',
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  expires_at timestamptz,
  revoked_at timestamptz,
  view_count integer not null default 0 check (view_count >= 0),
  last_viewed_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists bizkipe_customer_portal_owner_idx
  on public.bizkipe_customer_portal_links(user_id,created_at desc);
create index if not exists bizkipe_customer_portal_email_idx
  on public.bizkipe_customer_portal_links(user_id,lower(customer_email));

alter table public.bizkipe_customer_portal_links enable row level security;
drop policy if exists "Owners manage own customer portal links" on public.bizkipe_customer_portal_links;
create policy "Owners manage own customer portal links" on public.bizkipe_customer_portal_links
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
revoke all on public.bizkipe_customer_portal_links from anon;
grant select,insert,update,delete on public.bizkipe_customer_portal_links to authenticated;

create or replace function public.bizkipe_customer_portal(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $fn$
declare
  portal public.bizkipe_customer_portal_links%rowtype;
  docs jsonb;
begin
  if p_token is null or length(p_token) < 40 or length(p_token) > 128 then
    return jsonb_build_object('ok',false,'message','This customer portal link is invalid or unavailable.');
  end if;
  select * into portal from public.bizkipe_customer_portal_links
   where token_hash = encode(digest(p_token,'sha256'),'hex')
     and revoked_at is null and (expires_at is null or expires_at > now());
  if not found then
    return jsonb_build_object('ok',false,'message','This customer portal link has expired or is no longer available.');
  end if;
  with base as (
    select d.*,
      case when d.doc_type='invoice' then greatest(
        coalesce((select sum(p.amount) from public.document_payments p where p.saved_document_id=d.id and p.user_id=d.user_id),0),
        coalesce((select sum(f.amount_received) from public.bizkipe_financial_entries f where f.source_document_id=d.id and f.user_id=d.user_id and f.entry_type='sale'),0)
      ) else 0 end as paid
    from public.saved_documents d
    where d.user_id=portal.user_id
      and lower(trim(d.client_email))=lower(trim(portal.customer_email))
      and d.doc_type in ('invoice','quote')
      and d.status <> 'draft'
    order by d.issue_date desc nulls last, d.created_at desc
    limit 200
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',b.id,'doc_type',b.doc_type,'document_number',b.document_number,'title',b.title,
    'issue_date',b.issue_date,'due_date',b.due_date,'currency',b.currency,
    'subtotal',b.subtotal,'discount',b.discount,'tax_rate',b.tax_rate,'total',b.total,
    'status',b.status,'items',coalesce(b.document_data->'items','[]'::jsonb),
    'notes',coalesce(b.document_data->>'notes',''),
    'business_name',coalesce(b.document_data->>'businessName','BizKipe business'),
    'business_email',coalesce(b.document_data->>'businessEmail',''),
    'business_phone',coalesce(b.document_data->>'businessPhone',''),
    'amount_paid',b.paid,
    'balance',case when b.doc_type='invoice' then greatest(0,b.total-b.paid) else 0 end,
    'payment_state',case when b.doc_type<>'invoice' then null
      when b.paid >= b.total and b.total > 0 then 'Paid'
      when b.paid > 0 then 'Partially paid'
      when b.due_date < (now() at time zone 'Africa/Nairobi')::date then 'Overdue'
      else 'Unpaid' end
  ) order by b.issue_date desc nulls last, b.created_at desc),'[]'::jsonb)
  into docs from base b;

  update public.bizkipe_customer_portal_links
    set view_count=view_count+1,last_viewed_at=now() where id=portal.id;
  return jsonb_build_object('ok',true,'customer_name',portal.customer_name,
    'customer_email',portal.customer_email,'documents',docs);
end;
$fn$;
revoke all on function public.bizkipe_customer_portal(text) from public;
grant execute on function public.bizkipe_customer_portal(text) to anon, authenticated;
