-- BizKipe v2.7: confirmed sale → atomic stock deduction
-- Run AFTER v2.6-inventory-sync.sql in Supabase SQL Editor.
-- This records a sale only when the owner explicitly confirms it in the UI.

create table if not exists public.bizkipe_inventory_sales (
  user_id uuid not null references auth.users(id) on delete cascade,
  sale_ref text not null,
  item_id text not null,
  item_name text not null,
  quantity integer not null check (quantity > 0),
  quantity_before integer not null check (quantity_before >= 0),
  quantity_after integer not null check (quantity_after >= 0),
  created_at timestamptz not null default now(),
  primary key (user_id, sale_ref, item_id)
);

create index if not exists bizkipe_inventory_sales_user_created_idx
  on public.bizkipe_inventory_sales (user_id, created_at desc);

alter table public.bizkipe_inventory_sales enable row level security;
drop policy if exists "Users read their own BizKipe sales" on public.bizkipe_inventory_sales;
create policy "Users read their own BizKipe sales"
  on public.bizkipe_inventory_sales for select to authenticated
  using (auth.uid() = user_id);
grant select on public.bizkipe_inventory_sales to authenticated;
revoke insert, update, delete on public.bizkipe_inventory_sales from anon, authenticated;

create or replace function public.bizkipe_record_inventory_sale(
  p_item_id text,
  p_quantity integer,
  p_sale_ref text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_item public.bizkipe_inventory_items%rowtype;
  v_before integer;
  v_after integer;
  v_name text;
  v_ref text := left(trim(coalesce(p_sale_ref, '')), 100);
  v_existing public.bizkipe_inventory_sales%rowtype;
  v_now timestamptz := now();
begin
  if v_uid is null then raise exception 'Sign in before recording a sale.'; end if;
  if p_item_id is null or trim(p_item_id) = '' then raise exception 'Choose a valid inventory item.'; end if;
  if p_quantity is null or p_quantity < 1 or p_quantity > 1000000 then raise exception 'Quantity must be a positive whole number.'; end if;
  if v_ref = '' then raise exception 'Enter a unique sale or invoice reference.'; end if;

  -- Lock the user's item row so concurrent sales cannot oversell stock.
  select * into v_item from public.bizkipe_inventory_items
    where user_id = v_uid and item_id = p_item_id and is_deleted = false
    for update;
  if not found then raise exception 'Inventory item not found in your synced account. Sync inventory and try again.'; end if;
  if coalesce((v_item.item_data->>'trackStock')::boolean, false) is not true then
    raise exception 'Stock tracking is not enabled for this item.';
  end if;
  v_name := left(coalesce(v_item.item_data->>'name', 'Inventory item'), 120);
  v_before := greatest(0, floor(coalesce((v_item.item_data->>'stockQty')::numeric, 0))::integer);

  -- The same reference can cover multiple products; each reference/item pair is idempotent: never deduct twice.
  select * into v_existing from public.bizkipe_inventory_sales
    where user_id = v_uid and sale_ref = v_ref and item_id = p_item_id;
  if found then
    if v_existing.item_id = p_item_id and v_existing.quantity = p_quantity then
      return jsonb_build_object('ok', true, 'duplicate', true, 'sale_ref', v_ref,
        'item_id', p_item_id, 'item_name', v_existing.item_name,
        'quantity', v_existing.quantity, 'quantity_before', v_existing.quantity_before,
        'quantity_after', v_existing.quantity_after, 'created_at', v_existing.created_at);
    end if;
    raise exception 'This sale reference has already been used for a different sale. Use a new reference.';
  end if;

  if v_before < p_quantity then raise exception 'Insufficient stock. Available quantity: %.', v_before; end if;
  v_after := v_before - p_quantity;

  update public.bizkipe_inventory_items
    set item_data = jsonb_set(jsonb_set(item_data, '{stockQty}', to_jsonb(v_after), true), '{updatedAt}', to_jsonb(v_now), true),
        updated_at = v_now
    where user_id = v_uid and item_id = p_item_id;

  insert into public.bizkipe_inventory_sales(user_id, sale_ref, item_id, item_name, quantity, quantity_before, quantity_after, created_at)
    values (v_uid, v_ref, p_item_id, v_name, p_quantity, v_before, v_after, v_now);

  insert into public.bizkipe_inventory_movements(user_id, movement_id, movement_data, created_at)
    values (v_uid, 'sale-' || md5(v_ref || ':' || p_item_id), jsonb_build_object(
      'id', 'sale-' || md5(v_ref || ':' || p_item_id), 'itemId', p_item_id, 'name', v_name,
      'delta', -p_quantity, 'before', v_before, 'after', v_after,
      'reason', 'Confirmed sale ' || v_ref, 'saleRef', v_ref,
      'type', 'sale', 'at', v_now
    ), v_now)
    on conflict (user_id, movement_id) do nothing;

  return jsonb_build_object('ok', true, 'duplicate', false, 'sale_ref', v_ref,
    'item_id', p_item_id, 'item_name', v_name, 'quantity', p_quantity,
    'quantity_before', v_before, 'quantity_after', v_after, 'created_at', v_now);
end;
$$;

revoke all on function public.bizkipe_record_inventory_sale(text, integer, text) from public, anon;
grant execute on function public.bizkipe_record_inventory_sale(text, integer, text) to authenticated;
