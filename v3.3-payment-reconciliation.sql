-- BizKipe v3.3 — payment reconciliation and printable receipt support
-- Run AFTER v3.2-payment-record-management.sql.
-- Reconciliation is a manual bookkeeping flag; it does not query or verify M-Pesa/bank providers.

alter table public.bizkipe_financial_payments
  add column if not exists reconciled_at timestamptz null,
  add column if not exists reconciliation_note text null
    check (reconciliation_note is null or length(reconciliation_note) <= 300);

create or replace function public.bizkipe_reconcile_financial_payment(
  p_payment_id uuid,
  p_note text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_payment public.bizkipe_financial_payments%rowtype;
begin
  if v_user_id is null then raise exception 'Sign in to reconcile a payment.'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'Reconciliation note is limited to 300 characters.'; end if;
  select * into v_payment
    from public.bizkipe_financial_payments
    where id = p_payment_id and user_id = v_user_id
    for update;
  if not found then raise exception 'Payment record not found for this account.'; end if;
  if v_payment.reconciled_at is not null then
    return jsonb_build_object('already_reconciled', true, 'reconciled_at', v_payment.reconciled_at);
  end if;
  update public.bizkipe_financial_payments
    set reconciled_at = now(), reconciliation_note = nullif(trim(p_note), '')
    where id = p_payment_id and user_id = v_user_id;
  return jsonb_build_object('already_reconciled', false, 'reconciled_at', now());
end;
$$;

revoke all on function public.bizkipe_reconcile_financial_payment(uuid, text) from public, anon;
grant execute on function public.bizkipe_reconcile_financial_payment(uuid, text) to authenticated;
