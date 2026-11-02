-- BizKipe v4.3: recurring invoice schedules and controlled numbering.
-- Run after customer-dashboard-schema.sql. Uses authenticated Supabase sessions and RLS.
-- "Due" is judged by the Nairobi calendar date (East Africa Time).
create table if not exists public.bizkipe_recurring_schedules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  template_document_id uuid not null references public.saved_documents(id) on delete cascade,
  schedule_name text not null check (char_length(schedule_name) between 1 and 100),
  frequency text not null check (frequency in ('weekly','monthly','quarterly','yearly')),
  next_run_date date not null,
  first_run_date date null,
  due_days integer not null default 14 check (due_days between 0 and 365),
  number_prefix text not null default 'BK-REC-' check (char_length(number_prefix) between 1 and 24),
  next_number integer not null default 1 check (next_number > 0),
  status text not null default 'active' check (status in ('active','paused')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint recurring_template_owner check (user_id is not null)
);
create index if not exists bizkipe_recurring_user_next_idx
  on public.bizkipe_recurring_schedules(user_id, status, next_run_date);
alter table public.bizkipe_recurring_schedules enable row level security;
drop policy if exists "Users manage own recurring schedules" on public.bizkipe_recurring_schedules;
create policy "Users manage own recurring schedules" on public.bizkipe_recurring_schedules
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
revoke all on public.bizkipe_recurring_schedules from anon;
grant select, insert, update, delete on public.bizkipe_recurring_schedules to authenticated;

-- Atomic generation: creates a draft invoice and advances its schedule in one transaction.
create or replace function public.bizkipe_generate_recurring_invoice(p_schedule_id uuid)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  s public.bizkipe_recurring_schedules%rowtype;
  t public.saved_documents%rowtype;
  new_id uuid;
  next_date date;
  doc_no text;
  due_date_value date;
  doc_data jsonb;
  anchor_day integer;
  step_months integer;
  target_start date;
  target_days integer;
begin
  select * into s from public.bizkipe_recurring_schedules
   where id = p_schedule_id and user_id = auth.uid() for update;
  if not found then raise exception 'Schedule not found or access denied'; end if;
  if s.status <> 'active' then raise exception 'This schedule is paused'; end if;
  if s.next_run_date > (now() at time zone 'Africa/Nairobi')::date then raise exception 'This invoice is not due to be generated yet'; end if;
  select * into t from public.saved_documents
   where id = s.template_document_id and user_id = auth.uid() and doc_type = 'invoice';
  if not found then raise exception 'The source invoice template is unavailable'; end if;

  doc_no := s.number_prefix || to_char(s.next_run_date, 'YYYY') || '-' || lpad(s.next_number::text, greatest(4, length(s.next_number::text)), '0');
  due_date_value := s.next_run_date + s.due_days;
  doc_data := coalesce(t.document_data, '{}'::jsonb) || jsonb_build_object(
    'docType','invoice','documentNumber',doc_no,
    'issueDate',s.next_run_date,'dueDate',due_date_value,
    'recurringScheduleId',s.id,'recurrenceDate',s.next_run_date
  );
  insert into public.saved_documents (
    user_id, doc_type, document_number, title, client_name, client_email,
    issue_date, due_date, currency, subtotal, discount, tax_rate, total,
    status, document_data
  ) values (
    auth.uid(), 'invoice', doc_no, 'Invoice ' || doc_no, t.client_name, t.client_email,
    s.next_run_date, due_date_value, t.currency, t.subtotal, t.discount, t.tax_rate,
    t.total, 'draft', doc_data
  ) returning id into new_id;

  -- Keep the original day of the month (e.g. the 31st), using each month's last day when it is shorter.
  if s.frequency = 'weekly' then
    next_date := s.next_run_date + 7;
  else
    anchor_day := extract(day from coalesce(s.first_run_date, s.next_run_date))::integer;
    step_months := case s.frequency when 'monthly' then 1 when 'quarterly' then 3 else 12 end;
    target_start := (date_trunc('month', s.next_run_date) + make_interval(months => step_months))::date;
    target_days := extract(day from (target_start + interval '1 month' - interval '1 day'))::integer;
    next_date := target_start + (least(anchor_day, target_days) - 1);
  end if;
  update public.bizkipe_recurring_schedules
     set next_run_date = next_date, next_number = next_number + 1, updated_at = now()
   where id = s.id and user_id = auth.uid();
  return new_id;
end;
$$;
revoke all on function public.bizkipe_generate_recurring_invoice(uuid) from public, anon;
grant execute on function public.bizkipe_generate_recurring_invoice(uuid) to authenticated;
