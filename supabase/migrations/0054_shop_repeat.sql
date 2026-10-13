-- ============================================================
-- 마피아 게임 · 상점 물건이 해마다 다시 나온다
-- ============================================================
-- shop_items.repeat_yearly 가 켜져 있으면 파는 기간(sale_from ~ sale_until)이
-- 해마다 같은 날짜에 되풀이된다. 꺼져 있으면 0051 과 같이 한 번만 판다.
--
--   물건                     파는 기간 (한국 시간, 해마다)
--   CASTLE_PUMPKIN  호박 성  10월 5일 ~ 11월 1일이 끝날 때까지
--   CASTLE_GHOST    유령 성  10월 5일 ~ 11월 1일이 끝날 때까지
--
-- 할로윈 배경(화면 theme.js)도 같은 기간을 쓴다.
-- 한 물건은 한 번만 살 수 있으므로, 이미 산 사람에게는 다시 나와도 보유 중으로 보인다.
--
-- 앞으로 더하는 할로윈 물건·이벤트·보상도 같은 기간에 다시 오게 한다.
--   상점 물건  shop_items 에 넣을 때 같은 sale_from · sale_until 과 repeat_yearly 를 준다
--   서버 규칙  is_halloween() 으로 지금이 할로윈 기간인지 본다
--   화면       theme.js 의 halloween 을 쓴다
-- ============================================================

alter table public.shop_items add column if not exists repeat_yearly boolean not null default false;

-- 처음에는 364일 간격으로 만들었다. 그때 실행했다면 남아 있는 것을 지운다
alter table public.shop_items drop column if exists repeat_every;
drop function if exists public.shop_shift(timestamptz, interval);

update public.shop_items s
   set sale_from     = '2026-10-05 00:00:00+09',
       sale_until    = '2026-11-02 00:00:00+09',
       repeat_yearly = true
 where s.id in ('CASTLE_PUMPKIN', 'CASTLE_GHOST');

-- ------------------------------------------------------------
-- 1. 파는 기간 (내부용)
-- ------------------------------------------------------------
-- 지금 속한 해의 파는 기간이 처음 기간에서 몇 년 밀렸는지. 되풀이하지 않으면 0
create or replace function public.shop_shift(p_from timestamptz, p_yearly boolean)
returns interval
language sql
stable
as $$
  select case
    when not p_yearly or now() < p_from then interval '0'
    else make_interval(years => extract(year from age(now(), p_from))::int)
  end;
$$;

-- 지금이 할로윈 기간인지. 해마다 10월 5일부터 11월 1일이 끝날 때까지 (화면 theme.js 와 같다)
-- 할로윈에만 여는 이벤트·보상은 이 함수로 기간을 본다
create or replace function public.is_halloween()
returns boolean
language sql
stable
as $$
  select now() >= timestamptz '2026-10-05 00:00:00+09'
     and now() <  timestamptz '2026-11-02 00:00:00+09'
                  + public.shop_shift(timestamptz '2026-10-05 00:00:00+09', true);
$$;

-- ------------------------------------------------------------
-- 2. RPC — 상점과 내 물건 (파는 기간 말고는 0051 과 같다)
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
               'priceType', s.price_type,
               'price',     s.price,
               'saleUntil', s.sale_until + public.shop_shift(s.sale_from, s.repeat_yearly),
               'owned',     o.uid is not null)
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
-- 3. RPC — 사기 (파는 기간 말고는 0051 과 같다)
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
  if v_item.sale_from > now()
     or (v_item.sale_until is not null
         and now() >= v_item.sale_until + public.shop_shift(v_item.sale_from, v_item.repeat_yearly)) then
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
