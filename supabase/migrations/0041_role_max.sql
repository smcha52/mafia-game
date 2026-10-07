-- ============================================================
-- 마피아 게임 · 특수 직업 직업마다 최대 3명
-- ============================================================
-- 랜덤 구성에서 특수 직업(마피아·시민 외)을 직업마다 1~3명까지 넣을 수 있다.
-- 방장이 대기실에서 직업마다 최대 인원을 정한다 (rooms.role_max, 기본 1).
-- 진영별 자리 수(team_composition)는 그대로이고, 뽑을 후보에 직업을 최대 인원만큼 넣는다.
-- 고정 구성은 구성표 그대로라 최대 인원을 쓰지 않는다.
--
-- 같은 직업이 여럿이 되면서 한 명을 가정하던 곳을 고친다.
--   · 살인자·자경단·보안관: 밤에 각자 쏜다 (resolve_night)
--   · 광대: 처형된 사람의 직업으로 판정하고, 이긴 광대를 rooms.jester_uid 에 남긴다 (check_winner)
--   · 승패: 처형된 광대, 살아 있는 살인자·생존자만 이긴다 (player_won → award_xp, final_roles)
-- ============================================================

alter table public.rooms add column if not exists role_max jsonb not null default '{}'::jsonb;

-- 최대 인원을 정할 수 있는 직업 (마피아·시민 외 특수 직업)
create or replace function public.special_roles()
returns text[]
language sql
immutable
as $$
  select array['POLICE', 'DOCTOR', 'BODYGUARD', 'DETECTIVE', 'REPORTER', 'MEDIUM',
               'VIGILANTE', 'SHERIFF', 'SPY', 'ASSASSIN', 'FORGER',
               'JESTER', 'KILLER', 'SURVIVOR'];
$$;

-- 직업의 최대 인원 (1~3, 정하지 않았으면 1)
create or replace function public.role_max_of(p_max jsonb, p_role text)
returns int
language sql
immutable
as $$
  select greatest(1, least(3, coalesce((p_max ->> p_role)::int, 1)));
$$;

-- 켜진 직업을 최대 인원만큼 늘어놓은 후보 목록
create or replace function public.role_pool(p_roles text[], p_off text[], p_max jsonb)
returns setof text
language sql
immutable
as $$
  select x
    from unnest(p_roles) x
    cross join lateral generate_series(1, public.role_max_of(p_max, x))
   where not (x = any (coalesce(p_off, '{}')));
$$;

-- ------------------------------------------------------------
-- 방장이 직업의 최대 인원을 정한다
-- ------------------------------------------------------------
create or replace function public.set_role_max(p_room_id uuid, p_role text, p_max int)
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
    raise exception '방장만 직업을 바꿀 수 있습니다.';
  end if;
  if v_room.phase <> 'LOBBY' then
    raise exception '대기실에서만 바꿀 수 있습니다.';
  end if;
  if not (p_role = any (public.special_roles())) then
    raise exception '% 는 인원을 정할 수 없는 직업입니다.', p_role;
  end if;
  if p_max is null or p_max < 1 or p_max > 3 then
    raise exception '직업마다 1~3명까지 넣을 수 있습니다.';
  end if;

  update public.rooms r
     set role_max = r.role_max || jsonb_build_object(p_role, p_max)
   where r.id = p_room_id;
end;
$$;

grant execute on function public.set_role_max(uuid, text, int) to anon, authenticated;

-- ------------------------------------------------------------
-- team_composition / random_composition: 최대 인원을 받는다 (0034 / 0040 과 나머지는 같다)
-- ------------------------------------------------------------
drop function if exists public.team_composition(int, text[]);
drop function if exists public.random_composition(int, text[]);

create or replace function public.team_composition(
  p_count int, p_disabled text[] default '{}', p_max jsonb default '{}')
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

  -- 켜진 중립 직업의 최대 인원 합보다 자리가 많으면 남는 자리는 시민 진영으로 간다
  select coalesce(sum(public.role_max_of(p_max, x)), 0) into v_open
    from unnest(array['JESTER', 'KILLER', 'SURVIVOR']) x
   where not (x = any (off));
  v_neutral := least(v_neutral, v_open);

  -- 마피아가 꺼져 있으면 마피아 진영은 켜진 스파이·암살자·위조범 수만큼만 채운다.
  -- 남는 자리는 시민 진영으로 간다. 0명이면 시작할 수 없다 (assign_roles).
  if 'MAFIA' = any (off) then
    select coalesce(sum(public.role_max_of(p_max, x)), 0) into v_mopen
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

grant execute on function public.team_composition(int, text[], jsonb) to anon, authenticated;

create or replace function public.random_composition(
  p_count int, p_disabled text[] default '{}', p_max jsonb default '{}')
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
  v_teams := public.team_composition(p_count, off, p_max);
  v_m := (v_teams ->> 'mafia')::int;
  v_n := (v_teams ->> 'neutral')::int;
  v_c := (v_teams ->> 'citizen')::int;

  -- 마피아 진영
  --   마피아가 켜져 있으면 첫 자리는 마피아, 나머지는 켜진 스파이·암살자·위조범과 마피아 중에서.
  --   마피아가 꺼져 있으면 켜진 스파이·암살자·위조범으로만 채운다 (자리 수는 이미 그 이하).
  if 'MAFIA' = any (off) then
    v_out := v_out || array(
      select x from public.role_pool(array['SPY', 'ASSASSIN', 'FORGER'], off, p_max) x
       order by random() limit v_m);
  else
    v_out := v_out || 'MAFIA'::text;
    if v_m > 1 then
      v_pool := array(select x from public.role_pool(array['SPY', 'ASSASSIN', 'FORGER'], off, p_max) x)
                || array_fill('MAFIA'::text, array[v_m - 1]);
      v_out := v_out || array(select x from unnest(v_pool) x order by random() limit v_m - 1);
    end if;
  end if;

  -- 중립: 켜진 중립 직업 중에서 (자리 수는 이미 켜진 직업 수 이하)
  if v_n > 0 then
    v_out := v_out || array(
      select x from public.role_pool(array['JESTER', 'KILLER', 'SURVIVOR'], off, p_max) x
       order by random() limit v_n);
  end if;

  -- 시민 진영: 켜진 시민 직업과 시민 중에서.
  -- 시민을 껐으면 켜진 시민 진영 직업(각 최대 인원만큼)만으로 채우므로, 자리보다 적으면 시작할 수 없다.
  v_pool := array(
              select x from public.role_pool(array['POLICE', 'DOCTOR', 'BODYGUARD', 'DETECTIVE',
                                                   'REPORTER', 'MEDIUM', 'VIGILANTE', 'SHERIFF'],
                                             off, p_max) x);
  if 'CITIZEN' = any (off) then
    if coalesce(array_length(v_pool, 1), 0) < v_c then
      raise exception '시민 진영 직업이 부족해 게임을 시작할 수 없습니다. (필요 %명, 켜진 직업 %개)',
        v_c, coalesce(array_length(v_pool, 1), 0);
    end if;
  else
    v_pool := v_pool || array_fill('CITIZEN'::text, array[v_c]);
  end if;
  v_out := v_out || array(select x from unnest(v_pool) x order by random() limit v_c);

  if coalesce(array_length(v_out, 1), 0) <> p_count then
    raise exception '랜덤 구성 오류: %명 구성의 직업 수가 %개입니다.',
      p_count, coalesce(array_length(v_out, 1), 0);
  end if;

  return v_out;
end;
$$;

revoke all on function public.random_composition(int, text[], jsonb) from public, anon, authenticated;

-- ------------------------------------------------------------
-- assign_roles: 방의 최대 인원을 넘긴다 (0040 과 나머지는 같다)
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

  -- 최대 일수가 2일 이하이면 생존자는 이길 날이 없으므로 넣지 않는다
  if public.survivor_target(v_max) is null then
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
-- check_winner: 광대가 여럿이어도 처형된 광대만 이긴다 (0028 과 나머지는 같다)
-- ------------------------------------------------------------
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
  v_killer   int;
  v_alive    int;
begin
  -- §4.1 광대 승리 — 다른 조건보다 먼저 검사한다.
  -- 광대가 여럿일 수 있으므로 처형된 사람의 직업으로 본다. 이긴 광대를 rooms.jester_uid 에 남긴다.
  if p_executed_uid is not null then
    select pr.uid into v_jester
      from public.private_roles pr
     where pr.room_id = p_room_id and pr.uid = p_executed_uid and pr.role = 'JESTER';
    if v_jester is not null then
      update public.rooms r set jester_uid = v_jester where r.id = p_room_id;
      return 'JESTER';
    end if;
  end if;

  -- 광대·살인자는 양쪽 진영 인원 계산에서 제외한다 (§4.3)
  select
    count(*) filter (where pr.team = 'MAFIA'),
    count(*) filter (where pr.team = 'CITIZEN'),
    count(*) filter (where pr.role = 'KILLER'),
    count(*)
    into v_mafia, v_citizen, v_killer, v_alive
  from public.private_roles pr
  join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
  where pr.room_id = p_room_id and pl.alive = true;

  -- 살인자: 누구와든 1:1 이 되면 단독 승리. 살아 있는 동안은 아무도 이기지 못한다.
  if v_killer > 0 then
    if v_alive <= 2 then
      return 'KILLER';
    end if;
    return null;
  end if;

  if v_mafia = 0 then
    return 'CITIZEN';          -- §4.2
  end if;
  if v_mafia >= v_citizen then
    return 'MAFIA';            -- §4.3
  end if;
  return null;
end;
$$;

revoke all on function public.check_winner(uuid, uuid) from public, anon, authenticated;

-- ------------------------------------------------------------
-- resolve_night: 살인자·자경단·보안관이 여럿이면 각자 쏜다 (0033 과 나머지는 같다)
-- ------------------------------------------------------------
create or replace function public.resolve_night(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day       int;
  v_target    uuid;
  v_ties      int;
  v_healed    uuid[] := '{}';
  v_guards    uuid[] := '{}';
  v_deaths    uuid[] := '{}';
  v_saved     boolean := false;
  v_shielded  boolean := false;
  v_reveal    jsonb := '[]'::jsonb;
  v_ok        boolean;
  v_winner    text;
  v_rec       record;
  v_dead      uuid;
  v_ktargets  uuid[] := '{}';
  v_vactors   uuid[] := '{}';
  v_vtargets  uuid[] := '{}';
  v_stargets  uuid[] := '{}';
  v_smisfire  uuid[] := '{}';
  v_forged    uuid[] := '{}';
  v_attacks   uuid[] := '{}';
  v_guardmap  jsonb := '[]'::jsonb;
  v_t         uuid;
  v_died      uuid[];
begin
  select r.day_number into v_day from public.rooms r where r.id = p_room_id;

  -- 1. 마피아 공격 대상 확정. 스파이·암살자의 표도 함께 센다 (§2.2)
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
    v_target := null;
  end if;

  -- 2. 의사 치료 대상 (§2.4)
  select coalesce(array_agg(n.target_uid), '{}')
    into v_healed
    from public.night_actions n
    join public.private_roles pr on pr.room_id = n.room_id and pr.uid = n.actor_uid
    join public.players pl       on pl.room_id = n.room_id and pl.uid = n.actor_uid
   where n.room_id = p_room_id and n.day_number = v_day
     and n.action = 'DOCTOR' and pr.role = 'DOCTOR'
     and pl.alive = true and n.target_uid is not null;

  -- 2-2. 살인자 공격 대상. 살인자마다 혼자 정하므로 표결이 없다 (여럿이면 각자 공격, 0041)
  select coalesce(array_agg(n.target_uid), '{}') into v_ktargets
    from public.night_actions n
    join public.private_roles pr on pr.room_id = n.room_id and pr.uid = n.actor_uid
    join public.players pl       on pl.room_id = n.room_id and pl.uid = n.actor_uid
   where n.room_id = p_room_id and n.day_number = v_day
     and n.action = 'KILLER' and pr.role = 'KILLER'
     and pl.alive = true and n.target_uid is not null;

  -- 2-3. 자경단 공격 대상. 게임 중 한 번뿐이라 쏘는 순간 기회를 쓴다.
  --      치료·경호에 막혀도 다시 쏠 수 없다.
  --      자경단이 여럿이면 각자 쏜다 (0041)
  select coalesce(array_agg(n.actor_uid), '{}'), coalesce(array_agg(n.target_uid), '{}')
    into v_vactors, v_vtargets
    from public.night_actions n
    join public.private_roles pr on pr.room_id = n.room_id and pr.uid = n.actor_uid
    join public.players pl       on pl.room_id = n.room_id and pl.uid = n.actor_uid
   where n.room_id = p_room_id and n.day_number = v_day
     and n.action = 'VIGILANTE' and pr.role = 'VIGILANTE'
     and pl.alive = true and pl.ability_used = false
     and n.target_uid is not null;

  update public.players pl
     set ability_used = true
   where pl.room_id = p_room_id and pl.uid = any (v_vactors);

  -- 2-4. 보안관 공격 대상. 시민 진영을 쏜 보안관은 오인 사격으로 함께 죽는다.
  --      보안관이 여럿이면 각자 쏜다 (0041)
  select coalesce(array_agg(n.target_uid), '{}'),
         coalesce(array_agg(n.actor_uid) filter (where tgt.team = 'CITIZEN'), '{}')
    into v_stargets, v_smisfire
    from public.night_actions n
    join public.private_roles pr  on pr.room_id = n.room_id and pr.uid = n.actor_uid
    join public.players pl        on pl.room_id = n.room_id and pl.uid = n.actor_uid
    join public.private_roles tgt on tgt.room_id = n.room_id and tgt.uid = n.target_uid
   where n.room_id = p_room_id and n.day_number = v_day
     and n.action = 'SHERIFF' and pr.role = 'SHERIFF'
     and pl.alive = true and n.target_uid is not null;

  -- 공격 목록: 마피아 -> 살인자 -> 자경단 -> 보안관. 같은 사람을 노렸으면 한 번만 친다.
  if v_target is not null then
    v_attacks := v_attacks || v_target;
  end if;
  foreach v_t in array v_ktargets || v_vtargets || v_stargets loop
    if not (v_t = any (v_attacks)) then
      v_attacks := v_attacks || v_t;
    end if;
  end loop;

  -- 3. 경호원 보호 대상 (§2.5). 사망을 반영하기 전에 한꺼번에 정해 둔다.
  --    경호원이 다른 공격에 죽더라도 이미 몸을 던진 것으로 본다.
  select coalesce(jsonb_agg(jsonb_build_object('t', n.target_uid, 'g', n.actor_uid)),
                  '[]'::jsonb)
    into v_guardmap
    from public.night_actions n
    join public.private_roles pr on pr.room_id = n.room_id and pr.uid = n.actor_uid
    join public.players pl       on pl.room_id = n.room_id and pl.uid = n.actor_uid
   where n.room_id = p_room_id and n.day_number = v_day
     and n.action = 'BODYGUARD' and pr.role = 'BODYGUARD'
     and pl.alive = true and n.target_uid = any (v_attacks);

  -- 4~5. 공격마다 생존·사망 계산 (§3.1 — 치료 우선, 다음이 경호)
  foreach v_t in array v_attacks loop
    select coalesce(array_agg((e ->> 'g')::uuid), '{}')
      into v_guards
      from jsonb_array_elements(v_guardmap) e
     where (e ->> 't')::uuid = v_t;

    v_saved := v_t = any (v_healed);
    v_shielded := not v_saved and coalesce(array_length(v_guards, 1), 0) > 0;

    if not v_saved then
      with d as (
        update public.players pl
           set alive = false
         where pl.room_id = p_room_id and pl.alive = true
           and (case when v_shielded then pl.uid = any (v_guards) else pl.uid = v_t end)
        returning pl.uid
      )
      select coalesce(array_agg(d.uid), '{}') into v_died from d;
      v_deaths := v_deaths || v_died;
    end if;

    -- 의사 본인에게만
    if v_saved then
      insert into public.private_results (room_id, uid, day_number, kind, payload)
      select p_room_id, n.actor_uid, v_day, 'DOCTOR',
             jsonb_build_object('savedUid', v_t, 'savedNickname', tp.nickname)
        from public.night_actions n
        join public.players tp on tp.room_id = n.room_id and tp.uid = n.target_uid
       where n.room_id = p_room_id and n.day_number = v_day
         and n.action = 'DOCTOR' and n.target_uid = v_t
      on conflict (room_id, uid, day_number, kind) do update set payload = excluded.payload;
    end if;

    -- 경호원 본인에게만
    if coalesce(array_length(v_guards, 1), 0) > 0 then
      insert into public.private_results (room_id, uid, day_number, kind, payload)
      select p_room_id, g, v_day, 'BODYGUARD',
             jsonb_build_object('protectedUid', v_t,
                                'protectedNickname', tp.nickname,
                                'sacrificed', v_shielded)
        from unnest(v_guards) g
        join public.players tp on tp.room_id = p_room_id and tp.uid = v_t
      on conflict (room_id, uid, day_number, kind) do update set payload = excluded.payload;
    end if;
  end loop;

  -- 5-1. 보안관 오인 사격. 시민 진영을 쐈으면 보안관도 죽는다.
  --      대상이 치료·보호로 살았어도, 보안관 본인이 치료받았어도 막을 수 없다.
  if coalesce(array_length(v_smisfire, 1), 0) > 0 then
    with d as (
      update public.players pl
         set alive = false
       where pl.room_id = p_room_id and pl.uid = any (v_smisfire) and pl.alive = true
      returning pl.uid
    )
    select coalesce(array_agg(d.uid), '{}') into v_died from d;
    v_deaths := v_deaths || v_died;
  end if;

  -- 5-2. 밤 저격. 치료·보호로 막을 수 없다.
  for v_rec in
    select a.actor_uid
      from public.assassinations a
      join public.private_roles pr on pr.room_id = a.room_id and pr.uid = a.actor_uid
     where a.room_id = p_room_id and a.day_number = v_day
       and a.phase = 'NIGHT' and a.resolved = false
       and pr.role = 'ASSASSIN'
  loop
    v_dead := public.apply_assassination(p_room_id, v_day, 'NIGHT', v_rec.actor_uid);
    if v_dead is not null then
      v_deaths := v_deaths || v_dead;
    end if;
  end loop;

  -- 의사·경호원의 직전 대상 기록 (§6.3)
  update public.players pl
     set last_target_id = n.target_uid
    from public.night_actions n
   where n.room_id = pl.room_id
     and n.actor_uid = pl.uid
     and n.room_id = p_room_id
     and n.day_number = v_day
     and n.action in ('DOCTOR', 'BODYGUARD');

  -- 5-3. 위조 대상. 오늘 밤 이 사람들을 조사한 경찰·탐정·기자·영매는 오답을 받는다.
  select coalesce(array_agg(n.target_uid), '{}')
    into v_forged
    from public.night_actions n
    join public.private_roles pr on pr.room_id = n.room_id and pr.uid = n.actor_uid
   where n.room_id = p_room_id and n.day_number = v_day
     and n.action = 'FORGE' and pr.role = 'FORGER'
     and n.target_uid is not null;

  -- 6. 경찰 조사 (§2.3)
  for v_rec in
    select n.actor_uid, n.target_uid, tgt.team as target_team, tp.nickname as target_nick
      from public.night_actions n
      join public.private_roles pr  on pr.room_id = n.room_id and pr.uid = n.actor_uid
      join public.private_roles tgt on tgt.room_id = n.room_id and tgt.uid = n.target_uid
      join public.players tp        on tp.room_id = n.room_id and tp.uid = n.target_uid
     where n.room_id = p_room_id and n.day_number = v_day
       and n.action = 'POLICE' and pr.role = 'POLICE'
       and n.target_uid is not null
  loop
    insert into public.private_results (room_id, uid, day_number, kind, payload)
    values (p_room_id, v_rec.actor_uid, v_day, 'POLICE',
            jsonb_build_object('targetUid', v_rec.target_uid,
                               'targetNickname', v_rec.target_nick,
                               'team', case when v_rec.target_uid = any (v_forged)
                                            then public.forged_team(v_rec.target_team)
                                            else v_rec.target_team end))
    on conflict (room_id, uid, day_number, kind) do update set payload = excluded.payload;
  end loop;

  -- 7. 탐정
  for v_rec in
    select n.actor_uid, n.target_uid, tp.nickname as target_nick
      from public.night_actions n
      join public.private_roles pr on pr.room_id = n.room_id and pr.uid = n.actor_uid
      join public.players tp       on tp.room_id = n.room_id and tp.uid = n.target_uid
     where n.room_id = p_room_id and n.day_number = v_day
       and n.action = 'DETECTIVE' and pr.role = 'DETECTIVE'
       and n.target_uid is not null
  loop
    insert into public.private_results (room_id, uid, day_number, kind, payload)
    values (p_room_id, v_rec.actor_uid, v_day, 'DETECTIVE',
            jsonb_build_object(
              'targetUid', v_rec.target_uid,
              'targetNickname', v_rec.target_nick,
              'candidates', to_jsonb(
                case when v_rec.target_uid = any (v_forged)
                     then public.forged_candidates(p_room_id, v_rec.target_uid)
                     else public.detective_candidates(p_room_id, v_rec.target_uid) end)))
    on conflict (room_id, uid, day_number, kind) do update set payload = excluded.payload;
  end loop;

  -- 8. 영매
  for v_rec in
    select n.actor_uid, n.target_uid, tgt.role as target_role, tp.nickname as target_nick
      from public.night_actions n
      join public.private_roles pr  on pr.room_id = n.room_id and pr.uid = n.actor_uid
      join public.private_roles tgt on tgt.room_id = n.room_id and tgt.uid = n.target_uid
      join public.players tp        on tp.room_id = n.room_id and tp.uid = n.target_uid
     where n.room_id = p_room_id and n.day_number = v_day
       and n.action = 'MEDIUM' and pr.role = 'MEDIUM'
       and n.target_uid is not null
  loop
    insert into public.private_results (room_id, uid, day_number, kind, payload)
    values (p_room_id, v_rec.actor_uid, v_day, 'MEDIUM',
            jsonb_build_object('targetUid', v_rec.target_uid,
                               'targetNickname', v_rec.target_nick,
                               'role', case when v_rec.target_uid = any (v_forged)
                                            then case when public.team_of(v_rec.target_role) = 'MAFIA'
                                                      then 'CITIZEN' else 'MAFIA' end
                                            else v_rec.target_role end))
    on conflict (room_id, uid, day_number, kind) do update set payload = excluded.payload;
  end loop;

  -- 9. 기자 (성공률 50%)
  for v_rec in
    select n.actor_uid, n.target_uid, tgt.team as target_team, tp.nickname as target_nick
      from public.night_actions n
      join public.private_roles pr  on pr.room_id = n.room_id and pr.uid = n.actor_uid
      join public.private_roles tgt on tgt.room_id = n.room_id and tgt.uid = n.target_uid
      join public.players tp        on tp.room_id = n.room_id and tp.uid = n.target_uid
     where n.room_id = p_room_id and n.day_number = v_day
       and n.action = 'REPORTER' and pr.role = 'REPORTER'
       and n.target_uid is not null
  loop
    v_ok := random() < 0.5;

    update public.players pl
       set ability_used = true
     where pl.room_id = p_room_id and pl.uid = v_rec.actor_uid;

    insert into public.private_results (room_id, uid, day_number, kind, payload)
    values (p_room_id, v_rec.actor_uid, v_day, 'REPORTER',
            jsonb_build_object('targetUid', v_rec.target_uid,
                               'targetNickname', v_rec.target_nick,
                               'success', v_ok,
                               'team', case when not v_ok then null
                                          when v_rec.target_uid = any (v_forged)
                                            then public.forged_team(v_rec.target_team)
                                          when v_rec.target_team = 'NEUTRAL' then 'CITIZEN'
                                          else v_rec.target_team end))
    on conflict (room_id, uid, day_number, kind) do update set payload = excluded.payload;

    if v_ok then
      v_reveal := v_reveal || jsonb_build_object(
        'targetUid', v_rec.target_uid,
        'targetNickname', v_rec.target_nick,
        'team', case when v_rec.target_uid = any (v_forged)
                       then public.forged_team(v_rec.target_team)
                     when v_rec.target_team = 'NEUTRAL' then 'CITIZEN'
                     else v_rec.target_team end);
    end if;
  end loop;

  -- 공개 결과 — 사망자와 취재 성공분만. 사인은 구분하지 않는다.
  insert into public.public_results (room_id, day_number, kind, payload)
  values (p_room_id, v_day, 'NIGHT',
          jsonb_build_object('nightDeaths', to_jsonb(v_deaths),
                             'reporterReveal', v_reveal))
  on conflict (room_id, day_number, kind) do update
    set payload = public.public_results.payload || excluded.payload;

  -- 10. 승리 조건
  v_winner := public.check_winner(p_room_id);
  if v_winner is not null then
    perform public.end_game(p_room_id, v_winner);
    return;
  end if;

  -- 11. 낮으로
  perform public.enter_phase(p_room_id, 'DAY', v_day);
end;
$$;

revoke all on function public.resolve_night(uuid) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 이 사람이 이겼는지. 같은 직업이 여럿일 수 있어 사람 단위로 본다
--   시민·마피아 승리: 진영 / 광대: 처형된 그 광대(rooms.jester_uid) / 살인자·생존자: 살아 있는 사람
-- ------------------------------------------------------------
create or replace function public.player_won(
  p_room_id uuid, p_winner text, p_uid uuid, p_role text, p_team text, p_alive boolean)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when p_winner in ('CITIZEN', 'MAFIA') then p_team = p_winner
    when p_winner = 'JESTER' then
      p_uid = (select r.jester_uid from public.rooms r where r.id = p_room_id)
    when p_winner in ('KILLER', 'SURVIVOR') then p_role = p_winner and p_alive
    else false
  end;
$$;

revoke all on function public.player_won(uuid, text, uuid, text, text, boolean) from public, anon, authenticated;

-- ------------------------------------------------------------
-- award_xp: 사람 단위 승패로 2배를 정한다 (0038 과 나머지는 같다)
-- ------------------------------------------------------------
create or replace function public.award_xp(p_room_id uuid, p_winner text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (select 1 from public.players pl
              where pl.room_id = p_room_id and pl.xp_gained is not null) then
    return;
  end if;

  update public.players pl
     set xp_base   = b.base,
         xp_gained = b.base * case when b.win then 2 else 1 end
    from (
      select pr.uid,
             public.base_xp(p_room_id, pr.uid, pr.role) as base,
             public.player_won(p_room_id, p_winner, pr.uid, pr.role, pr.team, pl.alive) as win
        from public.private_roles pr
        join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
       where pr.room_id = p_room_id
    ) b
   where pl.room_id = p_room_id and pl.uid = b.uid;

  -- 익명 사용자(테스트)는 프로필이 없어 건너뛴다. 50레벨(12250 XP)에서 멈춘다
  update public.profiles pf
     set xp = least(12250, pf.xp + pl.xp_gained)
    from public.players pl
   where pl.room_id = p_room_id and pl.uid = pf.uid and pl.xp_gained > 0;
end;
$$;

revoke all on function public.award_xp(uuid, text) from public, anon, authenticated;

-- ------------------------------------------------------------
-- final_roles: 사람마다 이겼는지(won)를 함께 준다 (0039 와 나머지는 같다)
-- ------------------------------------------------------------
create or replace function public.final_roles(p_room_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phase  text;
  v_winner text;
begin
  if not public.is_room_member(p_room_id) then
    raise exception '이 방의 참가자가 아닙니다.';
  end if;

  select r.phase, r.winner into v_phase, v_winner from public.rooms r where r.id = p_room_id;
  if v_phase <> 'ENDED' then
    raise exception '게임이 끝난 뒤에만 볼 수 있습니다.';
  end if;

  return (
    select json_agg(json_build_object(
             'uid', pl.uid, 'nickname', pl.nickname,
             'role', pr.role, 'team', pr.team, 'alive', pl.alive,
             'level', pl.level,
             'won', public.player_won(p_room_id, v_winner, pl.uid, pr.role, pr.team, pl.alive),
             'xpBase',   case when pl.uid = auth.uid() then pl.xp_base end,
             'xpGained', case when pl.uid = auth.uid() then pl.xp_gained end)
           order by pl.joined_at)
      from public.private_roles pr
      join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
     where pr.room_id = p_room_id
  );
end;
$$;
