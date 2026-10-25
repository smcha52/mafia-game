-- ============================================================
-- 마피아 게임 · 생존자 승리 조건 변경 (목표 날)
-- ============================================================
-- 생존자 승률이 맞지 않아 목표 날을 최대 일수와 인원수로 다시 정한다.
--
-- 최대 일수별 기본 목표 날
--   1~3일    1일
--   4~8일    2일
--   9~12일   3일
--   13~20일  4일
--   21~50일  5일
--
-- 인원수별 추가 일수
--   5~7명    +0일
--   8~11명   +1일
--   12~15명  +2일
--
-- 목표 날이 최대 일수를 넘으면 이길 날이 없으므로 생존자를 넣지 않는다 (null).
--   예) 최대 1일 · 8명 → 목표 2일 > 1일 → 생존자 없음
--
-- 인원수는 게임에 참가한 사람 수다. 진행 중 나간 사람도 사망 처리될 뿐
-- players 에 남으므로 시작할 때와 같다.
--
-- 이전 survivor_target(int) 를 쓰던 assign_roles(0041) · resolve_day(0043) 를
-- 인원수를 넘기도록 바꾼다. 화면 survivorTarget() 과 일치해야 한다.
-- ============================================================

-- ------------------------------------------------------------
-- 1. 목표 날
-- ------------------------------------------------------------

create or replace function public.survivor_target(p_max int, p_players int)
returns int
language sql
immutable
as $$
  select case
    when p_max is null then null
    when t.target > p_max then null
    else t.target
  end
  from (
    select
      case
        when p_max <= 3  then 1
        when p_max <= 8  then 2
        when p_max <= 12 then 3
        when p_max <= 20 then 4
        else 5
      end
      + case
          when coalesce(p_players, 5) >= 12 then 2
          when coalesce(p_players, 5) >= 8  then 1
          else 0
        end as target
  ) t;
$$;

grant execute on function public.survivor_target(int, int) to anon, authenticated;

-- 예전 함수는 더 쓰지 않는다
drop function if exists public.survivor_target(int);

-- ------------------------------------------------------------
-- 2. 직업 배정 — 인원수를 넘긴다 (0041 과 나머지는 같다)
-- ------------------------------------------------------------

create or replace function public.assign_roles(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_roles  text[];
  v_off    text[];
  v_random boolean;
  v_rmax   jsonb;
  v_max    int;
  v_count  int;
  v_i      int := 1;
  v_uid    uuid;
  v_role   text;
  v_team   text;
begin
  select count(*) into v_count from public.players pl where pl.room_id = p_room_id;
  select r.disabled_roles, r.random_roles, r.max_days, r.role_max
    into v_off, v_random, v_max, v_rmax
    from public.rooms r where r.id = p_room_id;

  -- 목표 날이 최대 일수를 넘으면 생존자는 이길 날이 없으므로 넣지 않는다
  if public.survivor_target(v_max, v_count) is null then
    v_off := coalesce(v_off, '{}') || 'SURVIVOR'::text;
  end if;

  if coalesce(v_random, true) then
    v_roles := public.random_composition(v_count, coalesce(v_off, '{}'), coalesce(v_rmax, '{}'));
  else
    -- 고정 구성은 끈 직업 자리를 시민이 채우므로 시민 끄기는 무시한다
    v_roles := public.role_composition(v_count, array_remove(coalesce(v_off, '{}'), 'CITIZEN'));
  end if;

  -- 마피아 진영이 한 명도 없으면 시작과 동시에 시민이 이기므로 시작을 막는다.
  -- start_game 안에서 불리므로 여기서 거절하면 시작 전체가 취소된다.
  if not exists (select 1 from unnest(v_roles) x where public.team_of(x) = 'MAFIA') then
    raise exception '마피아 진영 직업이 하나도 없어 게임을 시작할 수 없습니다.';
  end if;

  -- 무작위 순서로 배정한다
  for v_uid in
    select pl.uid from public.players pl
     where pl.room_id = p_room_id
     order by random()
  loop
    v_role := v_roles[v_i];
    v_team := public.team_of(v_role);

    insert into public.private_roles (room_id, uid, role, team)
    values (p_room_id, v_uid, v_role, v_team)
    on conflict (room_id, uid) do update set role = excluded.role, team = excluded.team;

    if v_role = 'JESTER' then
      update public.rooms r set jester_uid = v_uid where r.id = p_room_id;
    end if;

    v_i := v_i + 1;
  end loop;
end;
$$;

revoke all on function public.assign_roles(uuid) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 3. 낮 처리 — 인원수를 넘긴다 (0043 과 나머지는 같다)
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
  v_top      int;
  v_votes    jsonb;
  v_skip     int;
  v_skipped  boolean;
  v_executed uuid := null;
  v_team     text := null;
  v_role     text := null;
  v_winner   text;
  v_count    int;
begin
  select r.day_number, r.max_days into v_day, v_max
    from public.rooms r where r.id = p_room_id;

  -- 생존자 목표 날은 게임 인원으로 정한다. 진행 중에는 참가자가 지워지지 않는다
  select count(*) into v_count from public.players pl where pl.room_id = p_room_id;

  -- 건너뛰기 표 수
  select count(*) into v_skip
    from public.day_votes d
   where d.room_id = p_room_id and d.day_number = v_day
     and d.target_uid = public.skip_vote_uid();

  with tally as (
    select d.target_uid as t_uid, count(*) as c
      from public.day_votes d
     where d.room_id = p_room_id and d.day_number = v_day
       and d.target_uid <> public.skip_vote_uid()
     group by d.target_uid
  ), mx as (
    select max(c) as m from tally
  )
  select count(*), (array_agg(tally.t_uid))[1], max(mx.m)
    into v_ties, v_target, v_top
    from tally join mx on tally.c = mx.m;

  -- 사람별 득표 수 (많은 순)
  select coalesce(jsonb_agg(jsonb_build_object('uid', t.t_uid, 'count', t.c)
                            order by t.c desc), '[]'::jsonb)
    into v_votes
    from (
      select d.target_uid as t_uid, count(*) as c
        from public.day_votes d
       where d.room_id = p_room_id and d.day_number = v_day
         and d.target_uid <> public.skip_vote_uid()
       group by d.target_uid
    ) t;

  -- 건너뛰기를 후보 하나처럼 센다. 최다 득표자보다 많거나 같으면 아무도 처형하지 않는다.
  -- 건너뛰기가 생존자 과반수면 누구도 그보다 많을 수 없으므로 여기에 포함된다.
  v_skipped := v_skip > 0 and v_skip >= coalesce(v_top, 0);

  if not v_skipped and coalesce(v_ties, 0) = 1 and v_target is not null then
    update public.players pl
       set alive = false
     where pl.room_id = p_room_id and pl.uid = v_target and pl.alive = true;
    if found then
      v_executed := v_target;
    end if;
  end if;

  if v_executed is not null then
    select pr.team, pr.role into v_team, v_role
      from public.private_roles pr
     where pr.room_id = p_room_id and pr.uid = v_executed;
  end if;

  insert into public.public_results (room_id, day_number, kind, payload)
  values (p_room_id, v_day, 'DAY', jsonb_build_object(
    'executed',      v_executed,
    'executedVotes', case when v_executed is not null then v_top else null end,
    'votes',         v_votes,
    'tie',           not v_skipped and coalesce(v_ties, 0) > 1,
    'skipVotes',     v_skip,
    'skipped',       v_skipped,
    'executedTeam',  case when v_team = 'NEUTRAL' then null else v_team end,
    'executedRole',  case when v_team = 'NEUTRAL' then v_role else null end))
  on conflict (room_id, day_number, kind) do update
    set payload = public.public_results.payload || excluded.payload;

  v_winner := public.check_winner(p_room_id, v_executed);
  if v_winner is not null then
    perform public.end_game(p_room_id, v_winner);
    return;
  end if;

  -- 생존자: 목표 날의 낮이 끝날 때 살아 있으면 단독 승리 (§4.1-3)
  if v_day >= coalesce(public.survivor_target(v_max, v_count), v_max + 1) and exists (
    select 1
      from public.private_roles pr
      join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
     where pr.room_id = p_room_id and pr.role = 'SURVIVOR' and pl.alive = true
  ) then
    perform public.end_game(p_room_id, 'SURVIVOR');
    return;
  end if;

  if v_day >= v_max then
    perform public.end_game(p_room_id, 'DRAW');
    return;
  end if;

  -- 밤은 결과 시간이 끝난 뒤 tick_phase 가 연다
  perform public.enter_phase(p_room_id, 'DAY_RESULT', v_day);
end;
$$;
revoke all on function public.resolve_day(uuid) from public, anon, authenticated;
