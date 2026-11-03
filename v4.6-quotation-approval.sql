-- BizKipe v4.6 Online Quotation Approval and Customer Sign-off
-- Run after customer-dashboard-schema.sql and v4.4-customer-billing-portal.sql.
-- Security: the link table is closed to the public; only the owner manages links. The public page can call
-- TWO functions, and both need the secret link. A response is recorded once, with the total the customer saw.
create extension if not exists pgcrypto;
create unique index if not exists saved_documents_id_user_unique on public.saved_documents(id,user_id);
create table if not exists public.bizkipe_quote_approval_links (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  saved_document_id uuid not null,
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  expires_at timestamptz,
  revoked_at timestamptz,
  decision text not null default 'pending' check (decision in ('pending','accepted','rejected')),
  customer_note text not null default '',
  decided_at timestamptz,
  decided_total numeric(14,2),
  decided_currency text,
  view_count integer not null default 0 check (view_count >= 0),
  last_viewed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint bizkipe_quote_approval_doc_fk foreign key(saved_document_id,user_id)
    references public.saved_documents(id,user_id) on delete cascade
);
create index if not exists bizkipe_quote_approval_owner_idx
  on public.bizkipe_quote_approval_links(user_id,created_at desc);
alter table public.bizkipe_quote_approval_links enable row level security;
drop policy if exists "Owners manage own quotation approval links" on public.bizkipe_quote_approval_links;
create policy "Owners manage own quotation approval links" on public.bizkipe_quote_approval_links
  for all to authenticated using (auth.uid()=user_id) with check (auth.uid()=user_id);
revoke all on public.bizkipe_quote_approval_links from anon;
grant select,insert,update,delete on public.bizkipe_quote_approval_links to authenticated;
create or replace function public.bizkipe_public_quote(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $fn$
declare s public.bizkipe_quote_approval_links%rowtype; d public.saved_documents%rowtype;
begin
 if p_token is null or length(p_token)<40 or length(p_token)>128 then
  return jsonb_build_object('ok',false,'message','This quotation link is invalid or unavailable.'); end if;
 select * into s from public.bizkipe_quote_approval_links where token_hash=encode(digest(p_token,'sha256'),'hex')
  and revoked_at is null and (expires_at is null or expires_at>now());
 if not found then return jsonb_build_object('ok',false,'message','This quotation link has expired or is no longer available.'); end if;
 select * into d from public.saved_documents where id=s.saved_document_id and user_id=s.user_id and doc_type='quote';
 if not found then return jsonb_build_object('ok',false,'message','Quotation unavailable.'); end if;
 update public.bizkipe_quote_approval_links set view_count=view_count+1,last_viewed_at=now() where id=s.id;
 return jsonb_build_object('ok',true,'decision',s.decision,'customer_note',s.customer_note,'decided_at',s.decided_at,
  'quote',jsonb_build_object('document_number',d.document_number,'title',d.title,'client_name',d.client_name,
   'issue_date',d.issue_date,'due_date',d.due_date,'currency',d.currency,'subtotal',d.subtotal,'discount',d.discount,
   'tax_rate',d.tax_rate,'total',d.total,'status',d.status,'items',coalesce(d.document_data->'items','[]'::jsonb),
   'notes',coalesce(d.document_data->>'notes',''),'business_name',coalesce(d.document_data->>'businessName','BizKipe business'),
   'business_address',coalesce(d.document_data->>'businessAddress',''),'business_email',coalesce(d.document_data->>'businessEmail',''),
   'business_phone',coalesce(d.document_data->>'businessPhone','')));
end; $fn$;
create or replace function public.bizkipe_submit_quote_decision(p_token text,p_decision text,p_customer_note text default '',p_seen_total numeric default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $fn$
declare s public.bizkipe_quote_approval_links%rowtype; d public.saved_documents%rowtype;
begin
 if p_token is null or length(p_token)<40 or length(p_token)>128 then return jsonb_build_object('ok',false,'message','Invalid quotation link.'); end if;
 if p_decision is null or p_decision not in ('accepted','rejected') then return jsonb_build_object('ok',false,'message','Choose accept or reject.'); end if;
 if length(coalesce(p_customer_note,''))>1000 then return jsonb_build_object('ok',false,'message','Your note is too long.'); end if;
 select * into s from public.bizkipe_quote_approval_links where token_hash=encode(digest(p_token,'sha256'),'hex')
  and revoked_at is null and (expires_at is null or expires_at>now()) for update;
 if not found then return jsonb_build_object('ok',false,'message','This quotation link has expired or is unavailable.'); end if;
 if s.decision<>'pending' then return jsonb_build_object('ok',false,'message','A response has already been recorded for this quotation.'); end if;
 select * into d from public.saved_documents where id=s.saved_document_id and user_id=s.user_id and doc_type='quote';
 if not found then return jsonb_build_object('ok',false,'message','Quotation unavailable.'); end if;
 if p_seen_total is not null and abs(d.total-p_seen_total)>0.005 then
  return jsonb_build_object('ok',false,'message','This quotation was updated while you were reviewing it. Please reload the page and review it again before responding.'); end if;
 update public.bizkipe_quote_approval_links set decision=p_decision,customer_note=trim(coalesce(p_customer_note,'')),
  decided_at=now(),decided_total=d.total,decided_currency=d.currency where id=s.id;
 return jsonb_build_object('ok',true,'decision',p_decision,'message','Your response has been recorded.');
end; $fn$;
revoke all on function public.bizkipe_public_quote(text) from public;
revoke all on function public.bizkipe_submit_quote_decision(text,text,text,numeric) from public;
grant execute on function public.bizkipe_public_quote(text) to anon,authenticated;
grant execute on function public.bizkipe_submit_quote_decision(text,text,text,numeric) to anon,authenticated;
