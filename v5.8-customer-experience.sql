-- BizKipe v5.8 — Customer Experience Centre
-- Additive and safe to run more than once.
-- Stores feedback summaries entered by the business and internal service issue records.
do $fn$
begin
  create table if not exists public.bizkipe_customer_feedback (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    customer_name text check (customer_name is null or char_length(customer_name) <= 120),
    customer_email text check (customer_email is null or char_length(customer_email) <= 254),
    rating smallint not null check (rating between 1 and 5),
    category text not null check (category in ('Product or service','Communication','Delivery','Billing','Support','Other')),
    feedback text not null check (char_length(trim(feedback)) between 1 and 3000),
    received_on date not null default current_date,
    created_at timestamptz not null default now()
  );
  create table if not exists public.bizkipe_customer_issues (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    title text not null check (char_length(trim(title)) between 1 and 160),
    customer_name text check (customer_name is null or char_length(customer_name) <= 120),
    customer_email text check (customer_email is null or char_length(customer_email) <= 254),
    category text not null check (category in ('Product or service','Communication','Delivery','Billing','Support','Other')),
    priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
    description text not null check (char_length(trim(description)) between 1 and 3000),
    status text not null default 'open' check (status in ('open','in_progress','resolved','closed')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
  );
  alter table public.bizkipe_customer_feedback enable row level security;
  alter table public.bizkipe_customer_issues enable row level security;
  drop policy if exists "Users manage own customer feedback" on public.bizkipe_customer_feedback;
  create policy "Users manage own customer feedback" on public.bizkipe_customer_feedback for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
  drop policy if exists "Users manage own customer issues" on public.bizkipe_customer_issues;
  create policy "Users manage own customer issues" on public.bizkipe_customer_issues for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
  revoke all on table public.bizkipe_customer_feedback from anon;
  revoke all on table public.bizkipe_customer_issues from anon;
  grant select, insert, update, delete on table public.bizkipe_customer_feedback to authenticated;
  grant select, insert, update, delete on table public.bizkipe_customer_issues to authenticated;
  create index if not exists bizkipe_customer_feedback_user_received_idx on public.bizkipe_customer_feedback(user_id, received_on desc);
  create index if not exists bizkipe_customer_issues_user_status_idx on public.bizkipe_customer_issues(user_id, status, created_at desc);
end
$fn$;
