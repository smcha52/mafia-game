-- ============================================================
-- 마피아 게임 · 제한시간 단축 + 무승부 종료
-- ============================================================
-- 요구사항 §4 에 없는 추가 규칙이다.
--
-- 1. 기본 제한시간을 줄인다
--      밤 90초 -> 30초, 낮 180초 -> 60초
--    방장이 대기실에서 set_timers 로 계속 조절할 수 있다.
--
-- 2. 최대 일수에 도달하면 무승부로 끝낸다
--      기본 15일차. 15일차 낮 투표까지 끝나도 승부가 안 나면 무승부.
--    §4 의 세 승리 조건을 먼저 검사하고, 아무도 이기지 못했을 때만
--    무승부가 된다. 광대 우선 판정(§4.1)도 그대로 유지된다.
-- ============================================================

-- ------------------------------------------------------------
-- 1. 기본값 변경과 최대 일수 추가
-- ------------------------------------------------------------

alter table public.rooms alter column night_seconds set default 30;
alter table public.rooms alter column day_seconds   set default 60;

alter table public.rooms
  add column if not exists max_days int not null default 15
  check (max_days between 1 and 50);

-- 무승부를 승자 값으로 허용한다
alter table public.rooms drop constraint if exists rooms_winner_check;
alter table public.rooms add constraint rooms_winner_check
  check (winner is null or winner in ('CITIZEN', 'MAFIA', 'JESTER', 'DRAW'));

-- ------------------------------------------------------------
-- 2. 낮 처리 — 최대 일수에 도달하면 무승부
-- ------------------------------------------------------------

create or replace function public.resolve_day(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day      int;
  v_max      int;
  v_target   uuid;
  v_ties     int;
  v_executed uuid := null;
  v_winner   text;
begin
  select r.day_number, r.max_days into v_day, v_max
    from public.rooms r where r.id = p_room_id;

  with tally as (
    select d.target_uid as t_uid, count(*) as c
      from public.day_votes d
     where d.room_id = p_room_id and d.day_number = v_day
     group by d.target_uid
  ), mx as (
    select max(c) as m from tally
  )
  select count(*), (array_agg(tally.t_uid))[1]
    into v_ties, v_target
    from tally join mx on tally.c = mx.m;

  -- 동점이면 아무도 처형하지 않는다 (D-2)
  if coalesce(v_ties, 0) = 1 and v_target is not null then
    update public.players pl
       set alive = false
     where pl.room_id = p_room_id and pl.uid = v_target and pl.alive = true;
    if found then
      v_executed := v_target;
    end if;
  end if;

  insert into public.public_results (room_id, day_number, kind, payload)
  values (p_room_id, v_day, 'DAY',
          jsonb_build_object('executed', v_executed))
  on conflict (room_id, day_number, kind) do update set payload = excluded.payload;

  -- 광대 승리를 먼저 검사한다 (§4.1)
  v_winner := public.check_winner(p_room_id, v_executed);
  if v_winner is not null then
    perform public.end_game(p_room_id, v_winner);
    return;
  end if;

  -- 아무도 이기지 못한 채 최대 일수에 도달하면 무승부
  if v_day >= v_max then
    perform public.end_game(p_room_id, 'DRAW');
    return;
  end if;

  perform public.enter_phase(p_room_id, 'NIGHT', v_day + 1);
end;
$$;

revoke all on function public.resolve_day(uuid) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 3. 방장이 제한시간과 최대 일수를 조절한다
-- ------------------------------------------------------------
-- p_max_days 를 생략하면 기존 값을 유지한다.
--
-- 인자를 추가할 때는 이전 시그니처를 반드시 지워야 한다.
-- create or replace 는 인자가 다르면 "교체" 가 아니라 "추가" 라서
-- 두 함수가 공존하게 되고, PostgREST 가 어느 쪽인지 정하지 못해
-- PGRST203(함수 중복) 오류가 난다.
drop function if exists public.set_timers(uuid, int, int);

create or replace function public.set_timers(
  p_room_id uuid, p_night int, p_day int, p_max_days int default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room public.rooms%rowtype;
begin
  select * into v_room from public.rooms r where r.id = p_room_id;
  if not found then
    raise exception '존재하지 않는 방입니다.';
  end if;
  if v_room.host_uid <> auth.uid() then
    raise exception '방장만 제한시간을 바꿀 수 있습니다.';
  end if;
  if v_room.phase <> 'LOBBY' then
    raise exception '대기실에서만 바꿀 수 있습니다.';
  end if;

  update public.rooms r
     set night_seconds = p_night,
         day_seconds   = p_day,
         max_days      = coalesce(p_max_days, r.max_days)
   where r.id = p_room_id;
end;
$$;

grant execute on function public.set_timers(uuid, int, int, int) to anon, authenticated;
