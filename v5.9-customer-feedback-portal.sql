-- BizKipe v5.9 — Customer Feedback Portal
-- Run after v5.8-customer-experience.sql. Additive, owner-scoped, safe to run more than once.
-- Public visitors can only submit through bizkipe_submit_customer_feedback(); they cannot read any table.
-- Each link is rate-limited on the server (15 per hour, 100 per day) to limit spam.
do $fn$
begin
  create table if not exists public.bizkipe_feedback_portal_links (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    token uuid not null unique default gen_random_uuid(),
    title text not null default 'Customer feedback' check (char_length(trim(title)) between 1 and 100),
    enabled boolean not null default true,
    expires_at timestamptz,
    created_at timestamptz not null default now()
  );
  create index if not exists bizkipe_feedback_portal_links_user_created_idx on public.bizkipe_feedback_portal_links(user_id, created_at desc);
  alter table public.bizkipe_feedback_portal_links enable row level security;
  drop policy if exists "Owners manage own feedback portal links" on public.bizkipe_feedback_portal_links;
  create policy "Owners manage own feedback portal links" on public.bizkipe_feedback_portal_links for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
  revoke all on table public.bizkipe_feedback_portal_links from anon;
  grant select, insert, update, delete on table public.bizkipe_feedback_portal_links to authenticated;
  create table if not exists public.bizkipe_feedback_portal_submissions (
    id bigint generated always as identity primary key,
    link_id uuid not null references public.bizkipe_feedback_portal_links(id) on delete cascade,
    created_at timestamptz not null default now()
  );
  create index if not exists bizkipe_feedback_portal_submissions_link_time_idx on public.bizkipe_feedback_portal_submissions(link_id, created_at desc);
  alter table public.bizkipe_feedback_portal_submissions enable row level security;
  revoke all on table public.bizkipe_feedback_portal_submissions from anon, authenticated;
  execute $ddl$
  create or replace function public.bizkipe_submit_customer_feedback(
    p_token uuid,
    p_rating integer,
    p_category text,
    p_feedback text,
    p_customer_name text default null,
    p_customer_email text default null
  ) returns boolean
  language plpgsql
  security definer
  set search_path = public
  as $f$
  declare v_link uuid; v_owner uuid; v_enabled boolean; v_expires timestamptz; v_name text; v_email text;
  begin
    if p_token is null or p_rating is null or p_rating < 1 or p_rating > 5 then raise exception 'Invalid feedback submission'; end if;
    if p_category is null or p_category not in ('Product or service','Communication','Delivery','Billing','Support','Other') then raise exception 'Invalid feedback category'; end if;
    if p_feedback is null or char_length(trim(p_feedback)) < 1 or char_length(trim(p_feedback)) > 2000 then raise exception 'Feedback must be between 1 and 2000 characters'; end if;
    v_name := nullif(trim(coalesce(p_customer_name,'')),'');
    v_email := nullif(trim(coalesce(p_customer_email,'')),'');
    if v_name is not null and char_length(v_name) > 120 then raise exception 'Name is too long'; end if;
    if v_email is not null and (char_length(v_email) > 254 or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+$') then raise exception 'Invalid email address'; end if;
    select id, user_id, enabled, expires_at into v_link, v_owner, v_enabled, v_expires from public.bizkipe_feedback_portal_links where token = p_token;
    if v_owner is null or not v_enabled or (v_expires is not null and v_expires < now()) then raise exception 'This feedback link is unavailable'; end if;
    delete from public.bizkipe_feedback_portal_submissions where created_at < now() - interval '3 days';
    if (select count(*) from public.bizkipe_feedback_portal_submissions where link_id = v_link and created_at > now() - interval '1 hour') >= 15
       or (select count(*) from public.bizkipe_feedback_portal_submissions where link_id = v_link and created_at > now() - interval '1 day') >= 100 then
      raise exception 'Too many submissions, please try again later';
    end if;
    insert into public.bizkipe_feedback_portal_submissions(link_id) values (v_link);
    insert into public.bizkipe_customer_feedback(user_id, customer_name, customer_email, rating, category, feedback, received_on)
    values (v_owner, v_name, v_email, p_rating, p_category, trim(p_feedback), (now() at time zone 'Africa/Nairobi')::date);
    return true;
  end;
  $f$;
  $ddl$;
  revoke all on function public.bizkipe_submit_customer_feedback(uuid,integer,text,text,text,text) from public;
  grant execute on function public.bizkipe_submit_customer_feedback(uuid,integer,text,text,text,text) to anon, authenticated;
end
$fn$;
