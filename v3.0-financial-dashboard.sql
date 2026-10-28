-- BizKipe v3.0 Financial Dashboard
-- Run in Supabase SQL Editor after the existing BizKipe migrations.
-- This stores user-entered records only; it does NOT verify M-Pesa or any payment provider.
create table if not exists public.bizkipe_financial_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  entry_type text not null check (entry_type in ('sale','expense')),
  description text not null check (length(trim(description)) between 1 and 160),
  reference text null check (reference is null or length(reference) <= 100),
  customer_or_payee text null check (customer_or_payee is null or length(customer_or_payee) <= 120),
  amount numeric(14,2) not null check (amount > 0),
  amount_received numeric(14,2) not null default 0 check (amount_received >= 0 and amount_received <= amount),
  cost_amount numeric(14,2) not null default 0 check (cost_amount >= 0),
  currency text not null default 'KES' check (currency in ('KES','USD','EUR','GBP')),
  payment_status text not null default 'not_applicable' check (payment_status in ('unpaid','partial','paid','not_applicable')),
  entry_date date not null default current_date,
  created_at timestamptz not null default now(),
  constraint bizkipe_financial_entry_rules check (
    (entry_type = 'sale' and payment_status in ('unpaid','partial','paid') and cost_amount >= 0)
    or (entry_type = 'expense' and payment_status = 'not_applicable' and amount_received = 0 and cost_amount = 0)
  )
);
create index if not exists bizkipe_financial_entries_user_date_idx
  on public.bizkipe_financial_entries (user_id, entry_date desc, created_at desc);
create index if not exists bizkipe_financial_entries_user_type_idx
  on public.bizkipe_financial_entries (user_id, entry_type, currency);
alter table public.bizkipe_financial_entries enable row level security;
drop policy if exists "Users can read own BizKipe financial entries" on public.bizkipe_financial_entries;
create policy "Users can read own BizKipe financial entries" on public.bizkipe_financial_entries for select to authenticated using (auth.uid() = user_id);
drop policy if exists "Users can insert own BizKipe financial entries" on public.bizkipe_financial_entries;
create policy "Users can insert own BizKipe financial entries" on public.bizkipe_financial_entries for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Users can update own BizKipe financial entries" on public.bizkipe_financial_entries;
create policy "Users can update own BizKipe financial entries" on public.bizkipe_financial_entries for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "Users can delete own BizKipe financial entries" on public.bizkipe_financial_entries;
create policy "Users can delete own BizKipe financial entries" on public.bizkipe_financial_entries for delete to authenticated using (auth.uid() = user_id);
grant select, insert, update, delete on public.bizkipe_financial_entries to authenticated;
