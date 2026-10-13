-- ============================================================
-- 마피아 게임 · 출석
-- ============================================================
-- 튜토리얼을 처음 마친 순간(profiles.attendance_start)부터 24시간마다 하루씩 넘어간다.
-- 1일부터 30일까지 가고, 30일이 지나면 다시 1일부터 시작한다.
-- 그날 보상은 그날에만 받을 수 있다. 지나간 날의 보상은 받지 못한다.
--
--   날짜                 보상
--   1 · 6 · 11 · 16 · 21   코인 5
--   2 · 7 · 12 · 17 · 22   코인 10
--   3 · 8 · 13 · 18 · 23   별 3
--   4 · 9 · 14 · 19 · 24   별 5
--   5 · 10 · 15 · 20 · 25  나중에 정한다 (지금은 없음)
--   26                   별 10
--   27                   별 15
--   28                   별 20
--   29                   보석 2
--   30                   보석 3 + 나중에 정한다
--
-- 보상은 attendance_rewards 를 고치면 된다. 화면은 서버가 준 보상을 그대로 보여준다.
-- 이 마이그레이션 전에 튜토리얼을 마친 계정은 출석 화면을 처음 열 때부터 센다.
-- profiles 는 쓰기 정책이 없으므로(0046) 출석은 RPC 로만 한다.
-- ============================================================

-- ------------------------------------------------------------
-- 1. 테이블
-- ------------------------------------------------------------

alter table public.profiles add column if not exists attendance_start timestamptz;

-- 보상을 받은 날. slot = 출석이 시작된 뒤 지난 날 수 (0 이 첫 1일)
create table if not exists public.attendance_claims (
  uid        uuid not null references public.profiles (uid) on delete cascade,
  slot       int  not null check (slot >= 0),
  claimed_at timestamptz not null default now(),
  primary key (uid, slot)
);

-- 직접 읽기·쓰기는 막고 RPC 로만 다룬다
alter table public.attendance_claims enable row level security;
revoke all on public.attendance_claims from anon, authenticated;

-- ------------------------------------------------------------
-- 2. 출석 규칙 (내부용)
-- ------------------------------------------------------------

-- 그날 받는 보상 [[재화, 개수], ...]. 없으면 빈 배열
create or replace function public.attendance_rewards(p_day int)
returns jsonb
language sql
immutable
as $$
  select case
    when p_day between 1 and 25 then
      case (p_day - 1) % 5
        when 0 then '[["COIN",5]]'
        when 1 then '[["COIN",10]]'
        when 2 then '[["STAR",3]]'
        when 3 then '[["STAR",5]]'
        else '[]'
      end
    when p_day = 26 then '[["STAR",10]]'
    when p_day = 27 then '[["STAR",15]]'
    when p_day = 28 then '[["STAR",20]]'
    when p_day = 29 then '[["GEM",2]]'
    when p_day = 30 then '[["GEM",3]]'
    else '[]'
  end::jsonb;
$$;

-- 출석이 시작된 시각. 아직 시작하지 않았으면 지금부터 센다. 프로필이 없으면 null
create or replace function public.attendance_begin(p_uid uuid)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_start timestamptz;
begin
  update public.profiles pf set attendance_start = now()
   where pf.uid = p_uid and pf.attendance_start is null;
  select pf.attendance_start into v_start from public.profiles pf where pf.uid = p_uid;
  return v_start;
end;
$$;

revoke all on function public.attendance_begin(uuid) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 3. RPC — 출석 시작 (튜토리얼을 처음 마쳤을 때)
-- ------------------------------------------------------------
create or replace function public.start_attendance()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.attendance_begin(auth.uid()) is null then
    raise exception '로그인이 필요합니다.';
  end if;
end;
$$;

revoke all on function public.start_attendance() from public, anon;
grant execute on function public.start_attendance() to authenticated;

-- ------------------------------------------------------------
-- 4. RPC — 내 출석
-- ------------------------------------------------------------
-- { day: 오늘 날짜(1~30), next: 다음 날이 되는 시각,
--   days: [{ day, rewards: [{ type, amount }], claimed }] }
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
  v_n := floor(extract(epoch from now() - v_start) / 86400)::int;

  return json_build_object(
    'day',  v_n % 30 + 1,
    'next', v_start + interval '1 day' * (v_n + 1),
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

revoke all on function public.my_attendance() from public, anon;
grant execute on function public.my_attendance() to authenticated;

-- ------------------------------------------------------------
-- 5. RPC — 오늘 보상 받기
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

  v_n       := floor(extract(epoch from now() - v_start) / 86400)::int;
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

revoke all on function public.claim_attendance() from public, anon;
grant execute on function public.claim_attendance() to authenticated;
