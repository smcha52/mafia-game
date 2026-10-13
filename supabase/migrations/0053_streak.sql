-- ============================================================
-- 마피아 게임 · 연속 출석
-- ============================================================
-- 출석(0052)과 같은 날짜를 쓴다. 튜토리얼을 처음 마친 순간부터 24시간이 하루다.
-- 연속 출석 화면에서 하루에 한 번 출석한다. 어제 출석했으면 하루가 더해지고,
-- 하루라도 빠지면 0일로 돌아가 다음 출석이 1일이 된다. 끝이 없다.
-- 출석 보상(0052)을 받는 것과는 따로 센다.
--
-- 보상은 출석(0052 attendance_rewards)과 같다. 연속 1일째가 출석 1일 보상, 30일째가
-- 30일 보상이고, 31일째부터 다시 1일 보상이다. 연속 일수는 30일을 넘어도 계속 센다.
-- 보상이 없는 날(5·10·15·20·25일째)에도 출석은 해야 이어진다.
-- profiles 는 쓰기 정책이 없으므로(0046) 연속 출석은 RPC 로만 한다.
-- ============================================================

-- ------------------------------------------------------------
-- 1. 테이블
-- ------------------------------------------------------------

-- streak_slot = 마지막으로 출석한 날 (출석이 시작된 뒤 지난 날 수, 0052 의 slot 과 같다)
-- streak_count = 그날까지 이어진 연속 출석 일수
alter table public.profiles add column if not exists streak_count int not null default 0 check (streak_count >= 0);
alter table public.profiles add column if not exists streak_slot  int;

-- ------------------------------------------------------------
-- 2. 연속 출석 규칙 (내부용)
-- ------------------------------------------------------------

-- 연속 p_streak 일째에 출석하면 받는 보상 [[재화, 개수], ...]. 없으면 빈 배열
create or replace function public.streak_rewards(p_streak int)
returns jsonb
language sql
immutable
as $$
  select public.attendance_rewards((p_streak - 1) % 30 + 1);
$$;

-- ------------------------------------------------------------
-- 3. RPC — 내 연속 출석
-- ------------------------------------------------------------
-- { streak: 지금 이어지고 있는 일수 (끊겼으면 0), checked: 오늘 출석했는지,
--   next: 다음 날이 되는 시각, day: 30일 표에서 오늘 칸(1~30),
--   days: [{ day, rewards: [{ type, amount }], claimed }] }
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

  v_n := floor(extract(epoch from now() - v_start) / 86400)::int;
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
    'next',    v_start + interval '1 day' * (v_n + 1),
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

revoke all on function public.my_streak() from public, anon;
grant execute on function public.my_streak() to authenticated;

-- ------------------------------------------------------------
-- 4. RPC — 오늘 연속 출석하기
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

  v_n := floor(extract(epoch from now() - v_start) / 86400)::int;
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

revoke all on function public.claim_streak() from public, anon;
grant execute on function public.claim_streak() to authenticated;
