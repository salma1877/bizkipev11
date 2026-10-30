-- BizKipe v3.2 — individual payment records
-- Run after v3.0-financial-dashboard.sql and v3.1-invoice-finance-integration.sql.
-- Payments are user-entered records; this does NOT verify provider transactions.

create table if not exists public.bizkipe_financial_payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  financial_entry_id uuid not null references public.bizkipe_financial_entries(id) on delete cascade,
  amount numeric(14,2) not null check (amount > 0),
  payment_method text not null check (length(trim(payment_method)) between 1 and 40),
  payment_reference text null check (payment_reference is null or length(trim(payment_reference)) between 1 and 120),
  payment_date date not null default current_date,
  notes text null check (notes is null or length(notes) <= 300),
  created_at timestamptz not null default now(),
  constraint bizkipe_financial_payments_reference_unique unique (user_id, payment_reference)
);
create index if not exists bizkipe_financial_payments_entry_date_idx
  on public.bizkipe_financial_payments (user_id, financial_entry_id, payment_date desc, created_at desc);

alter table public.bizkipe_financial_payments enable row level security;
drop policy if exists "Users can read own BizKipe financial payments" on public.bizkipe_financial_payments;
create policy "Users can read own BizKipe financial payments" on public.bizkipe_financial_payments
  for select to authenticated using (auth.uid() = user_id);
-- Writes are performed through the atomic function below, not direct table inserts/updates.
grant select on public.bizkipe_financial_payments to authenticated;
revoke insert, update, delete on public.bizkipe_financial_payments from anon, authenticated;

create or replace function public.bizkipe_record_financial_payment(
  p_financial_entry_id uuid,
  p_amount numeric,
  p_payment_method text,
  p_payment_reference text default null,
  p_payment_date date default current_date,
  p_notes text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_entry public.bizkipe_financial_entries%rowtype;
  v_payment public.bizkipe_financial_payments%rowtype;
  v_reference text := nullif(trim(p_payment_reference), '');
  v_method text := trim(coalesce(p_payment_method, ''));
  v_received numeric(14,2);
  v_status text;
begin
  if v_user_id is null then raise exception 'Sign in to record a payment.'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Payment amount must be greater than zero.'; end if;
  if length(v_method) < 1 or length(v_method) > 40 then raise exception 'Payment method must be 1–40 characters.'; end if;
  if v_reference is not null and length(v_reference) > 120 then raise exception 'Payment reference is too long.'; end if;
  if p_notes is not null and length(p_notes) > 300 then raise exception 'Notes are limited to 300 characters.'; end if;

  -- Lock the owned sale row so two simultaneous receipts cannot exceed the balance.
  select * into v_entry from public.bizkipe_financial_entries
    where id = p_financial_entry_id and user_id = v_user_id and entry_type = 'sale'
    for update;
  if not found then raise exception 'Sale entry not found for this account.'; end if;

  -- An already-used provider/receipt reference is treated as a duplicate, not another receipt.
  if v_reference is not null then
    select * into v_payment from public.bizkipe_financial_payments
      where user_id = v_user_id and payment_reference = v_reference;
    if found then
      if v_payment.financial_entry_id = p_financial_entry_id and v_payment.amount = p_amount then
        return jsonb_build_object('duplicate', true, 'payment_id', v_payment.id,
          'amount_received', v_entry.amount_received, 'payment_status', v_entry.payment_status);
      end if;
      raise exception 'That payment reference has already been used. Check the receipt reference before retrying.';
    end if;
  end if;

  v_received := coalesce(v_entry.amount_received, 0);
  if v_received + p_amount > v_entry.amount then
    raise exception 'Payment exceeds the remaining balance (%).', (v_entry.amount - v_received);
  end if;

  insert into public.bizkipe_financial_payments
    (user_id, financial_entry_id, amount, payment_method, payment_reference, payment_date, notes)
  values (v_user_id, p_financial_entry_id, p_amount, v_method, v_reference,
    coalesce(p_payment_date, current_date), p_notes)
  returning * into v_payment;

  v_received := v_received + p_amount;
  v_status := case when v_received >= v_entry.amount then 'paid'
                   when v_received > 0 then 'partial' else 'unpaid' end;
  update public.bizkipe_financial_entries
    set amount_received = v_received, payment_status = v_status
    where id = v_entry.id and user_id = v_user_id;

  return jsonb_build_object('duplicate', false, 'payment_id', v_payment.id,
    'amount_received', v_received, 'payment_status', v_status,
    'remaining_balance', v_entry.amount - v_received);
end;
$$;
revoke all on function public.bizkipe_record_financial_payment(uuid, numeric, text, text, date, text) from public, anon;
grant execute on function public.bizkipe_record_financial_payment(uuid, numeric, text, text, date, text) to authenticated;
