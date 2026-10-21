-- ============================================================
-- 마피아 게임 · 상점에서 상자 팔기
-- ============================================================
--   물건                      값     파는 기간
--   BOX_TREASURE  보물상자    별 5   늘
--   BOX_PUMPKIN   호박상자    별 5   할로윈 기간만 (해마다 10월 5일 ~ 11월 1일, 할로윈 프로필과 같다)
--
-- 상자는 몇 번이든 다시 살 수 있다. 사면 바로 열어 나온 것을 준다.
-- 나오는 것과 확률은 일일보상 상자와 같다 (roll_box, 0058). 이미 가진 프로필이 나오면
-- 상점 가격의 반을 재화로 준다. 연승 보너스는 붙지 않는다 (이겨서 받는 것이 아니다).
-- 프로필은 0051 처럼 한 번만 산다.
-- ============================================================

alter table public.shop_items drop constraint if exists shop_items_kind_check;
alter table public.shop_items add constraint shop_items_kind_check check (kind in ('AVATAR', 'BOX'));
-- 상자 물건이 여는 상자 종류 (TREASURE · PUMPKIN)
alter table public.shop_items add column if not exists box text;

insert into public.shop_items (id, kind, price_type, price, sale_from, sale_until, repeat_yearly, sort, box) values
  ('BOX_TREASURE', 'BOX', 'STAR', 5, '2026-10-01 00:00:00+09', null, false, 10, 'TREASURE'),
  ('BOX_PUMPKIN',  'BOX', 'STAR', 5, '2026-10-05 00:00:00+09', '2026-11-02 00:00:00+09', true, 11, 'PUMPKIN')
on conflict (id) do nothing;

-- ------------------------------------------------------------
-- my_shop: 상자 종류를 함께 주고, 상자는 보유로 보지 않는다 (0054 와 나머지는 같다)
-- ------------------------------------------------------------
create or replace function public.my_shop()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_avatar text;
begin
  select pf.avatar into v_avatar from public.profiles pf where pf.uid = v_uid;
  if not found then
    raise exception '로그인이 필요합니다.';
  end if;

  return json_build_object(
    'items', coalesce((
      select json_agg(json_build_object(
               'id',        s.id,
               'kind',      s.kind,
               'box',       s.box,
               'priceType', s.price_type,
               'price',     s.price,
               'saleUntil', s.sale_until + public.shop_shift(s.sale_from, s.repeat_yearly),
               'owned',     s.kind <> 'BOX' and o.uid is not null)
             order by s.sort, s.id)
        from public.shop_items s
        left join public.owned_items o on o.item_id = s.id and o.uid = v_uid
       where s.sale_from <= now()
         and (s.sale_until is null
              or now() < s.sale_until + public.shop_shift(s.sale_from, s.repeat_yearly))), '[]'::json),
    'owned', coalesce((
      select json_agg(json_build_object('id', s.id, 'kind', s.kind) order by o.bought_at, s.id)
        from public.owned_items o
        join public.shop_items s on s.id = o.item_id
       where o.uid = v_uid), '[]'::json),
    'avatar', v_avatar
  );
end;
$$;

grant execute on function public.my_shop() to authenticated;

-- ------------------------------------------------------------
-- buy_item: 상자는 몇 번이든 사고 바로 연다 (0054 와 나머지는 같다)
-- 상자를 사면 { stars, gems, coins, open: { box, type, amount, item, dup } } 를 준다.
-- 재화는 연 것을 받기 전의 값이다
-- ------------------------------------------------------------
create or replace function public.buy_item(p_item_id text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_item  public.shop_items%rowtype;
  v_stars int;
  v_gems  int;
  v_coins int;
  v_open  jsonb;
begin
  -- 같은 사람의 요청이 겹쳐도 가진 것보다 많이 쓰지 못하도록 프로필을 잠근다
  select pf.stars, pf.gems, pf.coins into v_stars, v_gems, v_coins
    from public.profiles pf where pf.uid = v_uid for update;
  if not found then
    raise exception '로그인이 필요합니다.';
  end if;

  select * into v_item from public.shop_items s where s.id = p_item_id;
  if not found then
    raise exception '없는 물건입니다.';
  end if;

  if v_item.sale_from > now()
     or (v_item.sale_until is not null
         and now() >= v_item.sale_until + public.shop_shift(v_item.sale_from, v_item.repeat_yearly)) then
    raise exception '지금은 팔지 않는 물건입니다.';
  end if;

  if v_item.kind <> 'BOX'
     and exists (select 1 from public.owned_items o where o.uid = v_uid and o.item_id = v_item.id) then
    raise exception '이미 가지고 있습니다.';
  end if;

  case v_item.price_type
    when 'STAR' then v_stars := v_stars - v_item.price;
    when 'GEM'  then v_gems  := v_gems  - v_item.price;
    when 'COIN' then v_coins := v_coins - v_item.price;
  end case;

  if v_stars < 0 or v_gems < 0 or v_coins < 0 then
    raise exception '재화가 부족합니다.';
  end if;

  update public.profiles pf
     set stars = v_stars, gems = v_gems, coins = v_coins
   where pf.uid = v_uid;

  if v_item.kind = 'BOX' then
    v_open := public.open_box(v_uid, v_item.box);
    return json_build_object('stars', v_stars, 'gems', v_gems, 'coins', v_coins, 'open', v_open);
  end if;

  insert into public.owned_items (uid, item_id) values (v_uid, v_item.id);

  return json_build_object('stars', v_stars, 'gems', v_gems, 'coins', v_coins);
end;
$$;

revoke all on function public.buy_item(text) from public, anon;
grant execute on function public.buy_item(text) to authenticated;
