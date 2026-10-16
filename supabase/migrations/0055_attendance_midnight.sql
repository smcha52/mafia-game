-- ============================================================
-- 마피아 게임 · 출석 날짜가 한국 시간 자정에 넘어간다
-- ============================================================
-- 0052·0053 에서는 튜토리얼을 처음 마친 순간부터 24시간이 하루였다.
-- 이제 한국 시간 자정(0시)에 다음 날이 된다. 출석 보상을 다시 받을 수 있게 되는 때와
-- 연속 출석이 끊기는 때가 모두 자정이다.
--
-- 날 수(slot) = 출석이 시작된 날부터 오늘까지 한국 날짜로 며칠 지났는지.
-- 이미 출석을 시작한 계정은 attendance_start 를 "오늘 - 지금 날 수" 의 자정으로 옮겨
-- 이 마이그레이션을 실행한 순간의 날 수가 그대로 이어지게 한다.
-- (받은 보상·연속 일수가 바뀌지 않는다. 지금 하루만 자정까지 늘거나 줄어든다)
-- 다시 실행해도 결과는 같다.
-- ============================================================

-- ------------------------------------------------------------
-- 1. 날짜 규칙 (내부용)
-- ------------------------------------------------------------

-- 출석이 시작된 뒤 지난 날 수 (한국 날짜 기준)
create or replace function public.attendance_slot(p_start timestamptz)
returns int
language sql
stable
as $$
  select (now() at time zone 'Asia/Seoul')::date - (p_start at time zone 'Asia/Seoul')::date;
$$;

-- 다음 날이 되는 시각 (다음 한국 자정)
create or replace function public.attendance_next()
returns timestamptz
language sql
stable
as $$
  select ((now() at time zone 'Asia/Seoul')::date + 1)::timestamp at time zone 'Asia/Seoul';
$$;

-- ------------------------------------------------------------
-- 2. 이미 시작한 계정의 날 수를 이어 간다
-- ------------------------------------------------------------
update public.profiles pf
   set attendance_start =
         ((now() at time zone 'Asia/Seoul')::date
           - floor(extract(epoch from now() - pf.attendance_start) / 86400)::int
         )::timestamp at time zone 'Asia/Seoul'
 where pf.attendance_start is not null;

-- ------------------------------------------------------------
-- 3. RPC — 내 출석
-- ------------------------------------------------------------
create or replace function public.my_attendance()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_start timestamptz;
  v_n     int;
begin
  v_start := public.attendance_begin(v_uid);
  if v_start is null then
    raise exception '로그인이 필요합니다.';
  end if;

  -- 시작한 뒤 지난 날 수. 30일마다 한 바퀴
  v_n := public.attendance_slot(v_start);

  return json_build_object(
    'day',  v_n % 30 + 1,
    'next', public.attendance_next(),
    'days', (
      select json_agg(json_build_object(
               'day',     d,
               'rewards', coalesce((
                 select jsonb_agg(jsonb_build_object('type', r ->> 0, 'amount', (r ->> 1)::int))
                   from jsonb_array_elements(public.attendance_rewards(d)) r), '[]'::jsonb),
               'claimed', exists (
                 select 1 from public.attendance_claims c
                  where c.uid = v_uid and c.slot = v_n - v_n % 30 + d - 1))
             order by d)
        from generate_series(1, 30) d)
  );
end;
$$;

-- ------------------------------------------------------------
-- 4. RPC — 오늘 보상 받기
-- ------------------------------------------------------------
create or replace function public.claim_attendance()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_start   timestamptz;
  v_n       int;
  v_day     int;
  v_rewards jsonb;
begin
  v_start := public.attendance_begin(v_uid);
  if v_start is null then
    raise exception '로그인이 필요합니다.';
  end if;

  v_n       := public.attendance_slot(v_start);
  v_day     := v_n % 30 + 1;
  v_rewards := public.attendance_rewards(v_day);
  if jsonb_array_length(v_rewards) = 0 then
    raise exception '오늘은 받을 보상이 없습니다.';
  end if;

  -- 같은 사람의 요청이 겹쳐도 한 번만 받는다
  insert into public.attendance_claims (uid, slot) values (v_uid, v_n)
  on conflict (uid, slot) do nothing;
  if not found then
    raise exception '오늘 출석 보상은 이미 받았습니다.';
  end if;

  -- 지난 바퀴의 기록은 더 쓰지 않는다
  delete from public.attendance_claims c
   where c.uid = v_uid and c.slot < v_n - v_n % 30;

  update public.profiles pf
     set stars = pf.stars + t.stars, gems = pf.gems + t.gems, coins = pf.coins + t.coins
    from (
      select coalesce(sum((r ->> 1)::int) filter (where r ->> 0 = 'STAR'), 0)::int as stars,
             coalesce(sum((r ->> 1)::int) filter (where r ->> 0 = 'GEM'),  0)::int as gems,
             coalesce(sum((r ->> 1)::int) filter (where r ->> 0 = 'COIN'), 0)::int as coins
        from jsonb_array_elements(v_rewards) r
    ) t
   where pf.uid = v_uid;

  return json_build_object('day', v_day);
end;
$$;

-- ------------------------------------------------------------
-- 5. RPC — 내 연속 출석
-- ------------------------------------------------------------
create or replace function public.my_streak()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_start  timestamptz;
  v_n      int;
  v_count  int;
  v_slot   int;
  v_streak int;
  v_done   int;
begin
  v_start := public.attendance_begin(v_uid);
  if v_start is null then
    raise exception '로그인이 필요합니다.';
  end if;

  v_n := public.attendance_slot(v_start);
  select pf.streak_count, pf.streak_slot into v_count, v_slot
    from public.profiles pf where pf.uid = v_uid;

  -- 오늘이나 어제 출석했으면 이어지고 있다. 그보다 오래됐으면 끊겼다
  v_streak := case when v_slot is not null and v_slot >= v_n - 1 then v_count else 0 end;

  -- 30일 표에서 이번 바퀴에 출석한 칸 수. 30일째를 채운 다음 날은 새 바퀴라 0 이다
  v_done := case
    when v_streak = 0   then 0
    when v_slot = v_n   then (v_streak - 1) % 30 + 1
    else v_streak % 30
  end;

  return json_build_object(
    'streak',  v_streak,
    'checked', coalesce(v_slot = v_n, false),
    'next',    public.attendance_next(),
    'day',     case when v_slot = v_n then v_done else v_done + 1 end,
    'days', (
      select json_agg(json_build_object(
               'day',     d,
               'rewards', coalesce((
                 select jsonb_agg(jsonb_build_object('type', r ->> 0, 'amount', (r ->> 1)::int))
                   from jsonb_array_elements(public.streak_rewards(d)) r), '[]'::jsonb),
               'claimed', d <= v_done)
             order by d)
        from generate_series(1, 30) d)
  );
end;
$$;

-- ------------------------------------------------------------
-- 6. RPC — 오늘 연속 출석하기
-- ------------------------------------------------------------
create or replace function public.claim_streak()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_start   timestamptz;
  v_n       int;
  v_count   int;
  v_slot    int;
  v_rewards jsonb;
begin
  v_start := public.attendance_begin(v_uid);
  if v_start is null then
    raise exception '로그인이 필요합니다.';
  end if;

  -- 같은 사람의 요청이 겹쳐도 한 번만 세도록 프로필을 잠근다
  select pf.streak_count, pf.streak_slot into v_count, v_slot
    from public.profiles pf where pf.uid = v_uid for update;

  v_n := public.attendance_slot(v_start);
  if v_slot = v_n then
    raise exception '오늘은 이미 출석했습니다.';
  end if;

  -- 어제 출석했으면 이어 가고, 아니면 1일부터 다시 센다
  v_count   := case when v_slot = v_n - 1 then v_count + 1 else 1 end;
  v_rewards := public.streak_rewards(v_count);

  update public.profiles pf
     set streak_count = v_count,
         streak_slot  = v_n,
         stars = pf.stars + t.stars, gems = pf.gems + t.gems, coins = pf.coins + t.coins
    from (
      select coalesce(sum((r ->> 1)::int) filter (where r ->> 0 = 'STAR'), 0)::int as stars,
             coalesce(sum((r ->> 1)::int) filter (where r ->> 0 = 'GEM'),  0)::int as gems,
             coalesce(sum((r ->> 1)::int) filter (where r ->> 0 = 'COIN'), 0)::int as coins
        from jsonb_array_elements(v_rewards) r
    ) t
   where pf.uid = v_uid;

  return json_build_object('streak', v_count);
end;
$$;
