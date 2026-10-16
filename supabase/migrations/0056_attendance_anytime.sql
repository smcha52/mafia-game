-- ============================================================
-- 마피아 게임 · 출석은 언제 해도 이어진다
-- ============================================================
-- 0052·0055 에서는 날짜가 시간으로만 넘어가서, 출석하지 않은 날의 보상은 사라졌다.
-- 이제 출석할 때마다 하루씩 넘어간다. 며칠 빠져도 다음에 출석하면 이어서 다음 날 보상을 받는다.
-- 하루(한국 시간 자정 ~ 자정)에 한 번만 출석할 수 있다. 30일을 다 받으면 1일부터 다시 시작한다.
-- 보상이 없는 날(5·10·15·20·25일)도 출석해야 다음 날로 넘어간다.
-- 연속 출석(0053)은 그대로다.
--
-- 0055 를 먼저 실행해야 한다 (attendance_next 를 쓴다).
-- attendance_claims 는 더 쓰지 않는다. 기존 기록은 아래에서 옮긴다.
-- ============================================================

-- ------------------------------------------------------------
-- 1. 테이블
-- ------------------------------------------------------------

-- attendance_count = 지금까지 출석한 횟수, attendance_last = 마지막으로 출석한 한국 날짜
alter table public.profiles add column if not exists attendance_count int not null default 0 check (attendance_count >= 0);
alter table public.profiles add column if not exists attendance_last  date;

-- 기존 계정은 이번 바퀴에서 마지막으로 받은 날 다음부터 이어 간다. 다시 실행해도 결과는 같다
update public.profiles pf
   set attendance_count = t.last_day,
       attendance_last  = t.last_date
  from (
    select c.uid,
           max(c.slot) - (public.attendance_slot(p.attendance_start)
                          - public.attendance_slot(p.attendance_start) % 30) + 1 as last_day,
           max((c.claimed_at at time zone 'Asia/Seoul')::date) as last_date
      from public.attendance_claims c
      join public.profiles p on p.uid = c.uid
     where c.slot >= public.attendance_slot(p.attendance_start)
                     - public.attendance_slot(p.attendance_start) % 30
     group by c.uid, p.attendance_start
  ) t
 where pf.uid = t.uid and pf.attendance_last is null;

-- ------------------------------------------------------------
-- 2. RPC — 내 출석
-- ------------------------------------------------------------
-- { day: 오늘 칸(1~30), checked: 오늘 출석했는지, next: 다음 출석이 되는 시각,
--   days: [{ day, rewards: [{ type, amount }], claimed }] }
create or replace function public.my_attendance()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_count   int;
  v_checked boolean;
  v_done    int;
begin
  if public.attendance_begin(v_uid) is null then
    raise exception '로그인이 필요합니다.';
  end if;

  select pf.attendance_count, coalesce(pf.attendance_last = (now() at time zone 'Asia/Seoul')::date, false)
    into v_count, v_checked
    from public.profiles pf where pf.uid = v_uid;

  -- 이번 바퀴에 받은 칸 수. 30일째를 받은 다음 날은 새 바퀴라 0 이다
  v_done := case when v_checked then (v_count - 1) % 30 + 1 else v_count % 30 end;

  return json_build_object(
    'day',     case when v_checked then v_done else v_done + 1 end,
    'checked', v_checked,
    'next',    public.attendance_next(),
    'days', (
      select json_agg(json_build_object(
               'day',     d,
               'rewards', coalesce((
                 select jsonb_agg(jsonb_build_object('type', r ->> 0, 'amount', (r ->> 1)::int))
                   from jsonb_array_elements(public.attendance_rewards(d)) r), '[]'::jsonb),
               'claimed', d <= v_done)
             order by d)
        from generate_series(1, 30) d)
  );
end;
$$;

-- ------------------------------------------------------------
-- 3. RPC — 출석하고 그날 보상 받기
-- ------------------------------------------------------------
create or replace function public.claim_attendance()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_today   date := (now() at time zone 'Asia/Seoul')::date;
  v_count   int;
  v_last    date;
  v_day     int;
  v_rewards jsonb;
begin
  if public.attendance_begin(v_uid) is null then
    raise exception '로그인이 필요합니다.';
  end if;

  -- 같은 사람의 요청이 겹쳐도 한 번만 세도록 프로필을 잠근다
  select pf.attendance_count, pf.attendance_last into v_count, v_last
    from public.profiles pf where pf.uid = v_uid for update;

  if v_last = v_today then
    raise exception '오늘은 이미 출석했습니다.';
  end if;

  v_day     := v_count % 30 + 1;
  v_rewards := public.attendance_rewards(v_day);

  update public.profiles pf
     set attendance_count = v_count + 1,
         attendance_last  = v_today,
         stars = pf.stars + t.stars, gems = pf.gems + t.gems, coins = pf.coins + t.coins
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
