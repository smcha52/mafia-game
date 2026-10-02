-- ============================================================
-- 마피아 게임 · 새 직업: 생존자 (Survivor)
-- ============================================================
-- 중립 진영. 광대·살인자와는 또 다른 중립이다.
--
-- 능력 — 없다. 밤에 할 일도 없다.
--
-- 승리 — 목표 날의 낮이 끝날 때 살아 있으면 즉시 단독 승리, 게임 종료.
--   목표 날은 방의 최대 일수(max_days)로 정한다.
--     1~2일  생존자를 넣을 수 없다
--     3~4일  2일
--     5~7일  4일, 8~10일 6일, 11~13일 8일, 14~16일 10일 ... (3일마다 2일씩)
--   같은 낮에 다른 승리(광대 처형, 시민·마피아·살인자 승리)가 성립하면 그쪽이 먼저다.
--
-- 조사 결과 — 중립이므로 다른 중립과 같다.
--   경찰: 중립 · 기자: 시민 (중립 위장) · 낮 처형: 직업 공개
--
-- 구성 — 랜덤 구성에서만 나온다. 중립 후보에 들어간다.
-- ============================================================

-- ------------------------------------------------------------
-- 1. 스키마 확장
-- ------------------------------------------------------------

alter table public.private_roles drop constraint if exists private_roles_role_check;
alter table public.private_roles add constraint private_roles_role_check
  check (role in ('CITIZEN','MAFIA','POLICE','DOCTOR','BODYGUARD',
                  'DETECTIVE','REPORTER','MEDIUM','SPY','JESTER','ASSASSIN','KILLER',
                  'VIGILANTE','SHERIFF','FORGER','SURVIVOR'));

alter table public.rooms drop constraint if exists rooms_winner_check;
alter table public.rooms add constraint rooms_winner_check
  check (winner is null or winner in ('CITIZEN', 'MAFIA', 'JESTER', 'KILLER',
                                      'SURVIVOR', 'DRAW'));

-- ------------------------------------------------------------
-- 2. 진영과 목록
-- ------------------------------------------------------------

create or replace function public.team_of(p_role text)
returns text
language sql
immutable
as $$
  select case
    when p_role in ('MAFIA', 'SPY', 'ASSASSIN', 'FORGER')  then 'MAFIA'
    when p_role in ('JESTER', 'KILLER', 'SURVIVOR')        then 'NEUTRAL'
    else 'CITIZEN'
  end;
$$;

create or replace function public.toggleable_roles()
returns text[]
language sql
immutable
as $$
  select array['MAFIA', 'POLICE', 'DOCTOR', 'BODYGUARD', 'DETECTIVE',
               'REPORTER', 'MEDIUM', 'SPY', 'JESTER', 'ASSASSIN', 'KILLER',
               'VIGILANTE', 'SHERIFF', 'FORGER', 'SURVIVOR'];
$$;

-- ------------------------------------------------------------
-- 3. 목표 날 — 최대 일수가 2일 이하이면 null (생존자를 넣을 수 없다)
-- ------------------------------------------------------------

create or replace function public.survivor_target(p_max int)
returns int
language sql
immutable
as $$
  select case
    when p_max is null or p_max < 3 then null
    when p_max <= 4 then 2
    else 4 + 2 * ((p_max - 5) / 3)
  end;
$$;

grant execute on function public.survivor_target(int) to anon, authenticated;

-- ------------------------------------------------------------
-- 4. 랜덤 구성 — 중립 후보에 생존자를 더했다
-- ------------------------------------------------------------

create or replace function public.team_composition(
  p_count int, p_disabled text[] default '{}')
returns json
language plpgsql
immutable
as $$
declare
  off       text[] := coalesce(p_disabled, '{}');
  v_mafia   int;
  v_neutral int;
  v_open    int;
  v_mopen   int;
begin
  if p_count is null or p_count < 5 or p_count > 15 then
    raise exception '% 명은 지원하지 않습니다. (5~15명)', p_count;
  end if;

  v_mafia := case
    when p_count <= 6  then 1
    when p_count <= 8  then 2
    when p_count <= 11 then 3
    else 4
  end;
  v_neutral := case when p_count >= 9 then 2 else 1 end;

  -- 켜진 중립 직업보다 자리가 많으면 남는 자리는 시민 진영으로 간다
  select count(*) into v_open
    from unnest(array['JESTER', 'KILLER', 'SURVIVOR']) x
   where not (x = any (off));
  v_neutral := least(v_neutral, v_open);

  -- 마피아가 꺼져 있으면 마피아 진영은 켜진 스파이·암살자·위조범 수만큼만 채운다.
  -- 남는 자리는 시민 진영으로 간다. 0명이면 시작할 수 없다 (assign_roles).
  if 'MAFIA' = any (off) then
    select count(*) into v_mopen
      from unnest(array['SPY', 'ASSASSIN', 'FORGER']) x
     where not (x = any (off));
    v_mafia := least(v_mafia, v_mopen);
  end if;

  return json_build_object(
    'mafia',   v_mafia,
    'neutral', v_neutral,
    'citizen', p_count - v_mafia - v_neutral);
end;
$$;

grant execute on function public.team_composition(int, text[]) to anon, authenticated;

create or replace function public.random_composition(
  p_count int, p_disabled text[] default '{}')
returns text[]
language plpgsql
volatile
as $$
declare
  off      text[] := coalesce(p_disabled, '{}');
  v_teams  json;
  v_m      int;
  v_n      int;
  v_c      int;
  v_pool   text[];
  v_out    text[] := '{}';
begin
  v_teams := public.team_composition(p_count, off);
  v_m := (v_teams ->> 'mafia')::int;
  v_n := (v_teams ->> 'neutral')::int;
  v_c := (v_teams ->> 'citizen')::int;

  -- 마피아 진영
  --   마피아가 켜져 있으면 첫 자리는 마피아, 나머지는 켜진 스파이·암살자·위조범과 마피아 중에서.
  --   마피아가 꺼져 있으면 켜진 스파이·암살자·위조범으로만 채운다 (자리 수는 이미 그 이하).
  if 'MAFIA' = any (off) then
    v_out := v_out || array(
      select x from unnest(array['SPY', 'ASSASSIN', 'FORGER']) x
       where not (x = any (off))
       order by random() limit v_m);
  else
    v_out := v_out || 'MAFIA'::text;
    if v_m > 1 then
      v_pool := array(select x from unnest(array['SPY', 'ASSASSIN', 'FORGER']) x where not (x = any (off)))
                || array_fill('MAFIA'::text, array[v_m - 1]);
      v_out := v_out || array(select x from unnest(v_pool) x order by random() limit v_m - 1);
    end if;
  end if;

  -- 중립: 켜진 중립 직업 중에서 (자리 수는 이미 켜진 직업 수 이하)
  if v_n > 0 then
    v_out := v_out || array(
      select x from unnest(array['JESTER', 'KILLER', 'SURVIVOR']) x
       where not (x = any (off))
       order by random() limit v_n);
  end if;

  -- 시민 진영: 켜진 시민 직업과 시민 중에서
  v_pool := array(
              select x from unnest(array['POLICE', 'DOCTOR', 'BODYGUARD', 'DETECTIVE',
                                         'REPORTER', 'MEDIUM', 'VIGILANTE', 'SHERIFF']) x
               where not (x = any (off)))
            || array_fill('CITIZEN'::text, array[v_c]);
  v_out := v_out || array(select x from unnest(v_pool) x order by random() limit v_c);

  if coalesce(array_length(v_out, 1), 0) <> p_count then
    raise exception '랜덤 구성 오류: %명 구성의 직업 수가 %개입니다.',
      p_count, coalesce(array_length(v_out, 1), 0);
  end if;

  return v_out;
end;
$$;

revoke all on function public.random_composition(int, text[]) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 5. 배정 — 0031 본문에 "최대 일수 2일 이하면 생존자 제외" 를 더했다
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
  v_max    int;
  v_count  int;
  v_i      int := 1;
  v_uid    uuid;
  v_role   text;
  v_team   text;
begin
  select count(*) into v_count from public.players pl where pl.room_id = p_room_id;
  select r.disabled_roles, r.random_roles, r.max_days into v_off, v_random, v_max
    from public.rooms r where r.id = p_room_id;

  -- 최대 일수가 2일 이하이면 생존자는 이길 날이 없으므로 넣지 않는다
  if public.survivor_target(v_max) is null then
    v_off := coalesce(v_off, '{}') || 'SURVIVOR'::text;
  end if;

  if coalesce(v_random, true) then
    v_roles := public.random_composition(v_count, coalesce(v_off, '{}'));
  else
    v_roles := public.role_composition(v_count, coalesce(v_off, '{}'));
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
-- 6. 낮 처리 — 0023 본문에 생존자 승리를 더했다
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
  v_team     text := null;
  v_role     text := null;
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

  if coalesce(v_ties, 0) = 1 and v_target is not null then
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
    'executed',     v_executed,
    'tie',          coalesce(v_ties, 0) > 1,
    'executedTeam', case when v_team = 'NEUTRAL' then null else v_team end,
    'executedRole', case when v_team = 'NEUTRAL' then v_role else null end))
  on conflict (room_id, day_number, kind) do update
    set payload = public.public_results.payload || excluded.payload;

  v_winner := public.check_winner(p_room_id, v_executed);
  if v_winner is not null then
    perform public.end_game(p_room_id, v_winner);
    return;
  end if;

  -- 생존자: 목표 날의 낮이 끝날 때 살아 있으면 단독 승리 (§4.1-3)
  if v_day >= coalesce(public.survivor_target(v_max), v_max + 1) and exists (
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

  perform public.enter_phase(p_room_id, 'NIGHT', v_day + 1);
end;
$$;
revoke all on function public.resolve_day(uuid) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 7. 암살자가 생존자를 찍을 수 있게 한다
-- ------------------------------------------------------------

create or replace function public.submit_assassination(
  p_room_id uuid, p_target_uid uuid, p_guess text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_room    public.rooms%rowtype;
  v_role    text;
  v_alive   boolean;
  v_dead    uuid;
  v_winner  text;
  v_d_sub   int;
  v_d_exp   int;
begin
  select * into v_room from public.rooms r where r.id = p_room_id for update;
  if not found then
    raise exception '존재하지 않는 방입니다.';
  end if;
  if v_room.phase not in ('NIGHT', 'DAY') then
    raise exception '지금은 저격할 수 없습니다.';
  end if;

  select pr.role into v_role
    from public.private_roles pr
   where pr.room_id = p_room_id and pr.uid = v_uid;
  if not found then
    raise exception '이 방의 참가자가 아닙니다.';
  end if;
  if v_role <> 'ASSASSIN' then
    raise exception '암살자만 사용할 수 있습니다.';
  end if;

  select pl.alive into v_alive
    from public.players pl
   where pl.room_id = p_room_id and pl.uid = v_uid;
  if not v_alive then
    raise exception '사망한 참가자는 능력을 사용할 수 없습니다.';
  end if;

  if exists (
    select 1 from public.assassinations a
     where a.room_id = p_room_id and a.day_number = v_room.day_number
       and a.phase = v_room.phase and a.actor_uid = v_uid
  ) then
    raise exception '이번 %에는 이미 저격했습니다.',
      case when v_room.phase = 'NIGHT' then '밤' else '낮' end;
  end if;

  if not public.can_assassinate(p_room_id) then
    raise exception '상대가 모두 시민이면 저격할 수 없습니다.';
  end if;

  if p_target_uid = v_uid then
    raise exception '자신을 지목할 수 없습니다.';
  end if;
  if not exists (
    select 1 from public.players pl
     where pl.room_id = p_room_id and pl.uid = p_target_uid and pl.alive = true
  ) then
    raise exception '살아 있는 참가자만 지목할 수 있습니다.';
  end if;

  if p_guess is null or p_guess not in
     ('CITIZEN','MAFIA','POLICE','DOCTOR','BODYGUARD',
      'DETECTIVE','REPORTER','MEDIUM','SPY','JESTER','ASSASSIN','KILLER','VIGILANTE','SHERIFF','FORGER','SURVIVOR') then
    raise exception '직업을 선택해 주세요.';
  end if;

  insert into public.assassinations
    (room_id, day_number, phase, actor_uid, target_uid, guess_role)
  values
    (p_room_id, v_room.day_number, v_room.phase, v_uid, p_target_uid, p_guess);

  -- 밤이면 밤 처리 때 함께 계산한다
  if v_room.phase = 'NIGHT' then
    return json_build_object('resolved', false, 'phase', 'NIGHT');
  end if;

  -- 낮이면 즉시 처리한다
  v_dead := public.apply_assassination(p_room_id, v_room.day_number, 'DAY', v_uid);

  -- 낮 사망자를 공개 결과에 남긴다. executed 는 낮 처리에서 합쳐진다.
  if v_dead is not null then
    insert into public.public_results (room_id, day_number, kind, payload)
    values (p_room_id, v_room.day_number, 'DAY',
            jsonb_build_object('dayDeaths', jsonb_build_array(v_dead)))
    on conflict (room_id, day_number, kind) do update
      set payload = public.public_results.payload
                    || jsonb_build_object('dayDeaths',
                         coalesce(public.public_results.payload -> 'dayDeaths', '[]'::jsonb)
                         || jsonb_build_array(v_dead));
  end if;

  v_winner := public.check_winner(p_room_id);
  if v_winner is not null then
    perform public.end_game(p_room_id, v_winner);
    return json_build_object('resolved', true, 'phase', 'DAY', 'ended', true);
  end if;

  -- 사망으로 투표 인원이 줄어 낮이 이미 끝났을 수 있다
  select count(*) into v_d_exp
    from public.players pl where pl.room_id = p_room_id and pl.alive = true;
  select count(*) into v_d_sub
    from public.day_votes d
   where d.room_id = p_room_id and d.day_number = v_room.day_number;

  if v_d_sub >= v_d_exp then
    perform public.resolve_day(p_room_id);
  end if;

  return json_build_object('resolved', true, 'phase', 'DAY');
end;
$$;

grant execute on function public.submit_assassination(uuid, uuid, text) to anon, authenticated;
