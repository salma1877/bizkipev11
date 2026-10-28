-- BizKipe v2.8: account-scoped atomic stock adjustments + sales audit exports
-- Run AFTER v2.7-sales-stock-integration.sql and earlier migrations.

create or replace function public.bizkipe_adjust_inventory_stock(
  p_item_id text,
  p_delta integer,
  p_reason text,
  p_movement_id text
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
  v_reason text := left(trim(coalesce(p_reason, '')), 120);
  v_mid text := left(trim(coalesce(p_movement_id, '')), 120);
  v_existing jsonb;
  v_now timestamptz := now();
begin
  if v_uid is null then raise exception 'Sign in before adjusting stock.'; end if;
  if p_item_id is null or trim(p_item_id) = '' then raise exception 'Choose a valid inventory item.'; end if;
  if p_delta is null or p_delta = 0 or abs(p_delta::bigint) > 1000000 then raise exception 'Adjustment must be a non-zero whole number within the allowed range.'; end if;
  if v_mid = '' then raise exception 'A movement ID is required.'; end if;
  if v_reason = '' then raise exception 'Enter a reason for this stock adjustment.'; end if;

  -- Idempotency: a retried request must not apply the same movement twice.
  select movement_data into v_existing from public.bizkipe_inventory_movements
    where user_id = v_uid and movement_id = v_mid;
  if found then
    return jsonb_build_object('ok', true, 'duplicate', true, 'movement', v_existing);
  end if;

  select * into v_item from public.bizkipe_inventory_items
    where user_id = v_uid and item_id = p_item_id and is_deleted = false
    for update;
  if not found then raise exception 'Inventory item not found in your synced account. Sync inventory and try again.'; end if;
  if coalesce((v_item.item_data->>'trackStock')::boolean, false) is not true then raise exception 'Stock tracking is not enabled for this item.'; end if;
  v_name := left(coalesce(v_item.item_data->>'name', 'Inventory item'), 120);
  v_before := greatest(0, floor(coalesce((v_item.item_data->>'stockQty')::numeric, 0))::integer);
  v_after := v_before + p_delta;
  if v_after < 0 then raise exception 'Insufficient stock. Available quantity: %.', v_before; end if;
  if v_after > 2147483647 then raise exception 'Stock quantity is too large.'; end if;

  update public.bizkipe_inventory_items
    set item_data = jsonb_set(jsonb_set(item_data, '{stockQty}', to_jsonb(v_after), true), '{updatedAt}', to_jsonb(v_now), true),
        updated_at = v_now
    where user_id = v_uid and item_id = p_item_id;

  insert into public.bizkipe_inventory_movements(user_id, movement_id, movement_data, created_at)
    values (v_uid, v_mid, jsonb_build_object(
      'id', v_mid, 'itemId', p_item_id, 'name', v_name,
      'delta', p_delta, 'before', v_before, 'after', v_after,
      'reason', v_reason, 'type', 'adjustment', 'at', v_now
    ), v_now);

  return jsonb_build_object('ok', true, 'duplicate', false, 'item_id', p_item_id,
    'item_name', v_name, 'quantity_before', v_before, 'quantity_after', v_after,
    'delta', p_delta, 'movement_id', v_mid, 'created_at', v_now);
end;
$$;

revoke all on function public.bizkipe_adjust_inventory_stock(text, integer, text, text) from public, anon;
grant execute on function public.bizkipe_adjust_inventory_stock(text, integer, text, text) to authenticated;
