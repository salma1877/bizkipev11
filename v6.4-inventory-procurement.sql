-- BizKipe Inventory & Procurement
-- Apply after v2.6, v2.7 and v2.8 inventory migrations.
-- All records are scoped to auth.uid(); receiving stock is an explicit owner action.

create table if not exists public.bizkipe_suppliers (
  user_id uuid not null references auth.users(id) on delete cascade,
  supplier_id text not null,
  supplier_name text not null check (char_length(trim(supplier_name)) between 1 and 120),
  contact_name text not null default '' check (char_length(contact_name) <= 120),
  phone text not null default '' check (char_length(phone) <= 40),
  email text not null default '' check (char_length(email) <= 160),
  notes text not null default '' check (char_length(notes) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, supplier_id)
);

create table if not exists public.bizkipe_purchase_orders (
  user_id uuid not null references auth.users(id) on delete cascade,
  po_id text not null,
  po_number text not null check (char_length(po_number) between 1 and 60),
  supplier_id text not null,
  supplier_name text not null check (char_length(supplier_name) <= 120),
  item_id text not null,
  item_name text not null check (char_length(item_name) <= 160),
  quantity_ordered integer not null check (quantity_ordered > 0 and quantity_ordered <= 1000000),
  quantity_received integer not null default 0 check (quantity_received >= 0 and quantity_received <= quantity_ordered),
  unit_cost numeric(14,2) not null default 0 check (unit_cost >= 0),
  currency text not null default 'KES' check (currency in ('KES','USD','GBP','EUR')),
  expected_date date,
  status text not null default 'draft' check (status in ('draft','ordered','partially_received','received','cancelled')),
  notes text not null default '' check (char_length(notes) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, po_id),
  unique (user_id, po_number),
  foreign key (user_id, supplier_id) references public.bizkipe_suppliers(user_id, supplier_id) on delete restrict
);

create index if not exists bizkipe_suppliers_user_name_idx on public.bizkipe_suppliers(user_id, supplier_name);
create index if not exists bizkipe_purchase_orders_user_created_idx on public.bizkipe_purchase_orders(user_id, created_at desc);
create index if not exists bizkipe_purchase_orders_user_status_idx on public.bizkipe_purchase_orders(user_id, status);

alter table public.bizkipe_suppliers enable row level security;
alter table public.bizkipe_purchase_orders enable row level security;
drop policy if exists "Users manage their own BizKipe suppliers" on public.bizkipe_suppliers;
create policy "Users manage their own BizKipe suppliers" on public.bizkipe_suppliers for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "Users manage their own BizKipe purchase orders" on public.bizkipe_purchase_orders;
create policy "Users manage their own BizKipe purchase orders" on public.bizkipe_purchase_orders for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
grant select, insert, update, delete on public.bizkipe_suppliers, public.bizkipe_purchase_orders to authenticated;

create or replace function public.bizkipe_receive_purchase_order(
  p_po_id text,
  p_quantity integer,
  p_movement_id text
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_po public.bizkipe_purchase_orders%rowtype;
  v_item public.bizkipe_inventory_items%rowtype;
  v_before integer;
  v_after integer;
  v_now timestamptz := now();
  v_mid text := left(trim(coalesce(p_movement_id,'')),120);
begin
  if v_uid is null then raise exception 'Sign in before receiving a purchase order.'; end if;
  if p_quantity is null or p_quantity < 1 or p_quantity > 1000000 then raise exception 'Enter a positive whole quantity.'; end if;
  if v_mid = '' then raise exception 'A unique stock movement ID is required.'; end if;
  -- A retry with the same movement ID is safe and never receives stock twice.
  if exists(select 1 from public.bizkipe_inventory_movements where user_id=v_uid and movement_id=v_mid) then
    return jsonb_build_object('ok',true,'duplicate',true,'movement_id',v_mid);
  end if;
  select * into v_po from public.bizkipe_purchase_orders where user_id=v_uid and po_id=p_po_id for update;
  if not found then raise exception 'Purchase order not found.'; end if;
  -- Re-check after the lock so two simultaneous retries cannot both receive.
  if exists(select 1 from public.bizkipe_inventory_movements where user_id=v_uid and movement_id=v_mid) then
    return jsonb_build_object('ok',true,'duplicate',true,'movement_id',v_mid);
  end if;
  if v_po.status not in ('ordered','partially_received') then raise exception 'Only ordered purchase orders can receive stock.'; end if;
  if p_quantity > v_po.quantity_ordered-v_po.quantity_received then raise exception 'Received quantity exceeds the outstanding order quantity.'; end if;
  select * into v_item from public.bizkipe_inventory_items where user_id=v_uid and item_id=v_po.item_id and is_deleted=false for update;
  if not found then raise exception 'The linked inventory item is missing. Restore or sync it before receiving stock.'; end if;
  if coalesce((v_item.item_data->>'trackStock')::boolean,false) is not true then raise exception 'Enable stock tracking for this item before receiving stock.'; end if;
  v_before := greatest(0,floor(coalesce((v_item.item_data->>'stockQty')::numeric,0))::integer);
  if v_before::bigint+p_quantity > 2147483647 then raise exception 'Stock quantity is too large.'; end if;
  v_after := v_before+p_quantity;
  update public.bizkipe_inventory_items set item_data=jsonb_set(jsonb_set(item_data,'{stockQty}',to_jsonb(v_after),true),'{updatedAt}',to_jsonb(v_now),true), updated_at=v_now where user_id=v_uid and item_id=v_po.item_id;
  update public.bizkipe_purchase_orders set quantity_received=quantity_received+p_quantity,
    status=case when quantity_received+p_quantity=quantity_ordered then 'received' else 'partially_received' end, updated_at=v_now
    where user_id=v_uid and po_id=p_po_id;
  insert into public.bizkipe_inventory_movements(user_id,movement_id,movement_data,created_at)
  values(v_uid,v_mid,jsonb_build_object('id',v_mid,'itemId',v_po.item_id,'name',v_po.item_name,'delta',p_quantity,'before',v_before,'after',v_after,'reason','Purchase order '||v_po.po_number,'purchaseOrderId',v_po.po_id,'type','purchase_receipt','at',v_now),v_now);
  return jsonb_build_object('ok',true,'duplicate',false,'po_id',v_po.po_id,'quantity_received',p_quantity,'quantity_before',v_before,'quantity_after',v_after,'created_at',v_now);
end;
$$;
revoke all on function public.bizkipe_receive_purchase_order(text,integer,text) from public, anon;
grant execute on function public.bizkipe_receive_purchase_order(text,integer,text) to authenticated;
