-- BizKipe v2.6: account-synced inventory and stock movement records
-- Run in Supabase SQL Editor after the existing BizKipe migrations.
-- Uses the signed-in user's auth.uid(); never expose service-role keys in the browser.

create table if not exists public.bizkipe_inventory_items (
  user_id uuid not null references auth.users(id) on delete cascade,
  item_id text not null,
  item_data jsonb not null default '{}'::jsonb,
  is_deleted boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, item_id)
);

create table if not exists public.bizkipe_inventory_movements (
  user_id uuid not null references auth.users(id) on delete cascade,
  movement_id text not null,
  movement_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  primary key (user_id, movement_id)
);

create index if not exists bizkipe_inventory_items_user_updated_idx
  on public.bizkipe_inventory_items (user_id, updated_at desc);
create index if not exists bizkipe_inventory_movements_user_created_idx
  on public.bizkipe_inventory_movements (user_id, created_at desc);

alter table public.bizkipe_inventory_items enable row level security;
alter table public.bizkipe_inventory_movements enable row level security;

drop policy if exists "Users manage their own BizKipe inventory items" on public.bizkipe_inventory_items;
create policy "Users manage their own BizKipe inventory items"
  on public.bizkipe_inventory_items for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users manage their own BizKipe inventory movements" on public.bizkipe_inventory_movements;
create policy "Users manage their own BizKipe inventory movements"
  on public.bizkipe_inventory_movements for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

grant select, insert, update, delete on public.bizkipe_inventory_items to authenticated;
grant select, insert, update, delete on public.bizkipe_inventory_movements to authenticated;
