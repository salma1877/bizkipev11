-- Run this in Supabase SQL Editor. Use the service-role key only in Vercel server environment variables.
create extension if not exists pgcrypto;

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  product_id text not null,
  product_name text not null,
  customer_name text not null,
  customer_email text not null,
  phone text not null,
  amount numeric(12,2) not null check (amount >= 0),
  currency text not null default 'KES',
  status text not null default 'pending' check (status in ('pending','paid','failed','cancelled','expired','pending_verification','fulfilled')),
  access_token_hash text not null,
  checkout_request_id text unique,
  merchant_request_id text,
  mpesa_receipt text,
  paid_amount numeric(12,2),
  payer_phone text,
  result_code integer,
  result_description text,
  callback_payload jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists orders_created_at_idx on public.orders (created_at desc);
create index if not exists orders_status_idx on public.orders (status);
create index if not exists orders_customer_email_idx on public.orders (customer_email);
alter table public.orders enable row level security;

-- Private storage bucket: product files must not be public.
insert into storage.buckets (id, name, public)
values ('bizkipe-products', 'bizkipe-products', false)
on conflict (id) do update set public = false;
