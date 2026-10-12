-- ============================================================
-- 마피아 게임 · 상점 (프로필 구매 · 장착)
-- ============================================================
-- 상점에서 재화로 프로필을 사고, 장착 화면에서 산 프로필을 고른다.
--
--   물건                     값      파는 기간
--   CASTLE_PUMPKIN  호박 성  별 50   2026-11-01 까지 (한국 시간)
--   CASTLE_GHOST    유령 성  별 50   2026-11-01 까지 (한국 시간)
--
-- 물건은 shop_items 에 줄을 더하면 된다. 그림과 이름은 화면이 id 로 고른다.
-- 파는 기간이 끝나면 상점에 나오지 않고 살 수 없다. 이미 산 것은 계속 쓴다.
-- 한 물건은 한 번만 살 수 있다.
-- 장착한 프로필은 profiles.avatar 에 둔다. null 이면 기본(닉네임 첫 글자)이다.
-- profiles 는 쓰기 정책이 없으므로(0046) 구매·장착은 RPC 로만 한다.
-- ============================================================

-- ------------------------------------------------------------
-- 1. 테이블
-- ------------------------------------------------------------

create table if not exists public.shop_items (
  id         text primary key,
  kind       text not null check (kind in ('AVATAR')),
  price_type text not null check (price_type in ('STAR', 'GEM', 'COIN')),
  price      int  not null check (price > 0),
  sale_from  timestamptz not null default now(),
  -- null 이면 계속 판다
  sale_until timestamptz,
  sort       int  not null default 0
);

-- 산 물건
create table if not exists public.owned_items (
  uid       uuid not null references public.profiles (uid) on delete cascade,
  item_id   text not null references public.shop_items (id),
  bought_at timestamptz not null default now(),
  primary key (uid, item_id)
);

alter table public.profiles add column if not exists avatar text;

-- 직접 읽기·쓰기는 막고 RPC 로만 다룬다
alter table public.shop_items  enable row level security;
alter table public.owned_items enable row level security;
revoke all on public.shop_items  from anon, authenticated;
revoke all on public.owned_items from anon, authenticated;

-- 할로윈 프로필. 11월 1일이 끝날 때까지 판다
insert into public.shop_items (id, kind, price_type, price, sale_until, sort) values
  ('CASTLE_PUMPKIN', 'AVATAR', 'STAR', 50, '2026-11-02 00:00:00+09', 1),
  ('CASTLE_GHOST',   'AVATAR', 'STAR', 50, '2026-11-02 00:00:00+09', 2)
on conflict (id) do nothing;

-- ------------------------------------------------------------
-- 2. RPC — 상점과 내 물건
-- ------------------------------------------------------------
-- { items: 지금 파는 물건 [{ id, kind, priceType, price, saleUntil, owned }],
--   owned: 내가 산 물건 [{ id, kind }], avatar: 장착한 프로필 }
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
               'priceType', s.price_type,
               'price',     s.price,
               'saleUntil', s.sale_until,
               'owned',     o.uid is not null)
             order by s.sort, s.id)
        from public.shop_items s
        left join public.owned_items o on o.item_id = s.id and o.uid = v_uid
       where s.sale_from <= now() and (s.sale_until is null or now() < s.sale_until)), '[]'::json),
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
-- 3. RPC — 사기
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
  if v_item.sale_from > now() or (v_item.sale_until is not null and now() >= v_item.sale_until) then
    raise exception '지금은 팔지 않는 물건입니다.';
  end if;
  if exists (select 1 from public.owned_items o where o.uid = v_uid and o.item_id = v_item.id) then
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
  insert into public.owned_items (uid, item_id) values (v_uid, v_item.id);

  return json_build_object('stars', v_stars, 'gems', v_gems, 'coins', v_coins);
end;
$$;

revoke all on function public.buy_item(text) from public, anon;
grant execute on function public.buy_item(text) to authenticated;

-- ------------------------------------------------------------
-- 4. RPC — 프로필 장착. null 이면 기본 프로필로 돌아간다
-- ------------------------------------------------------------
create or replace function public.equip_avatar(p_item_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if not exists (select 1 from public.profiles pf where pf.uid = v_uid) then
    raise exception '로그인이 필요합니다.';
  end if;

  if p_item_id is not null and not exists (
       select 1 from public.owned_items o
         join public.shop_items s on s.id = o.item_id
        where o.uid = v_uid and o.item_id = p_item_id and s.kind = 'AVATAR') then
    raise exception '가지고 있지 않은 프로필입니다.';
  end if;

  update public.profiles pf set avatar = p_item_id where pf.uid = v_uid;
end;
$$;

revoke all on function public.equip_avatar(text) from public, anon;
grant execute on function public.equip_avatar(text) to authenticated;
