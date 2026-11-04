-- BizKipe v4.7 Quotation-to-Invoice Conversion and Sales Pipeline
-- Run after v4.6-quotation-approval.sql and all earlier BizKipe migrations.
-- Conversion is owner-only (signed in), transactional and happens once per approval link.
-- It is refused if the quotation was changed after the customer accepted it.
alter table public.bizkipe_quote_approval_links
  add column if not exists converted_invoice_id uuid null,
  add column if not exists converted_at timestamptz null;
alter table public.bizkipe_quote_approval_links
  drop constraint if exists bizkipe_quote_approval_converted_invoice_fk;
alter table public.bizkipe_quote_approval_links
  add constraint bizkipe_quote_approval_converted_invoice_fk
  foreign key (converted_invoice_id) references public.saved_documents(id) on delete set null;
create unique index if not exists bizkipe_quote_approval_converted_invoice_uidx
  on public.bizkipe_quote_approval_links(converted_invoice_id)
  where converted_invoice_id is not null;
create or replace function public.bizkipe_convert_accepted_quote(p_approval_link_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $fn$
declare
  v_link public.bizkipe_quote_approval_links%rowtype;
  v_quote public.saved_documents%rowtype;
  v_invoice_id uuid;
  v_number text;
  v_base text;
  v_today date;
  v_notes text;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'message', 'Sign in to convert this quotation.');
  end if;
  select * into v_link from public.bizkipe_quote_approval_links
   where id = p_approval_link_id and user_id = auth.uid() for update;
  if not found then
    return jsonb_build_object('ok', false, 'message', 'Quotation approval record not found.');
  end if;
  if v_link.decision <> 'accepted' then
    return jsonb_build_object('ok', false, 'message', 'Only customer-accepted quotations can be converted.');
  end if;
  if v_link.converted_invoice_id is not null then
    return jsonb_build_object('ok', true, 'already_converted', true,
      'invoice_id', v_link.converted_invoice_id, 'message', 'This quotation has already been converted.');
  end if;
  select * into v_quote from public.saved_documents
   where id = v_link.saved_document_id and user_id = auth.uid() and doc_type = 'quote' for share;
  if not found then
    return jsonb_build_object('ok', false, 'message', 'The original quotation could not be found.');
  end if;
  if v_link.decided_total is not null and abs(v_quote.total - v_link.decided_total) > 0.005 then
    return jsonb_build_object('ok', false, 'message', 'This quotation was changed after the customer accepted it. Ask the customer to review the updated quotation before converting.');
  end if;
  v_today := (now() at time zone 'Africa/Nairobi')::date;
  v_invoice_id := gen_random_uuid();
  v_base := 'INV-' || coalesce(nullif(left(regexp_replace(coalesce(v_quote.document_number, ''), '[^a-zA-Z0-9-]', '', 'g'), 30), ''), 'QUOTE');
  v_number := v_base;
  if exists (select 1 from public.saved_documents where user_id = auth.uid() and doc_type = 'invoice' and document_number = v_number) then
    v_number := v_base || '-' || upper(substr(replace(v_invoice_id::text, '-', ''), 1, 4));
  end if;
  v_notes := 'Invoice created from quotation ' || coalesce(v_quote.document_number, '') || '. ' || coalesce(v_quote.document_data->>'notes', '');
  insert into public.saved_documents (
    id, user_id, doc_type, document_number, title, client_name, client_email,
    issue_date, due_date, currency, subtotal, discount, tax_rate, total,
    status, document_data, created_at, updated_at
  ) values (
    v_invoice_id, auth.uid(), 'invoice', v_number,
    coalesce(nullif(v_quote.title, ''), 'Invoice from quotation'),
    v_quote.client_name, v_quote.client_email, v_today, null,
    v_quote.currency, v_quote.subtotal, v_quote.discount, v_quote.tax_rate,
    v_quote.total, 'draft',
    coalesce(v_quote.document_data, '{}'::jsonb) || jsonb_build_object(
      'docType', 'invoice',
      'documentNumber', v_number,
      'issueDate', v_today,
      'dueDate', null::text,
      'notes', v_notes,
      'convertedFromQuoteId', v_quote.id,
      'convertedFromQuoteNumber', v_quote.document_number,
      'convertedAt', now()
    ), now(), now()
  );
  update public.bizkipe_quote_approval_links
     set converted_invoice_id = v_invoice_id, converted_at = now()
   where id = v_link.id and user_id = auth.uid();
  update public.saved_documents set status = 'accepted', updated_at = now()
   where id = v_quote.id and user_id = auth.uid();
  return jsonb_build_object('ok', true, 'invoice_id', v_invoice_id,
    'invoice_number', v_number, 'message', 'Accepted quotation converted into a draft invoice.');
end;
$fn$;
revoke all on function public.bizkipe_convert_accepted_quote(uuid) from public, anon;
grant execute on function public.bizkipe_convert_accepted_quote(uuid) to authenticated;
