-- ============================================================
-- 마피아 게임 · 2단계-1 (직업 배정 + 마피아/시민 + 밤낮 진행)
-- ============================================================
-- 요구사항 §8.2 구현 순서 1번: 마피아와 시민
--
-- 이 단계에서 구현하는 것
--   · 인원별 직업 배정 (§5 구성표 전체)
--   · 비밀 직업 저장과 열람 제한 (§6)
--   · 마피아 밤 공격 투표 (§2.2)
--   · 낮 처형 투표
--   · 승리 조건 (§4 전체 — 광대 포함)
--
-- 아직 능력이 없는 직업(경찰·의사·경호원·탐정·기자·영매)은
-- 배정만 되고 시민처럼 행동한다. §8.2 순서대로 하나씩 추가한다.
--
-- 보안: 비밀 테이블에는 anon/authenticated 권한을 주지 않는다.
--       PostgREST 가 접근 자체를 못 하므로 RPC 를 통해서만 읽힌다.
-- ============================================================

-- ------------------------------------------------------------
-- 1. 방에 승자 기록 추가
-- ------------------------------------------------------------

alter table public.rooms
  add column if not exists winner text
  check (winner is null or winner in ('CITIZEN', 'MAFIA', 'JESTER'));

alter table public.rooms
  add column if not exists jester_uid uuid;

-- §7.1 players/{uid}/team.
-- 진행 중에 채우면 진영이 그대로 노출되므로 게임 종료 시에만 채운다.
alter table public.players
  add column if not exists team text
  check (team is null or team in ('CITIZEN', 'MAFIA', 'NEUTRAL'));

-- ------------------------------------------------------------
-- 2. 비밀 테이블 — 권한을 주지 않는다
-- ------------------------------------------------------------

create table if not exists public.private_roles (
  room_id uuid not null references public.rooms(id) on delete cascade,
  uid     uuid not null,
  role    text not null check (role in (
            'CITIZEN','MAFIA','POLICE','DOCTOR','BODYGUARD',
            'DETECTIVE','REPORTER','MEDIUM','SPY','JESTER')),
  team    text not null check (team in ('CITIZEN','MAFIA','NEUTRAL')),
  primary key (room_id, uid)
);

-- 밤 행동. 하루에 행동 종류별로 한 번만 제출할 수 있다.
create table if not exists public.night_actions (
  room_id     uuid not null references public.rooms(id) on delete cascade,
  day_number  int  not null,
  actor_uid   uuid not null,
  action      text not null check (action in (
                'MAFIA_VOTE','DOCTOR','BODYGUARD','POLICE',
                'DETECTIVE','REPORTER','MEDIUM')),
  target_uid  uuid,
  target_uid2 uuid,
  created_at  timestamptz not null default now(),
  primary key (room_id, day_number, actor_uid, action)
);

-- 낮 처형 투표. 제출 후 변경 불가 (§2.9 스파이 규칙과 동일하게 전원 적용)
create table if not exists public.day_votes (
  room_id    uuid not null references public.rooms(id) on delete cascade,
  day_number int  not null,
  voter_uid  uuid not null,
  target_uid uuid not null,
  created_at timestamptz not null default now(),
  primary key (room_id, day_number, voter_uid)
);

alter table public.private_roles  enable row level security;
alter table public.night_actions  enable row level security;
alter table public.day_votes      enable row level security;

-- 정책을 만들지 않는다 = 전면 거부.
-- 권한도 주지 않으므로 PostgREST 로는 존재조차 확인할 수 없다.
revoke all on public.private_roles from anon, authenticated;
revoke all on public.night_actions from anon, authenticated;
revoke all on public.day_votes     from anon, authenticated;

-- ------------------------------------------------------------
-- 3. 공개 결과 — 모든 참가자가 읽는다 (§6.1)
-- ------------------------------------------------------------

create table if not exists public.public_results (
  room_id     uuid not null references public.rooms(id) on delete cascade,
  day_number  int  not null,
  kind        text not null check (kind in ('NIGHT','DAY')),
  payload     jsonb not null,
  created_at  timestamptz not null default now(),
  primary key (room_id, day_number, kind)
);

alter table public.public_results enable row level security;

drop policy if exists "같은 방 공개결과 조회" on public.public_results;
create policy "같은 방 공개결과 조회"
  on public.public_results for select
  using (public.is_room_member(public_results.room_id));

grant select on public.public_results to anon, authenticated;
revoke insert, update, delete on public.public_results from anon, authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public'
       and tablename = 'public_results'
  ) then
    alter publication supabase_realtime add table public.public_results;
  end if;
end $$;

-- ------------------------------------------------------------
-- 4. 직업 구성표 (§5)
-- ------------------------------------------------------------

create or replace function public.role_composition(p_count int)
returns text[]
language plpgsql
immutable
as $$
declare
  v text[];
begin
  v := case p_count
    when 5  then array['MAFIA','POLICE','DOCTOR','CITIZEN','CITIZEN']
    when 6  then array['MAFIA','POLICE','DOCTOR','BODYGUARD','CITIZEN','CITIZEN']
    when 7  then array['MAFIA','MAFIA','POLICE','DOCTOR','JESTER','CITIZEN','CITIZEN']
    when 8  then array['MAFIA','MAFIA','POLICE','DOCTOR','BODYGUARD','JESTER','CITIZEN','CITIZEN']
    when 9  then array['MAFIA','MAFIA','SPY','POLICE','DOCTOR','DETECTIVE','CITIZEN','CITIZEN','CITIZEN']
    when 10 then array['MAFIA','MAFIA','SPY','POLICE','DOCTOR','BODYGUARD','DETECTIVE','CITIZEN','CITIZEN','CITIZEN']
    when 11 then array['MAFIA','MAFIA','SPY','POLICE','DOCTOR','BODYGUARD','DETECTIVE','REPORTER','CITIZEN','CITIZEN','CITIZEN']
    when 12 then array['MAFIA','MAFIA','MAFIA','SPY','POLICE','DOCTOR','BODYGUARD','DETECTIVE','REPORTER','JESTER','CITIZEN','CITIZEN']
    when 13 then array['MAFIA','MAFIA','MAFIA','SPY','POLICE','DOCTOR','BODYGUARD','DETECTIVE','REPORTER','MEDIUM','JESTER','CITIZEN','CITIZEN']
    when 14 then array['MAFIA','MAFIA','MAFIA','SPY','POLICE','DOCTOR','BODYGUARD','DETECTIVE','REPORTER','MEDIUM','JESTER','CITIZEN','CITIZEN','CITIZEN']
    when 15 then array['MAFIA','MAFIA','MAFIA','SPY','POLICE','DOCTOR','BODYGUARD','DETECTIVE','REPORTER','MEDIUM','JESTER','CITIZEN','CITIZEN','CITIZEN','CITIZEN']
    else null
  end;

  if v is null then
    raise exception '% 명은 지원하지 않습니다. (5~15명)', p_count;
  end if;

  -- §5.1 직업 수의 합계가 참가 인원과 정확히 일치하는지 검증
  if array_length(v, 1) <> p_count then
    raise exception '구성표 오류: %명 구성의 직업 수가 %개입니다.', p_count, array_length(v, 1);
  end if;

  return v;
end;
$$;

create or replace function public.team_of(p_role text)
returns text
language sql
immutable
as $$
  select case
    when p_role in ('MAFIA', 'SPY') then 'MAFIA'
    when p_role = 'JESTER'          then 'NEUTRAL'
    else 'CITIZEN'
  end;
$$;

-- ------------------------------------------------------------
-- 5. 직업 배정
-- ------------------------------------------------------------

create or replace function public.assign_roles(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_roles text[];
  v_count int;
  v_i     int := 1;
  v_uid   uuid;
  v_role  text;
  v_team  text;
begin
  select count(*) into v_count from public.players pl where pl.room_id = p_room_id;
  v_roles := public.role_composition(v_count);

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

    -- players.team 은 게임 종료 시에 채운다 (진행 중 노출 방지)
    if v_role = 'JESTER' then
      update public.rooms r set jester_uid = v_uid where r.id = p_room_id;
    end if;

    v_i := v_i + 1;
  end loop;
end;
$$;

-- ------------------------------------------------------------
-- 6. 승리 조건 (§4)
-- ------------------------------------------------------------
-- 검사 순서: 광대 → 시민 → 마피아
-- p_executed_uid 가 광대이면 즉시 광대 승리 (§4.1)

create or replace function public.check_winner(p_room_id uuid, p_executed_uid uuid default null)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_jester   uuid;
  v_mafia    int;
  v_citizen  int;
begin
  -- §4.1 광대 승리 — 다른 조건보다 먼저 검사한다
  if p_executed_uid is not null then
    select r.jester_uid into v_jester from public.rooms r where r.id = p_room_id;
    if v_jester is not null and v_jester = p_executed_uid then
      return 'JESTER';
    end if;
  end if;

  -- 광대는 양쪽 생존 인원 계산에서 제외한다 (§4.3)
  select
    count(*) filter (where pr.team = 'MAFIA'),
    count(*) filter (where pr.team = 'CITIZEN')
    into v_mafia, v_citizen
  from public.private_roles pr
  join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
  where pr.room_id = p_room_id and pl.alive = true;

  if v_mafia = 0 then
    return 'CITIZEN';          -- §4.2
  end if;
  if v_mafia >= v_citizen then
    return 'MAFIA';            -- §4.3
  end if;
  return null;
end;
$$;

-- ------------------------------------------------------------
-- 6-1. 게임 종료 처리 — 이때 비로소 진영을 공개한다
-- ------------------------------------------------------------

create or replace function public.end_game(p_room_id uuid, p_winner text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.players pl
     set team = pr.team
    from public.private_roles pr
   where pr.room_id = pl.room_id
     and pr.uid = pl.uid
     and pl.room_id = p_room_id;

  update public.rooms r
     set phase = 'ENDED', winner = p_winner
   where r.id = p_room_id;
end;
$$;

revoke all on function public.end_game(uuid, text) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 7. 밤 결과 처리 (§3)
-- ------------------------------------------------------------
-- 이 단계에서는 1·4·10·11 만 해당한다.
-- 의사/경호원/경찰/탐정/영매/기자는 이후 단계에서 이 함수에 끼워 넣는다.

create or replace function public.resolve_night(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day     int;
  v_target  uuid;
  v_ties    int;
  v_deaths  uuid[] := '{}';
  v_winner  text;
begin
  select r.day_number into v_day from public.rooms r where r.id = p_room_id;

  -- 1. 마피아 공격 대상 확정 — 최다 득표, 동점이면 공격 없음 (§2.2)
  with tally as (
    select n.target_uid as t_uid, count(*) as c
      from public.night_actions n
     where n.room_id = p_room_id and n.day_number = v_day
       and n.action = 'MAFIA_VOTE' and n.target_uid is not null
     group by n.target_uid
  ), mx as (
    select max(c) as m from tally
  )
  select count(*), (array_agg(tally.t_uid))[1]
    into v_ties, v_target
    from tally join mx on tally.c = mx.m;

  if coalesce(v_ties, 0) <> 1 then
    v_target := null;          -- 동점이거나 표가 없으면 공격하지 않는다
  end if;

  -- 4. 공격 대상 사망 처리
  --    (의사 치료·경호원 보호는 이후 단계에서 여기에 들어간다)
  if v_target is not null then
    update public.players pl
       set alive = false
     where pl.room_id = p_room_id and pl.uid = v_target and pl.alive = true;
    if found then
      v_deaths := array[v_target];
    end if;
  end if;

  insert into public.public_results (room_id, day_number, kind, payload)
  values (p_room_id, v_day, 'NIGHT',
          jsonb_build_object('nightDeaths', to_jsonb(v_deaths)))
  on conflict (room_id, day_number, kind) do update set payload = excluded.payload;

  -- 10. 승리 조건 확인
  v_winner := public.check_winner(p_room_id);
  if v_winner is not null then
    perform public.end_game(p_room_id, v_winner);
    return;
  end if;

  -- 11. 낮으로 이동
  update public.rooms r set phase = 'DAY' where r.id = p_room_id;
end;
$$;

-- ------------------------------------------------------------
-- 8. 낮 결과 처리
-- ------------------------------------------------------------

create or replace function public.resolve_day(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day      int;
  v_target   uuid;
  v_ties     int;
  v_executed uuid := null;
  v_winner   text;
begin
  select r.day_number into v_day from public.rooms r where r.id = p_room_id;

  -- 최다 득표자 처형. 동점이면 아무도 처형하지 않는다 (D-2)
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

  update public.rooms r
     set phase = 'NIGHT', day_number = v_day + 1
   where r.id = p_room_id;
end;
$$;

-- ------------------------------------------------------------
-- 9. start_game — 직업 배정을 붙인다
-- ------------------------------------------------------------

create or replace function public.start_game(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_room      public.rooms%rowtype;
  v_total     int;
  v_not_ready int;
begin
  select * into v_room from public.rooms r where r.id = p_room_id for update;
  if not found then
    raise exception '존재하지 않는 방입니다.';
  end if;
  if v_room.host_uid <> v_uid then
    raise exception '방장만 게임을 시작할 수 있습니다.';
  end if;
  if v_room.phase <> 'LOBBY' then
    raise exception '이미 시작된 게임입니다.';
  end if;

  select count(*) into v_total from public.players pl where pl.room_id = p_room_id;

  if v_total < 5 then
    raise exception '최소 5명이 필요합니다. (현재 %명)', v_total;
  end if;
  if v_total > 15 then
    raise exception '최대 15명까지 가능합니다. (현재 %명)', v_total;
  end if;

  select count(*) into v_not_ready
    from public.players pl
   where pl.room_id = p_room_id and pl.is_ready = false;

  if v_not_ready > 0 then
    raise exception '아직 준비하지 않은 참가자가 %명 있습니다.', v_not_ready;
  end if;

  update public.rooms r
     set phase = 'NIGHT', day_number = 1, started_at = now()
   where r.id = p_room_id;

  perform public.assign_roles(p_room_id);
end;
$$;

-- ------------------------------------------------------------
-- 10. RPC — 내 직업 확인 (§6.1)
-- ------------------------------------------------------------
-- 본인의 직업만 돌려준다. 마피아와 스파이에게만 마피아 진영 명단을 붙인다.

create or replace function public.my_role(p_room_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_role    text;
  v_team    text;
  v_mates   json;
begin
  select pr.role, pr.team into v_role, v_team
    from public.private_roles pr
   where pr.room_id = p_room_id and pr.uid = v_uid;

  if not found then
    raise exception '아직 직업이 배정되지 않았습니다.';
  end if;

  -- 마피아끼리는 서로를 알고, 스파이도 함께 안다 (§2.2, §2.9)
  if v_role in ('MAFIA', 'SPY') then
    select json_agg(json_build_object('uid', pl.uid, 'nickname', pl.nickname, 'role', pr.role)
                    order by pl.joined_at)
      into v_mates
      from public.private_roles pr
      join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
     where pr.room_id = p_room_id and pr.team = 'MAFIA';
  end if;

  return json_build_object('role', v_role, 'team', v_team, 'mafiaMembers', v_mates);
end;
$$;

-- ------------------------------------------------------------
-- 11. RPC — 밤 행동 제출
-- ------------------------------------------------------------

create or replace function public.submit_night_action(
  p_room_id uuid, p_action text, p_target_uid uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_room      public.rooms%rowtype;
  v_role      text;
  v_alive     boolean;
  v_expected  int;
  v_submitted int;
begin
  select * into v_room from public.rooms r where r.id = p_room_id;
  if not found then
    raise exception '존재하지 않는 방입니다.';
  end if;
  if v_room.phase <> 'NIGHT' then
    raise exception '밤에만 능력을 사용할 수 있습니다.';
  end if;

  select pr.role into v_role
    from public.private_roles pr
   where pr.room_id = p_room_id and pr.uid = v_uid;
  if not found then
    raise exception '이 방의 참가자가 아닙니다.';
  end if;

  select pl.alive into v_alive
    from public.players pl
   where pl.room_id = p_room_id and pl.uid = v_uid;
  if not v_alive then
    raise exception '사망한 참가자는 능력을 사용할 수 없습니다.';
  end if;

  -- 이 단계에서는 마피아 공격 투표만 받는다
  if p_action <> 'MAFIA_VOTE' then
    raise exception '아직 구현되지 않은 능력입니다: %', p_action;
  end if;
  if v_role <> 'MAFIA' then
    raise exception '마피아만 사용할 수 있습니다.';
  end if;

  -- 대상은 살아 있어야 한다
  if not exists (
    select 1 from public.players pl
     where pl.room_id = p_room_id and pl.uid = p_target_uid and pl.alive = true
  ) then
    raise exception '살아 있는 참가자만 지목할 수 있습니다.';
  end if;

  insert into public.night_actions (room_id, day_number, actor_uid, action, target_uid)
  values (p_room_id, v_room.day_number, v_uid, 'MAFIA_VOTE', p_target_uid)
  on conflict (room_id, day_number, actor_uid, action)
    do update set target_uid = excluded.target_uid, created_at = now();

  -- 살아 있는 마피아가 모두 제출했으면 밤을 처리한다
  -- (스파이는 밤 공격 투표에 참여하지 않는다 — §2.9)
  select count(*) into v_expected
    from public.private_roles pr
    join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
   where pr.room_id = p_room_id and pr.role = 'MAFIA' and pl.alive = true;

  select count(*) into v_submitted
    from public.night_actions n
   where n.room_id = p_room_id and n.day_number = v_room.day_number
     and n.action = 'MAFIA_VOTE';

  if v_submitted >= v_expected then
    perform public.resolve_night(p_room_id);
    return json_build_object('resolved', true);
  end if;

  return json_build_object('resolved', false,
                           'submitted', v_submitted, 'expected', v_expected);
end;
$$;

-- ------------------------------------------------------------
-- 12. RPC — 낮 처형 투표
-- ------------------------------------------------------------

create or replace function public.submit_day_vote(p_room_id uuid, p_target_uid uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_room      public.rooms%rowtype;
  v_alive     boolean;
  v_expected  int;
  v_submitted int;
begin
  select * into v_room from public.rooms r where r.id = p_room_id;
  if not found then
    raise exception '존재하지 않는 방입니다.';
  end if;
  if v_room.phase <> 'DAY' then
    raise exception '낮에만 투표할 수 있습니다.';
  end if;

  select pl.alive into v_alive
    from public.players pl
   where pl.room_id = p_room_id and pl.uid = v_uid;
  if not found then
    raise exception '이 방의 참가자가 아닙니다.';
  end if;
  if not v_alive then
    raise exception '사망한 참가자는 투표할 수 없습니다.';
  end if;

  if not exists (
    select 1 from public.players pl
     where pl.room_id = p_room_id and pl.uid = p_target_uid and pl.alive = true
  ) then
    raise exception '살아 있는 참가자만 지목할 수 있습니다.';
  end if;

  -- 제출한 뒤에는 바꿀 수 없다 (§2.9 스파이 규칙을 전원에게 적용)
  if exists (
    select 1 from public.day_votes d
     where d.room_id = p_room_id and d.day_number = v_room.day_number
       and d.voter_uid = v_uid
  ) then
    raise exception '이미 투표했습니다. 변경할 수 없습니다.';
  end if;

  insert into public.day_votes (room_id, day_number, voter_uid, target_uid)
  values (p_room_id, v_room.day_number, v_uid, p_target_uid);

  select count(*) into v_expected
    from public.players pl
   where pl.room_id = p_room_id and pl.alive = true;

  select count(*) into v_submitted
    from public.day_votes d
   where d.room_id = p_room_id and d.day_number = v_room.day_number;

  if v_submitted >= v_expected then
    perform public.resolve_day(p_room_id);
    return json_build_object('resolved', true);
  end if;

  return json_build_object('resolved', false,
                           'submitted', v_submitted, 'expected', v_expected);
end;
$$;

-- ------------------------------------------------------------
-- 13. RPC — 게임 종료 후 전체 직업 공개
-- ------------------------------------------------------------

create or replace function public.final_roles(p_room_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phase text;
begin
  if not public.is_room_member(p_room_id) then
    raise exception '이 방의 참가자가 아닙니다.';
  end if;

  select r.phase into v_phase from public.rooms r where r.id = p_room_id;
  if v_phase <> 'ENDED' then
    raise exception '게임이 끝난 뒤에만 볼 수 있습니다.';
  end if;

  return (
    select json_agg(json_build_object(
             'uid', pl.uid, 'nickname', pl.nickname,
             'role', pr.role, 'team', pr.team, 'alive', pl.alive)
           order by pl.joined_at)
      from public.private_roles pr
      join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
     where pr.room_id = p_room_id
  );
end;
$$;

-- ------------------------------------------------------------
-- 14. 권한
-- ------------------------------------------------------------

revoke all on function public.assign_roles(uuid)          from public, anon, authenticated;
revoke all on function public.resolve_night(uuid)         from public, anon, authenticated;
revoke all on function public.resolve_day(uuid)           from public, anon, authenticated;
revoke all on function public.check_winner(uuid, uuid)    from public, anon, authenticated;

grant execute on function public.my_role(uuid)                         to anon, authenticated;
grant execute on function public.submit_night_action(uuid, text, uuid) to anon, authenticated;
grant execute on function public.submit_day_vote(uuid, uuid)           to anon, authenticated;
grant execute on function public.final_roles(uuid)                     to anon, authenticated;
grant execute on function public.role_composition(int)                 to anon, authenticated;
