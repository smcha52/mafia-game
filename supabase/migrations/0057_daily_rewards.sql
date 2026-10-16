-- ============================================================
-- 마피아 게임 · 일일보상
-- ============================================================
-- 게임에서 이길 때마다 보상 하나를 무작위로 받는다. 하루(한국 시간 자정 ~ 자정)에 5개까지.
-- 6번째 승리부터는 그날 일일보상이 없다 (승리 코인 10개는 그대로 받는다).
--
--   보상      확률     등급
--   코인 5    35%      일반
--   코인 10   25%      일반
--   별 5      15%      일반
--   별 10     10%      일반
--   코인 40   10%      일반
--   별 20     4.5%     럭키
--   보석 2    0.5%     슈퍼 럭키
--
-- 게임이 끝나면 award_xp 가 game_records 에 한 사람마다 한 줄을 넣는다(0049).
-- 그 줄이 승리이면 트리거가 보상을 뽑아 바로 지급한다. award_xp 는 한 판에 한 번만 돌므로
-- 보상도 한 판에 한 번만 나온다. 익명 사용자(테스트)는 프로필이 없어 받지 않는다.
-- ============================================================

-- ------------------------------------------------------------
-- 1. 테이블
-- ------------------------------------------------------------

-- 받은 일일보상. day = 받은 한국 날짜, idx = 그날 몇 번째(1~5)
create table if not exists public.daily_rewards (
  uid        uuid not null references public.profiles (uid) on delete cascade,
  day        date not null,
  idx        int  not null check (idx between 1 and 5),
  type       text not null check (type in ('COIN', 'STAR', 'GEM')),
  amount     int  not null check (amount > 0),
  tier       text not null check (tier in ('NORMAL', 'LUCKY', 'SUPER_LUCKY')),
  room_id    uuid,
  created_at timestamptz not null default now(),
  primary key (uid, day, idx)
);

-- 직접 읽기·쓰기는 막고 RPC 로만 다룬다
alter table public.daily_rewards enable row level security;
revoke all on public.daily_rewards from anon, authenticated;

-- ------------------------------------------------------------
-- 2. 규칙 (내부용)
-- ------------------------------------------------------------

-- 하루에 받을 수 있는 개수
create or replace function public.daily_reward_limit()
returns int
language sql
immutable
as $$ select 5 $$;

-- 보상 하나를 뽑는다 { type, amount, tier }. 확률은 1000 분율
create or replace function public.roll_daily_reward()
returns jsonb
language plpgsql
volatile
as $$
declare
  v_r int := floor(random() * 1000)::int;  -- 0 ~ 999
begin
  return case
    when v_r < 350 then '{"type":"COIN","amount":5,"tier":"NORMAL"}'        -- 35%
    when v_r < 600 then '{"type":"COIN","amount":10,"tier":"NORMAL"}'       -- 25%
    when v_r < 750 then '{"type":"STAR","amount":5,"tier":"NORMAL"}'        -- 15%
    when v_r < 850 then '{"type":"STAR","amount":10,"tier":"NORMAL"}'       -- 10%
    when v_r < 950 then '{"type":"COIN","amount":40,"tier":"NORMAL"}'       -- 10%
    when v_r < 995 then '{"type":"STAR","amount":20,"tier":"LUCKY"}'        -- 4.5%
    else                '{"type":"GEM","amount":2,"tier":"SUPER_LUCKY"}'    -- 0.5%
  end::jsonb;
end;
$$;

revoke all on function public.roll_daily_reward() from public, anon, authenticated;

-- ------------------------------------------------------------
-- 3. 이기면 지급 (game_records 트리거)
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

  insert into public.daily_rewards (uid, day, idx, type, amount, tier, room_id)
  values (new.uid, v_today, v_idx, v_r ->> 'type', (v_r ->> 'amount')::int, v_r ->> 'tier', new.room_id);

  update public.profiles pf
     set coins = pf.coins + case when v_r ->> 'type' = 'COIN' then (v_r ->> 'amount')::int else 0 end,
         stars = pf.stars + case when v_r ->> 'type' = 'STAR' then (v_r ->> 'amount')::int else 0 end,
         gems  = pf.gems  + case when v_r ->> 'type' = 'GEM'  then (v_r ->> 'amount')::int else 0 end
   where pf.uid = new.uid;

  return new;
end;
$$;

revoke all on function public.give_daily_reward() from public, anon, authenticated;

drop trigger if exists game_records_daily_reward on public.game_records;
create trigger game_records_daily_reward
  after insert on public.game_records
  for each row when (new.won)
  execute function public.give_daily_reward();

-- ------------------------------------------------------------
-- 4. RPC — 오늘 받은 일일보상
-- ------------------------------------------------------------
-- { limit: 하루 개수, next: 다시 받을 수 있게 되는 시각(다음 한국 자정),
--   items: [{ idx, type, amount, tier }] }  (받은 순서)
create or replace function public.my_daily_rewards()
returns json
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

  return json_build_object(
    'limit', public.daily_reward_limit(),
    'next',  public.attendance_next(),
    'items', coalesce((
      select json_agg(json_build_object('idx', d.idx, 'type', d.type, 'amount', d.amount, 'tier', d.tier)
                      order by d.idx)
        from public.daily_rewards d
       where d.uid = v_uid and d.day = (now() at time zone 'Asia/Seoul')::date), '[]'::json)
  );
end;
$$;

revoke all on function public.my_daily_rewards() from public, anon;
grant execute on function public.my_daily_rewards() to authenticated;
