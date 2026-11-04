-- ============================================================
-- 마피아 게임 · 마피아 진영 직업 폭탄광 (Bomber)
-- ============================================================
-- 폭탄광 — 마피아 진영. 동료(마피아끼리 서로 앎)와 같은 진영이지만 제거 투표에는 참여하지 않는다.
--   · 랜덤 구성의 마피아 진영 후보에만 들어간다 (위조범과 같다).
--   · 밤에 다른 한 명(같은 마피아도 된다)에게 폭탄을 줄 수 있다. 오늘은 쓰지 않아도 된다.
--     폭탄은 한 번에 하나만. 준 폭탄이 터지거나 사라져야 새로 줄 수 있다.
--   · 폭탄을 받은 밤이 1번째 턴이다. 밤이 지날 때마다 턴이 하나씩 오른다.
--       가진 사람은 밤마다 자기 말고 살아 있는 사람에게 넘길 수 있다 (BOMB_PASS, 직업과 상관없이).
--       넘기지 않아도 턴은 오른다. 전에 나에게 준 사람·폭탄광에게도 넘길 수 있다.
--       3번째 턴 다음 밤이 지나면(4번째 턴) 그때 가진 사람이 터져 죽는다. 치료·보호로 막을 수 없다.
--   · 가진 사람이 다른 이유(처형·제거)로 죽으면 폭탄은 사라진다.
--   · 밤은 폭탄광(폭탄이 돌고 있지 않을 때)과 폭탄을 가진 사람이 모두 행동해야 끝난다.
--   · XP: 폭탄을 줄 때마다 2, 준 폭탄이 터져 누군가 죽으면 5. 터진 폭탄은 폭탄광의 킬로 센다.
-- ============================================================

-- ------------------------------------------------------------
-- 1. 스키마 확장
-- ------------------------------------------------------------

alter table public.private_roles drop constraint if exists private_roles_role_check;
alter table public.private_roles add constraint private_roles_role_check
  check (role in ('CITIZEN','MAFIA','POLICE','DOCTOR','BODYGUARD',
                  'DETECTIVE','REPORTER','MEDIUM','SPY','JESTER','ASSASSIN','KILLER',
                  'VIGILANTE','SHERIFF','FORGER','SURVIVOR','WITCH','BOMBER'));

alter table public.night_actions drop constraint if exists night_actions_action_check;
alter table public.night_actions add constraint night_actions_action_check
  check (action in ('MAFIA_VOTE','DOCTOR','BODYGUARD','POLICE',
                    'DETECTIVE','REPORTER','MEDIUM','ASSASSIN','KILLER','VIGILANTE',
                    'SHERIFF','FORGE','WITCH','BOMB','BOMB_PASS'));

-- 폭탄. turn 은 지금 턴(1~3), 4가 되면 터진다. 터지거나 사라지면 active = false
create table if not exists public.bombs (
  id           bigserial primary key,
  room_id      uuid not null references public.rooms(id) on delete cascade,
  bomber_uid   uuid not null,
  holder_uid   uuid not null,
  turn         int  not null default 1,
  given_day    int  not null,
  active       boolean not null default true,
  exploded_uid uuid,
  exploded_day int
);
create index if not exists bombs_room_idx on public.bombs (room_id, active);
-- 서버 함수만 읽고 쓴다
alter table public.bombs enable row level security;
revoke all on public.bombs from anon, authenticated;

-- 이 폭탄광이 준 폭탄이 아직 돌고 있는지. 가진 사람이 낮에 죽었으면 밤 처리 전이라도 사라진 것으로 본다
create or replace function public.has_live_bomb(p_room_id uuid, p_bomber uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.bombs b
      join public.players pl on pl.room_id = b.room_id and pl.uid = b.holder_uid
     where b.room_id = p_room_id and b.bomber_uid = p_bomber and b.active and pl.alive = true);
$$;

revoke all on function public.has_live_bomb(uuid, uuid) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 2. 진영과 목록
-- ------------------------------------------------------------

create or replace function public.team_of(p_role text)
returns text
language sql
immutable
as $$
  select case
    when p_role in ('MAFIA', 'SPY', 'ASSASSIN', 'FORGER', 'BOMBER') then 'MAFIA'
    when p_role in ('JESTER', 'KILLER', 'SURVIVOR', 'WITCH')       then 'NEUTRAL'
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
               'VIGILANTE', 'SHERIFF', 'FORGER', 'SURVIVOR', 'WITCH', 'BOMBER', 'CITIZEN'];
$$;

create or replace function public.special_roles()
returns text[]
language sql
immutable
as $$
  select array['POLICE', 'DOCTOR', 'BODYGUARD', 'DETECTIVE', 'REPORTER', 'MEDIUM',
               'VIGILANTE', 'SHERIFF', 'SPY', 'ASSASSIN', 'FORGER', 'BOMBER',
               'JESTER', 'KILLER', 'SURVIVOR', 'WITCH'];
$$;

create or replace function public.night_actor_roles()
returns text[]
language sql
immutable
as $$
  select array['MAFIA', 'SPY', 'ASSASSIN', 'FORGER', 'BOMBER', 'POLICE', 'DOCTOR', 'BODYGUARD',
               'DETECTIVE', 'REPORTER', 'MEDIUM', 'KILLER', 'VIGILANTE', 'SHERIFF', 'WITCH'];
$$;

-- ------------------------------------------------------------
-- 3. 랜덤 구성 — 마피아 진영 후보에 폭탄광을 더했다 (0071 과 나머지는 같다)
-- ------------------------------------------------------------

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
    from unnest(array['JESTER', 'KILLER', 'SURVIVOR', 'WITCH']) x
   where not (x = any (off));
  v_neutral := least(v_neutral, v_open);

  -- 마피아가 꺼져 있으면 마피아 진영은 켜진 스파이·암살자·위조범·폭탄광 수만큼만 채운다.
  -- 남는 자리는 시민 진영으로 간다. 0명이면 시작할 수 없다 (assign_roles).
  if 'MAFIA' = any (off) then
    select coalesce(sum(public.role_max_of(p_max, x)), 0) into v_mopen
      from unnest(array['SPY', 'ASSASSIN', 'FORGER', 'BOMBER']) x
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

  if 'MAFIA' = any (off) then
    v_out := v_out || array(
      select x from public.role_pool(array['SPY', 'ASSASSIN', 'FORGER', 'BOMBER'], off, p_max) x
       order by random() limit v_m);
  else
    v_out := v_out || 'MAFIA'::text;
    if v_m > 1 then
      v_pool := array(select x from public.role_pool(array['SPY', 'ASSASSIN', 'FORGER', 'BOMBER'], off, p_max) x)
                || array_fill('MAFIA'::text, array[v_m - 1]);
      v_out := v_out || array(select x from unnest(v_pool) x order by random() limit v_m - 1);
    end if;
  end if;

  -- 중립: 켜진 중립 직업 중에서 (자리 수는 이미 켜진 직업 수 이하)
  if v_n > 0 then
    v_out := v_out || array(
      select x from public.role_pool(array['JESTER', 'KILLER', 'SURVIVOR', 'WITCH'], off, p_max) x
       order by random() limit v_n);
  end if;

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
-- 4. 직업 배정 — 새 판을 시작할 때 지난 판 폭탄을 지운다 (0071 과 나머지는 같다)
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
  -- 같은 방의 지난 판 폭탄을 지운다
  delete from public.bombs b where b.room_id = p_room_id;

  select count(*) into v_count from public.players pl where pl.room_id = p_room_id;
  select r.disabled_roles, r.random_roles, r.max_days, r.role_max
    into v_off, v_random, v_max, v_rmax
    from public.rooms r where r.id = p_room_id;

  -- 목표 날이 최대 일수를 넘으면 생존자는 이길 날이 없으므로 넣지 않는다
  if public.survivor_target(v_max, v_count) is null then
    v_off := coalesce(v_off, '{}') || 'SURVIVOR'::text;
  end if;

  -- 마녀는 할로윈 기간에만 나온다
  if not public.is_halloween() then
    v_off := coalesce(v_off, '{}') || 'WITCH'::text;
  end if;

  if coalesce(v_random, true) then
    v_roles := public.random_composition(v_count, coalesce(v_off, '{}'), coalesce(v_rmax, '{}'));
  else
    -- 고정 구성은 끈 직업 자리를 시민이 채우므로 시민 끄기는 무시한다
    v_roles := public.role_composition(v_count, array_remove(coalesce(v_off, '{}'), 'CITIZEN'));
  end if;

  if not exists (select 1 from unnest(v_roles) x where public.team_of(x) = 'MAFIA') then
    raise exception '마피아 진영 직업이 하나도 없어 게임을 시작할 수 없습니다.';
  end if;

  for v_uid in
    select pl.uid from public.players pl
     where pl.room_id = p_room_id
     order by random()
  loop
    v_role := v_roles[v_i];
    v_team := public.team_of(v_role);

    insert into public.private_roles (room_id, uid, role, team)
    values (p_room_id, v_uid, v_role, v_team)
    on conflict (room_id, uid) do update
      set role = excluded.role, team = excluded.team,
          witch_quest = null, witch_goal = null, witch_won = false;

    if v_role = 'JESTER' then
      update public.rooms r set jester_uid = v_uid where r.id = p_room_id;
    end if;

    v_i := v_i + 1;
  end loop;

  perform public.assign_witch_quests(p_room_id);
end;
$$;

revoke all on function public.assign_roles(uuid) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 5. 킬 수와 XP — 폭탄광을 더했다 (kills_of 는 0071, base_xp 는 0038 과 나머지는 같다)
-- ------------------------------------------------------------

create or replace function public.kills_of(p_room_id uuid, p_uid uuid, p_role text)
returns int
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v int := 0;
begin
  if p_role in ('MAFIA', 'SPY') then
    select count(*) into v
      from public.night_actions n
     where n.room_id = p_room_id and n.actor_uid = p_uid
       and n.action = 'MAFIA_VOTE' and n.target_uid is not null
       and n.target_uid = public.mafia_target(p_room_id, n.day_number)
       and public.died_at_night(p_room_id, n.day_number, n.target_uid);
  elsif p_role in ('VIGILANTE', 'KILLER', 'SHERIFF', 'WITCH') then
    select count(*) into v
      from public.night_actions n
     where n.room_id = p_room_id and n.actor_uid = p_uid
       and n.action = p_role and n.target_uid is not null
       and public.died_at_night(p_room_id, n.day_number, n.target_uid);
  elsif p_role = 'BOMBER' then
    select count(*) into v
      from public.bombs b
     where b.room_id = p_room_id and b.bomber_uid = p_uid and b.exploded_uid is not null;
  elsif p_role = 'ASSASSIN' then
    select count(*) into v
      from public.assassinations a
     where a.room_id = p_room_id and a.actor_uid = p_uid
       and a.resolved = true and a.success;
  end if;
  return coalesce(v, 0);
end;
$$;

revoke all on function public.kills_of(uuid, uuid, text) from public, anon, authenticated;

create or replace function public.base_xp(p_room_id uuid, p_uid uuid, p_role text)
returns int
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_xp    int := 0;
  v_extra int := 0;
  v_death int;
begin
  case p_role
  when 'CITIZEN', 'SURVIVOR' then
    v_death := public.death_day(p_room_id, p_uid);
    select 2 * count(*) into v_xp
      from public.public_results r
     where r.room_id = p_room_id and r.kind = 'DAY'
       and (v_death is null or r.day_number < v_death);

  when 'POLICE' then
    select coalesce(sum(case tgt.team when 'MAFIA' then 5 when 'NEUTRAL' then 3 else 1 end), 0)
      into v_xp
      from public.private_results r
      join public.private_roles tgt
        on tgt.room_id = r.room_id and tgt.uid = (r.payload ->> 'targetUid')::uuid
     where r.room_id = p_room_id and r.uid = p_uid and r.kind = 'POLICE';

  when 'DOCTOR' then
    select 7 * count(*) into v_xp
      from public.private_results r
     where r.room_id = p_room_id and r.uid = p_uid and r.kind = 'DOCTOR';

  when 'BODYGUARD' then
    select coalesce(sum(case when coalesce((r.payload ->> 'sacrificed')::boolean, false)
                             then 5 else 1 end), 0)
      into v_xp
      from public.night_actions n
      left join public.private_results r
        on r.room_id = n.room_id and r.uid = n.actor_uid
       and r.day_number = n.day_number and r.kind = 'BODYGUARD'
     where n.room_id = p_room_id and n.actor_uid = p_uid
       and n.action = 'BODYGUARD' and n.target_uid is not null;

  when 'DETECTIVE' then
    select 3 * count(*) into v_xp
      from public.private_results r
     where r.room_id = p_room_id and r.uid = p_uid and r.kind = 'DETECTIVE';

  when 'REPORTER' then
    select coalesce(sum(case tgt.team when 'MAFIA' then 5 else 2 end), 0)
      into v_xp
      from public.private_results r
      join public.private_roles tgt
        on tgt.room_id = r.room_id and tgt.uid = (r.payload ->> 'targetUid')::uuid
     where r.room_id = p_room_id and r.uid = p_uid and r.kind = 'REPORTER'
       and coalesce((r.payload ->> 'success')::boolean, false);

  when 'MEDIUM' then
    select 2 * count(*) into v_xp
      from public.private_results r
     where r.room_id = p_room_id and r.uid = p_uid and r.kind = 'MEDIUM';
    if exists (select 1 from public.players pl
                where pl.room_id = p_room_id and pl.uid = p_uid and pl.alive = false) then
      v_xp := v_xp + 3;
    end if;

  when 'VIGILANTE', 'KILLER' then
    select 3 * count(*) into v_xp
      from public.night_actions n
     where n.room_id = p_room_id and n.actor_uid = p_uid
       and n.action = p_role and n.target_uid is not null
       and public.died_at_night(p_room_id, n.day_number, n.target_uid);

  when 'SHERIFF' then
    select coalesce(sum(case when tgt.team = 'CITIZEN' then 1 else 10 end), 0)
      into v_xp
      from public.night_actions n
      join public.private_roles tgt on tgt.room_id = n.room_id and tgt.uid = n.target_uid
     where n.room_id = p_room_id and n.actor_uid = p_uid
       and n.action = 'SHERIFF' and n.target_uid is not null;

  when 'MAFIA', 'SPY' then
    select 2 * count(*) into v_xp
      from public.night_actions n
     where n.room_id = p_room_id and n.actor_uid = p_uid
       and n.action = 'MAFIA_VOTE'
       and public.mafia_target(p_room_id, n.day_number) is not null
       and public.died_at_night(p_room_id, n.day_number,
                                public.mafia_target(p_room_id, n.day_number));
    if p_role = 'SPY' then
      select 2 * count(*) into v_extra
        from public.private_results r
       where r.room_id = p_room_id and r.uid = p_uid and r.kind = 'SPY';
      v_xp := v_xp + v_extra;
    end if;

  when 'ASSASSIN' then
    select coalesce(sum(case when a.success then 15 else 2 end), 0)
      into v_xp
      from public.assassinations a
     where a.room_id = p_room_id and a.actor_uid = p_uid and a.resolved = true;

  when 'FORGER' then
    select 5 * count(*) into v_xp
      from public.night_actions n
     where n.room_id = p_room_id and n.actor_uid = p_uid
       and n.action = 'FORGE' and n.target_uid is not null and n.target_uid <> p_uid;

  when 'BOMBER' then
    select 2 * count(*) into v_xp
      from public.night_actions n
     where n.room_id = p_room_id and n.actor_uid = p_uid
       and n.action = 'BOMB' and n.target_uid is not null;
    select 5 * count(*) into v_extra
      from public.bombs b
     where b.room_id = p_room_id and b.bomber_uid = p_uid and b.exploded_uid is not null;
    v_xp := v_xp + v_extra;

  when 'JESTER' then
    select coalesce(2 * sum((v ->> 'count')::int), 0) into v_xp
      from public.public_results r,
           jsonb_array_elements(r.payload -> 'votes') v
     where r.room_id = p_room_id and r.kind = 'DAY'
       and v ->> 'uid' = p_uid::text;

  else
    v_xp := 0;
  end case;

  return coalesce(v_xp, 0);
end;
$$;
revoke all on function public.base_xp(uuid, uuid, text) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 6. 밤 완료 — 폭탄광과 폭탄을 가진 사람을 더했다 (0033 과 나머지는 같다)
--   폭탄광은 준 폭탄이 돌고 있으면 할 일이 없다.
--   폭탄을 가진 사람은 직업 행동과 따로 넘기기(넘기지 않기 포함)를 내야 한다.
-- ------------------------------------------------------------

create or replace function public.night_is_complete(p_room_id uuid, p_day int)
returns boolean
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_dead      int;
  v_expected  int;
  v_submitted int;
  v_holders   int;
  v_passed    int;
begin
  select count(*) into v_dead
    from public.players pl
   where pl.room_id = p_room_id and pl.alive = false;

  select count(*) into v_expected
    from public.private_roles pr
    join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
   where pr.room_id = p_room_id
     and pl.alive = true
     and pr.role = any (public.night_actor_roles())
     -- 1회용 능력을 이미 쓴 사람은 더 이상 밤에 할 일이 없다
     and not (pr.role in ('REPORTER', 'VIGILANTE') and pl.ability_used = true)
     -- 사망자가 없으면 영매는 능력을 쓸 수 없다 (§2.8)
     and not (pr.role = 'MEDIUM' and v_dead = 0)
     -- 준 폭탄이 아직 돌고 있으면 폭탄광은 새 폭탄을 줄 수 없다
     and not (pr.role = 'BOMBER' and public.has_live_bomb(p_room_id, pr.uid));

  -- 행동한 사람 수를 센다. 선택 행동인 위조와 따로 세는 폭탄 넘기기는 제외한다.
  select count(distinct n.actor_uid) into v_submitted
    from public.night_actions n
    join public.players pl on pl.room_id = n.room_id and pl.uid = n.actor_uid
   where n.room_id = p_room_id
     and n.day_number = p_day
     and n.action not in ('FORGE', 'BOMB_PASS')
     and pl.alive = true;

  -- 폭탄을 가진 사람이 모두 넘기기를 냈는지
  select count(distinct b.holder_uid),
         count(distinct b.holder_uid) filter (where exists (
           select 1 from public.night_actions n
            where n.room_id = p_room_id and n.day_number = p_day
              and n.actor_uid = b.holder_uid and n.action = 'BOMB_PASS'))
    into v_holders, v_passed
    from public.bombs b
    join public.players pl on pl.room_id = b.room_id and pl.uid = b.holder_uid
   where b.room_id = p_room_id and b.active and pl.alive = true;

  return v_submitted >= v_expected and v_passed >= v_holders;
end;
$$;

revoke all on function public.night_is_complete(uuid, int) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 7. 밤 행동 제출 — 폭탄 주기(BOMB)·넘기기(BOMB_PASS)를 더했다 (0071 과 나머지는 같다)
-- ------------------------------------------------------------

create or replace function public.submit_night_action(
  p_room_id uuid, p_action text, p_target_uid uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid         uuid := auth.uid();
  v_room        public.rooms%rowtype;
  v_role        text;
  v_alive       boolean;
  v_used        boolean;
  v_last        uuid;
  v_needed      text;
  v_target_alive boolean;
  v_forged      int;
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

  select pl.alive, pl.last_target_id, pl.ability_used
    into v_alive, v_last, v_used
    from public.players pl
   where pl.room_id = p_room_id and pl.uid = v_uid;
  if not v_alive then
    raise exception '사망한 참가자는 능력을 사용할 수 없습니다.';
  end if;

  if p_action = 'MAFIA_VOTE' then
    -- 폭탄광은 마피아 진영이지만 제거 투표에 참여하지 않는다
    if public.team_of(v_role) <> 'MAFIA' or v_role = 'BOMBER' then
      raise exception '사용할 수 없는 능력입니다.';
    end if;
  elsif p_action = 'BOMB_PASS' then
    -- 폭탄 넘기기는 직업과 상관없이 폭탄을 가진 사람이 한다
    if not exists (select 1 from public.bombs b
                    where b.room_id = p_room_id and b.holder_uid = v_uid and b.active) then
      raise exception '폭탄을 가지고 있지 않습니다.';
    end if;
  else
    v_needed := case p_action
      when 'POLICE'    then 'POLICE'
      when 'DOCTOR'    then 'DOCTOR'
      when 'BODYGUARD' then 'BODYGUARD'
      when 'DETECTIVE' then 'DETECTIVE'
      when 'REPORTER'  then 'REPORTER'
      when 'MEDIUM'    then 'MEDIUM'
      when 'KILLER'    then 'KILLER'
      when 'VIGILANTE' then 'VIGILANTE'
      when 'SHERIFF'   then 'SHERIFF'
      when 'FORGE'     then 'FORGER'
      when 'WITCH'     then 'WITCH'
      when 'BOMB'      then 'BOMBER'
      else null
    end;

    if v_needed is null then
      raise exception '아직 구현되지 않은 능력입니다: %', p_action;
    end if;
    if v_role <> v_needed then
      raise exception '사용할 수 없는 능력입니다.';
    end if;
  end if;

  if p_action = 'VIGILANTE' and v_used then
    raise exception '당신은 제거를 이미 했습니다.';
  end if;

  -- 폭탄은 한 번에 하나만. 준 폭탄이 터지거나 사라져야 새로 줄 수 있다
  if p_action = 'BOMB' and public.has_live_bomb(p_room_id, v_uid) then
    raise exception '폭탄이 아직 돌고 있어 새 폭탄을 줄 수 없습니다.';
  end if;

  if p_target_uid is null then
    if p_action not in ('REPORTER', 'VIGILANTE', 'SHERIFF', 'WITCH', 'BOMB', 'BOMB_PASS') then
      raise exception '대상을 선택해 주세요.';
    end if;
  else
    select pl.alive into v_target_alive
      from public.players pl
     where pl.room_id = p_room_id and pl.uid = p_target_uid;

    if not found then
      raise exception '이 방의 참가자가 아닙니다.';
    end if;

    if p_action = 'MEDIUM' then
      if v_target_alive then
        raise exception '사망한 참가자만 확인할 수 있습니다.';
      end if;
    elsif p_action = 'FORGE' then
      null;
    else
      if not v_target_alive then
        raise exception '살아 있는 참가자만 지목할 수 있습니다.';
      end if;
    end if;

    if p_action in ('MAFIA_VOTE', 'BODYGUARD', 'KILLER', 'VIGILANTE', 'SHERIFF', 'WITCH',
                    'BOMB', 'BOMB_PASS')
       and p_target_uid = v_uid then
      raise exception '자신을 지목할 수 없습니다.';
    end if;

    if p_action in ('DOCTOR', 'BODYGUARD')
       and v_last is not null and v_last = p_target_uid then
      if p_action = 'DOCTOR' then
        raise exception '같은 사람을 연속해서 치료할 수 없습니다.';
      else
        raise exception '같은 사람을 연속해서 보호할 수 없습니다.';
      end if;
    end if;

    if p_action = 'REPORTER' and v_used then
      raise exception '취재는 게임 중 한 번만 할 수 있습니다.';
    end if;

    if p_action = 'FORGE' then
      select count(*) into v_forged
        from public.night_actions n
       where n.room_id = p_room_id and n.actor_uid = v_uid
         and n.action = 'FORGE' and n.target_uid is not null
         and n.day_number < v_room.day_number;
      if v_forged >= public.forge_limit(p_room_id) then
        raise exception '위조 기회를 모두 썼습니다.';
      end if;
    end if;
  end if;

  insert into public.night_actions (room_id, day_number, actor_uid, action, target_uid)
  values (p_room_id, v_room.day_number, v_uid, p_action, p_target_uid)
  on conflict (room_id, day_number, actor_uid, action)
    do update set target_uid = excluded.target_uid, created_at = now();

  if public.night_is_complete(p_room_id, v_room.day_number) then
    perform public.resolve_night(p_room_id);
    return json_build_object('resolved', true);
  end if;

  return json_build_object('resolved', false);
end;
$$;

grant execute on function public.submit_night_action(uuid, text, uuid) to anon, authenticated;

-- ------------------------------------------------------------
-- 8. 밤 처리 — 폭탄 넘기기·터짐·새 폭탄을 더했다 (0071 과 나머지는 같다)
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
  v_wtargets  uuid[] := '{}';
  v_vactors   uuid[] := '{}';
  v_vtargets  uuid[] := '{}';
  v_stargets  uuid[] := '{}';
  v_smisfire  uuid[] := '{}';
  v_forged    uuid[] := '{}';
  v_attacks   uuid[] := '{}';
  v_guardmap  jsonb := '[]'::jsonb;
  v_t         uuid;
  v_died      uuid[];
  v_bgives    jsonb := '[]'::jsonb;
  v_bpasses   jsonb := '[]'::jsonb;
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

  -- 2-2. 살인자 공격 대상. 살인자마다 혼자 정하므로 표결이 없다
  select coalesce(array_agg(n.target_uid), '{}') into v_ktargets
    from public.night_actions n
    join public.private_roles pr on pr.room_id = n.room_id and pr.uid = n.actor_uid
    join public.players pl       on pl.room_id = n.room_id and pl.uid = n.actor_uid
   where n.room_id = p_room_id and n.day_number = v_day
     and n.action = 'KILLER' and pr.role = 'KILLER'
     and pl.alive = true and n.target_uid is not null;

  -- 2-2-1. 마녀 공격 대상. 살인자와 같이 마녀마다 혼자 정한다
  select coalesce(array_agg(n.target_uid), '{}') into v_wtargets
    from public.night_actions n
    join public.private_roles pr on pr.room_id = n.room_id and pr.uid = n.actor_uid
    join public.players pl       on pl.room_id = n.room_id and pl.uid = n.actor_uid
   where n.room_id = p_room_id and n.day_number = v_day
     and n.action = 'WITCH' and pr.role = 'WITCH'
     and pl.alive = true and n.target_uid is not null;

  -- 2-3. 자경단 공격 대상. 게임 중 한 번뿐이라 쏘는 순간 기회를 쓴다.
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

  -- 2-3-1. 폭탄 주기·넘기기. 오늘 밤 죽더라도 살아서 낸 행동이므로 먼저 모아 둔다
  select coalesce(jsonb_agg(jsonb_build_object('b', n.actor_uid, 't', n.target_uid)), '[]'::jsonb)
    into v_bgives
    from public.night_actions n
    join public.private_roles pr on pr.room_id = n.room_id and pr.uid = n.actor_uid
    join public.players pl       on pl.room_id = n.room_id and pl.uid = n.actor_uid
   where n.room_id = p_room_id and n.day_number = v_day
     and n.action = 'BOMB' and pr.role = 'BOMBER'
     and pl.alive = true and n.target_uid is not null
     and not public.has_live_bomb(p_room_id, n.actor_uid);

  select coalesce(jsonb_agg(jsonb_build_object('h', n.actor_uid, 't', n.target_uid)), '[]'::jsonb)
    into v_bpasses
    from public.night_actions n
    join public.players pl on pl.room_id = n.room_id and pl.uid = n.actor_uid
   where n.room_id = p_room_id and n.day_number = v_day
     and n.action = 'BOMB_PASS' and pl.alive = true and n.target_uid is not null;

  -- 2-4. 보안관 공격 대상. 시민 진영을 쏜 보안관은 오인 사격으로 함께 죽는다.
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

  -- 공격 목록: 마피아 -> 살인자 -> 마녀 -> 자경단 -> 보안관. 같은 사람을 노렸으면 한 번만 친다.
  if v_target is not null then
    v_attacks := v_attacks || v_target;
  end if;
  foreach v_t in array v_ktargets || v_wtargets || v_vtargets || v_stargets loop
    if not (v_t = any (v_attacks)) then
      v_attacks := v_attacks || v_t;
    end if;
  end loop;

  -- 3. 경호원 보호 대상 (§2.5)
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

  -- 5-1. 보안관 오인 사격
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

  -- 5-2-1. 폭탄 (§2.17). 치료·보호로 막을 수 없다.
  --   넘기기 -> 가진 사람이 죽었으면 사라짐 -> 턴 +1, 4번째 턴이면 가진 사람이 터져 죽음 -> 새 폭탄
  update public.bombs b
     set holder_uid = (e ->> 't')::uuid
    from jsonb_array_elements(v_bpasses) e
   where b.room_id = p_room_id and b.active and b.holder_uid = (e ->> 'h')::uuid;

  update public.bombs b
     set active = false
    from public.players pl
   where b.room_id = p_room_id and b.active
     and pl.room_id = b.room_id and pl.uid = b.holder_uid and pl.alive = false;

  update public.bombs b
     set turn = b.turn + 1
   where b.room_id = p_room_id and b.active;

  with boom as (
    update public.bombs b
       set active = false, exploded_uid = b.holder_uid, exploded_day = v_day
     where b.room_id = p_room_id and b.active and b.turn >= 4
    returning b.holder_uid
  ), d as (
    update public.players pl
       set alive = false
     where pl.room_id = p_room_id and pl.alive = true
       and pl.uid in (select boom.holder_uid from boom)
    returning pl.uid
  )
  select coalesce(array_agg(d.uid), '{}') into v_died from d;
  v_deaths := v_deaths || v_died;

  insert into public.bombs (room_id, bomber_uid, holder_uid, turn, given_day)
  select p_room_id, (e ->> 'b')::uuid, (e ->> 't')::uuid, 1, v_day
    from jsonb_array_elements(v_bgives) e
    join public.players pl on pl.room_id = p_room_id and pl.uid = (e ->> 't')::uuid
   where pl.alive = true;

  -- 의사·경호원의 직전 대상 기록 (§6.3)
  update public.players pl
     set last_target_id = n.target_uid
    from public.night_actions n
   where n.room_id = pl.room_id
     and n.actor_uid = pl.uid
     and n.room_id = p_room_id
     and n.day_number = v_day
     and n.action in ('DOCTOR', 'BODYGUARD');

  -- 5-3. 위조 대상
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

  -- 10. 승리 조건. 마녀가 제거 퀘스트를 깼으면 즉시 승리 (다른 승리보다 먼저)
  v_winner := public.check_witch_kills(p_room_id);
  if v_winner is null then
    v_winner := public.check_winner(p_room_id);
  end if;
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
-- 9. 내 화면 정보 — 폭탄을 더했다 (0071 과 나머지는 같다)
--   bomber: { active } 폭탄광에게만. bomb: { turn, count, passed, passTarget } 가진 사람에게만.
--   bombExploded: 내가 폭탄이 터져 죽었는지
-- ------------------------------------------------------------

create or replace function public.my_game_view(p_room_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_room      public.rooms%rowtype;
  v_role      text;
  v_team      text;
  v_alive     boolean;
  v_used      boolean;
  v_last      uuid;
  v_acted     boolean;
  v_mates     json := null;
  v_night     uuid := null;
  v_day       uuid := null;
  v_n_sub     int  := null;
  v_n_exp     int  := null;
  v_d_sub     int;
  v_d_exp     int;
  v_results   json := null;
  v_as        json := null;
  v_forge     json := null;
  v_witch     json := null;
  v_wquest    text;
  v_wgoal     int;
  v_bomber    json := null;
  v_bomb      json := null;
begin
  select * into v_room from public.rooms r where r.id = p_room_id;
  if not found then
    raise exception '존재하지 않는 방입니다.';
  end if;

  select pr.role, pr.team, pr.witch_quest, pr.witch_goal
    into v_role, v_team, v_wquest, v_wgoal
    from public.private_roles pr
   where pr.room_id = p_room_id and pr.uid = v_uid;
  if not found then
    raise exception '아직 직업이 배정되지 않았습니다.';
  end if;

  select pl.alive, pl.last_target_id, pl.ability_used
    into v_alive, v_last, v_used
    from public.players pl
   where pl.room_id = p_room_id and pl.uid = v_uid;

  if v_team = 'MAFIA' then
    select json_agg(json_build_object(
             'uid', pl.uid, 'nickname', pl.nickname, 'role', pr.role, 'alive', pl.alive)
             order by pl.joined_at)
      into v_mates
      from public.private_roles pr
      join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
     where pr.room_id = p_room_id and pr.team = 'MAFIA';
  end if;

  select n.target_uid, true into v_night, v_acted
    from public.night_actions n
   where n.room_id = p_room_id
     and n.day_number = v_room.day_number
     and n.actor_uid = v_uid
     and n.action not in ('FORGE', 'BOMB_PASS');
  v_acted := coalesce(v_acted, false);

  if v_role = 'FORGER' then
    select json_build_object(
             'limit', public.forge_limit(p_room_id),
             'used', count(*) filter (where n.day_number < v_room.day_number
                                        or v_room.phase <> 'NIGHT'),
             'tonight', max(n.target_uid::text) filter (
                          where n.day_number = v_room.day_number and v_room.phase = 'NIGHT'))
      into v_forge
      from public.night_actions n
     where n.room_id = p_room_id and n.actor_uid = v_uid
       and n.action = 'FORGE' and n.target_uid is not null;
  end if;

  -- 마녀 퀘스트 (마녀에게만). 밤 처리가 끝난 제거만 센다
  if v_role = 'WITCH' and v_wquest is not null then
    v_witch := json_build_object(
      'quest',    v_wquest,
      'goal',     v_wgoal,
      'progress', case when v_wquest = 'SURVIVE' then v_room.day_number
                       else public.witch_kills(p_room_id, v_uid, v_wquest) end);
  end if;

  -- 폭탄광: 준 폭탄이 아직 돌고 있으면 새 폭탄을 줄 수 없다
  if v_role = 'BOMBER' then
    v_bomber := json_build_object('active', public.has_live_bomb(p_room_id, v_uid));
  end if;

  -- 내가 가진 폭탄. 여러 개면 가장 많이 간 턴을 보여준다. passed 는 오늘 밤 넘기기를 냈는지
  if v_alive then
    select json_build_object(
             'turn',  max(b.turn),
             'count', count(*),
             'passed', v_room.phase = 'NIGHT' and exists (
                         select 1 from public.night_actions n
                          where n.room_id = p_room_id and n.day_number = v_room.day_number
                            and n.actor_uid = v_uid and n.action = 'BOMB_PASS'),
             'passTarget', (select n.target_uid from public.night_actions n
                             where v_room.phase = 'NIGHT'
                               and n.room_id = p_room_id and n.day_number = v_room.day_number
                               and n.actor_uid = v_uid and n.action = 'BOMB_PASS'))
      into v_bomb
      from public.bombs b
     where b.room_id = p_room_id and b.holder_uid = v_uid and b.active
    having count(*) > 0;
  end if;

  -- 제거 투표 진행도. 폭탄광은 투표하지 않으므로 뺀다
  if v_team = 'MAFIA' then
    select count(*) into v_n_exp
      from public.private_roles pr
      join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
     where pr.room_id = p_room_id
       and pr.team = 'MAFIA'
       and pr.role <> 'BOMBER'
       and pl.alive = true;

    select count(*) into v_n_sub
      from public.night_actions n
     where n.room_id = p_room_id and n.day_number = v_room.day_number
       and n.action = 'MAFIA_VOTE';
  end if;

  if v_role = 'ASSASSIN' then
    select json_build_object(
             'done', true,
             'targetUid', a.target_uid,
             'guess', a.guess_role,
             'resolved', a.resolved,
             'success', a.success,
             'actualRole', a.actual_role)
      into v_as
      from public.assassinations a
     where a.room_id = p_room_id
       and a.day_number = v_room.day_number
       and a.phase = v_room.phase
       and a.actor_uid = v_uid;
    v_as := coalesce(v_as, json_build_object('done', false));
  end if;

  select d.target_uid into v_day
    from public.day_votes d
   where d.room_id = p_room_id
     and d.day_number = v_room.day_number
     and d.voter_uid = v_uid;

  select count(*) into v_d_exp
    from public.players pl
   where pl.room_id = p_room_id and pl.alive = true;

  select count(*) into v_d_sub
    from public.day_votes d
   where d.room_id = p_room_id and d.day_number = v_room.day_number;

  select json_agg(json_build_object(
           'day', pr.day_number, 'kind', pr.kind, 'payload', pr.payload)
           order by pr.day_number desc)
    into v_results
    from public.private_results pr
   where pr.room_id = p_room_id and pr.uid = v_uid;

  return json_build_object(
    'role',           v_role,
    'team',           v_team,
    'alive',          v_alive,
    'abilityUsed',    coalesce(v_used, false),
    'lastTargetId',   v_last,
    'nightActed',     v_acted,
    'assassin',       v_as,
    'canAssassinate', case when v_role = 'ASSASSIN'
                        then public.can_assassinate(p_room_id) else null end,
    'mafiaMembers',   v_mates,
    'nightSubmitted', v_night,
    'daySubmitted',   v_day,
    'forger',         v_forge,
    'witch',          v_witch,
    'bomber',         v_bomber,
    'bomb',           v_bomb,
    'bombExploded',   exists (select 1 from public.bombs b
                               where b.room_id = p_room_id and b.exploded_uid = v_uid),
    'nightProgress',  case when v_team = 'MAFIA'
                        then json_build_object('submitted', v_n_sub, 'expected', v_n_exp)
                        else null end,
    'dayProgress',    json_build_object('submitted', v_d_sub, 'expected', v_d_exp),
    'privateResults', v_results
  );
end;
$$;

grant execute on function public.my_game_view(uuid) to anon, authenticated;
