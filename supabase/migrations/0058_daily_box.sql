-- ============================================================
-- 마피아 게임 · 일일보상 상자
-- ============================================================
-- 일일보상(0057)에 상자를 더한다. 코인 5 · 코인 10 의 확률을 줄이고 남은 10% 가 상자다.
--
--   일일보상  확률     등급
--   코인 5    30%      일반   (35% → 30%)
--   코인 10   20%      일반   (25% → 20%)
--   별 5      15%      일반
--   별 10     10%      일반
--   코인 40   10%      일반
--   상자      10%      일반
--   별 20     4.5%     럭키
--   보석 2    0.5%     슈퍼 럭키
--
-- 상자는 받은 칸에 그대로 나오고, 눌러서 열면 보상을 받는다. 다음 날이 되어도 열지 않은
-- 상자는 남아 있다. 할로윈 기간(is_halloween, 0054)에는 호박상자만, 그 밖에는 보물상자만 나온다.
--
--   보물상자          확률     호박상자          확률
--   코인 5~25         35%      코인 5~25         35%
--   별 1~5            25%      별 1~5            25%
--   코인 30~50        20%      코인 30~50        20%
--   별 4~15           15%      별 4~15           15%
--   보석 1~2          4.8%     보석 1~2          3%
--   보석 5            0.2%     호박 성 프로필    1%
--                              유령 성 프로필    1%
--
-- 범위가 있는 보상은 그 안에서 고르게 하나를 뽑는다.
-- 이미 가진 프로필이 나오면 상점 가격의 반(별 25)을 재화로 바꿔 준다.
-- ============================================================

-- ------------------------------------------------------------
-- 1. 테이블
-- ------------------------------------------------------------

alter table public.daily_rewards drop constraint if exists daily_rewards_type_check;
alter table public.daily_rewards add  constraint daily_rewards_type_check
  check (type in ('COIN', 'STAR', 'GEM', 'BOX'));

-- box = 상자 종류 (BOX 일 때만), opened_at = 연 시각,
-- open_type · open_amount = 상자에서 나온 재화, open_item = 상자에서 나온 프로필,
-- open_dup = 이미 가진 프로필이라 재화(상점 가격의 반)로 바꿨는지
alter table public.daily_rewards add column if not exists box         text check (box in ('TREASURE', 'PUMPKIN'));
alter table public.daily_rewards add column if not exists opened_at   timestamptz;
alter table public.daily_rewards add column if not exists open_type   text;
alter table public.daily_rewards add column if not exists open_amount int;
alter table public.daily_rewards add column if not exists open_item   text;
alter table public.daily_rewards add column if not exists open_dup    boolean not null default false;

create index if not exists daily_rewards_box_idx on public.daily_rewards (uid)
  where type = 'BOX' and opened_at is null;

-- ------------------------------------------------------------
-- 2. 규칙 (내부용)
-- ------------------------------------------------------------

-- 일일보상 하나를 뽑는다 { type, amount, tier, box? }. 확률은 1000 분율
create or replace function public.roll_daily_reward()
returns jsonb
language plpgsql
volatile
as $$
declare
  v_r int := floor(random() * 1000)::int;  -- 0 ~ 999
begin
  return case
    when v_r < 300 then '{"type":"COIN","amount":5,"tier":"NORMAL"}'::jsonb        -- 30%
    when v_r < 500 then '{"type":"COIN","amount":10,"tier":"NORMAL"}'::jsonb       -- 20%
    when v_r < 650 then '{"type":"STAR","amount":5,"tier":"NORMAL"}'::jsonb        -- 15%
    when v_r < 750 then '{"type":"STAR","amount":10,"tier":"NORMAL"}'::jsonb       -- 10%
    when v_r < 850 then '{"type":"COIN","amount":40,"tier":"NORMAL"}'::jsonb       -- 10%
    when v_r < 950 then jsonb_build_object(                                        -- 10%
                          'type', 'BOX', 'amount', 1, 'tier', 'NORMAL',
                          'box', case when public.is_halloween() then 'PUMPKIN' else 'TREASURE' end)
    when v_r < 995 then '{"type":"STAR","amount":20,"tier":"LUCKY"}'::jsonb        -- 4.5%
    else                '{"type":"GEM","amount":2,"tier":"SUPER_LUCKY"}'::jsonb    -- 0.5%
  end;
end;
$$;

revoke all on function public.roll_daily_reward() from public, anon, authenticated;

-- p_lo ~ p_hi 중 하나
create or replace function public.rand_between(p_lo int, p_hi int)
returns int
language sql
volatile
as $$ select p_lo + floor(random() * (p_hi - p_lo + 1))::int $$;

-- 상자에서 나오는 것을 뽑는다 { type, amount } 또는 { item }. 확률은 1000 분율
create or replace function public.roll_box(p_box text)
returns jsonb
language plpgsql
volatile
as $$
declare
  v_r int := floor(random() * 1000)::int;  -- 0 ~ 999
begin
  if v_r < 350 then return jsonb_build_object('type', 'COIN', 'amount', public.rand_between(5, 25));  end if;  -- 35%
  if v_r < 600 then return jsonb_build_object('type', 'STAR', 'amount', public.rand_between(1, 5));   end if;  -- 25%
  if v_r < 800 then return jsonb_build_object('type', 'COIN', 'amount', public.rand_between(30, 50)); end if;  -- 20%
  if v_r < 950 then return jsonb_build_object('type', 'STAR', 'amount', public.rand_between(4, 15));  end if;  -- 15%

  if p_box = 'PUMPKIN' then
    if v_r < 980 then return jsonb_build_object('type', 'GEM', 'amount', public.rand_between(1, 2)); end if;   -- 3%
    if v_r < 990 then return '{"item":"CASTLE_PUMPKIN"}'::jsonb; end if;                                      -- 1%
    return '{"item":"CASTLE_GHOST"}'::jsonb;                                                                   -- 1%
  end if;

  if v_r < 998 then return jsonb_build_object('type', 'GEM', 'amount', public.rand_between(1, 2)); end if;     -- 4.8%
  return '{"type":"GEM","amount":5}'::jsonb;                                                                   -- 0.2%
end;
$$;

revoke all on function public.rand_between(int, int) from public, anon, authenticated;
revoke all on function public.roll_box(text)         from public, anon, authenticated;

-- 재화를 더한다
create or replace function public.give_currency(p_uid uuid, p_type text, p_amount int)
returns void
language sql
security definer
set search_path = public
as $$
  update public.profiles pf
     set coins = pf.coins + case when p_type = 'COIN' then p_amount else 0 end,
         stars = pf.stars + case when p_type = 'STAR' then p_amount else 0 end,
         gems  = pf.gems  + case when p_type = 'GEM'  then p_amount else 0 end
   where pf.uid = p_uid;
$$;

revoke all on function public.give_currency(uuid, text, int) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 3. 이기면 지급 (0057 과 같고, 상자는 지급하지 않고 남겨 둔다)
-- ------------------------------------------------------------
create or replace function public.give_daily_reward()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_idx   int;
  v_r     jsonb;
begin
  -- 같은 사람의 지급이 겹쳐도 개수를 넘지 않도록 프로필을 잠근다. 프로필이 없으면 건너뛴다
  perform 1 from public.profiles pf where pf.uid = new.uid for update;
  if not found then
    return new;
  end if;

  select count(*) + 1 into v_idx
    from public.daily_rewards d where d.uid = new.uid and d.day = v_today;
  if v_idx > public.daily_reward_limit() then
    return new;
  end if;

  v_r := public.roll_daily_reward();

  insert into public.daily_rewards (uid, day, idx, type, amount, tier, box, room_id)
  values (new.uid, v_today, v_idx, v_r ->> 'type', (v_r ->> 'amount')::int, v_r ->> 'tier',
          v_r ->> 'box', new.room_id);

  if v_r ->> 'type' <> 'BOX' then
    perform public.give_currency(new.uid, v_r ->> 'type', (v_r ->> 'amount')::int);
  end if;

  return new;
end;
$$;

-- ------------------------------------------------------------
-- 4. RPC — 오늘 받은 일일보상
-- ------------------------------------------------------------
-- { limit, next,
--   items: [{ day, idx, type, amount, tier, box, opened, open }]  오늘 받은 것 (받은 순서),
--   boxes: [...]  지난날에 받고 아직 열지 않은 상자 (같은 모양) }
-- open = 상자에서 나온 것 { type, amount, item, dup } (열지 않았으면 null)
create or replace function public.daily_reward_json(d public.daily_rewards)
returns json
language sql
stable
as $$
  select json_build_object(
    'day', d.day, 'idx', d.idx, 'type', d.type, 'amount', d.amount, 'tier', d.tier, 'box', d.box,
    'opened', d.opened_at is not null,
    'open', case when d.opened_at is not null then json_build_object(
              'type', d.open_type, 'amount', d.open_amount, 'item', d.open_item, 'dup', d.open_dup) end);
$$;

create or replace function public.my_daily_rewards()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_today date := (now() at time zone 'Asia/Seoul')::date;
begin
  if not exists (select 1 from public.profiles pf where pf.uid = v_uid) then
    raise exception '로그인이 필요합니다.';
  end if;

  return json_build_object(
    'limit', public.daily_reward_limit(),
    'next',  public.attendance_next(),
    'items', coalesce((
      select json_agg(public.daily_reward_json(d) order by d.idx)
        from public.daily_rewards d
       where d.uid = v_uid and d.day = v_today), '[]'::json),
    'boxes', coalesce((
      select json_agg(public.daily_reward_json(d) order by d.day, d.idx)
        from public.daily_rewards d
       where d.uid = v_uid and d.day < v_today and d.type = 'BOX' and d.opened_at is null), '[]'::json)
  );
end;
$$;

-- ------------------------------------------------------------
-- 5. RPC — 상자 열기
-- ------------------------------------------------------------
-- 돌려주는 값은 open 과 같다 { type, amount, item, dup }
create or replace function public.open_daily_box(p_day date, p_idx int)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_row  public.daily_rewards;
  v_r    jsonb;
  v_type text;
  v_amt  int;
  v_item text;
  v_dup  boolean := false;
begin
  -- 같은 상자를 두 번 열지 못하도록 잠근다
  select * into v_row from public.daily_rewards d
   where d.uid = v_uid and d.day = p_day and d.idx = p_idx and d.type = 'BOX'
   for update;
  if not found then
    raise exception '상자가 없습니다.';
  end if;
  if v_row.opened_at is not null then
    raise exception '이미 연 상자입니다.';
  end if;

  v_r    := public.roll_box(v_row.box);
  v_type := v_r ->> 'type';
  v_amt  := (v_r ->> 'amount')::int;
  v_item := v_r ->> 'item';

  if v_item is not null then
    insert into public.owned_items (uid, item_id) values (v_uid, v_item)
    on conflict (uid, item_id) do nothing;
    -- 이미 가졌으면 상점 가격의 반을 재화로 바꿔 준다
    if not found then
      v_dup := true;
      select s.price_type, s.price / 2 into v_type, v_amt from public.shop_items s where s.id = v_item;
    end if;
  end if;

  if v_type is not null then
    perform public.give_currency(v_uid, v_type, v_amt);
  end if;

  update public.daily_rewards d
     set opened_at = now(), open_type = v_type, open_amount = v_amt, open_item = v_item, open_dup = v_dup
   where d.uid = v_uid and d.day = p_day and d.idx = p_idx;

  return json_build_object('type', v_type, 'amount', v_amt, 'item', v_item, 'dup', v_dup);
end;
$$;

revoke all on function public.open_daily_box(date, int) from public, anon;
grant execute on function public.open_daily_box(date, int) to authenticated;
