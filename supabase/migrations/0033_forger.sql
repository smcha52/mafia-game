-- ============================================================
-- 마피아 게임 · 새 직업: 위조범 (Forger)
-- ============================================================
-- 마피아 진영.
--
-- 능력
--   · 마피아 동료와 함께 제거 대상 투표(MAFIA_VOTE)에 참여한다.
--   · 그와 별도로 밤에 한 명을 "위조"할 수 있다 (선택). 살아 있는 사람, 사망자,
--     자기 자신 모두 된다.
--   · 그날 밤 위조한 사람을 조사한 직업은 오답을 받는다 (진영 뒤집기).
--       경찰·기자  마피아 진영 -> 시민 진영, 시민·중립 -> 마피아 진영
--       탐정       후보 목록에서 진짜 직업을 빼고 가짜로만 채운다
--       영매       마피아 진영 -> 시민, 시민·중립 -> 마피아
--     스파이는 마피아 진영이라 영향을 받지 않는다.
--   · 위조 횟수: 5~8명 1번 · 9~12명 2번 · 13~15명 3번.
--
-- 구성 — 랜덤 구성에서만 나온다. 마피아 진영 후보에 들어간다.
-- ============================================================

-- ------------------------------------------------------------
-- 1. 스키마 확장
-- ------------------------------------------------------------

alter table public.private_roles drop constraint if exists private_roles_role_check;
alter table public.private_roles add constraint private_roles_role_check
  check (role in ('CITIZEN','MAFIA','POLICE','DOCTOR','BODYGUARD',
                  'DETECTIVE','REPORTER','MEDIUM','SPY','JESTER','ASSASSIN','KILLER',
                  'VIGILANTE','SHERIFF','FORGER'));

alter table public.night_actions drop constraint if exists night_actions_action_check;
alter table public.night_actions add constraint night_actions_action_check
  check (action in ('MAFIA_VOTE','DOCTOR','BODYGUARD','POLICE',
                    'DETECTIVE','REPORTER','MEDIUM','ASSASSIN','KILLER','VIGILANTE',
                    'SHERIFF','FORGE'));

-- ------------------------------------------------------------
-- 2. 진영과 목록
-- ------------------------------------------------------------

create or replace function public.team_of(p_role text)
returns text
language sql
immutable
as $$
  select case
    when p_role in ('MAFIA', 'SPY', 'ASSASSIN', 'FORGER') then 'MAFIA'
    when p_role in ('JESTER', 'KILLER')                   then 'NEUTRAL'
    else 'CITIZEN'
  end;
$$;

-- 위조범은 마피아 투표를 내야 하므로 밤에 행동하는 직업이다
create or replace function public.night_actor_roles()
returns text[]
language sql
immutable
as $$
  select array['MAFIA', 'SPY', 'ASSASSIN', 'FORGER', 'POLICE', 'DOCTOR', 'BODYGUARD',
               'DETECTIVE', 'REPORTER', 'MEDIUM', 'KILLER', 'VIGILANTE', 'SHERIFF'];
$$;

create or replace function public.toggleable_roles()
returns text[]
language sql
immutable
as $$
  select array['MAFIA', 'POLICE', 'DOCTOR', 'BODYGUARD', 'DETECTIVE',
               'REPORTER', 'MEDIUM', 'SPY', 'JESTER', 'ASSASSIN', 'KILLER',
               'VIGILANTE', 'SHERIFF', 'FORGER'];
$$;

-- ------------------------------------------------------------
-- 3. 위조 도우미
-- ------------------------------------------------------------

-- 위조 횟수: 5~8명 1 · 9~12명 2 · 13~15명 3
create or replace function public.forge_limit(p_room_id uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select case
    when count(*) <= 8  then 1
    when count(*) <= 12 then 2
    else 3
  end
  from public.players pl
  where pl.room_id = p_room_id;
$$;

revoke all on function public.forge_limit(uuid) from public, anon, authenticated;

-- 진영 뒤집기: 마피아 진영은 시민으로, 시민·중립은 마피아로
create or replace function public.forged_team(p_team text)
returns text
language sql
immutable
as $$
  select case when p_team = 'MAFIA' then 'CITIZEN' else 'MAFIA' end;
$$;

-- 탐정 후보에서 진짜 직업을 빼고 같은 수의 가짜로 채운다
create or replace function public.forged_candidates(p_room_id uuid, p_target_uid uuid)
returns text[]
language plpgsql
security definer
set search_path = public
as $$
declare
  v_true  text;
  v_cand  text[];
  v_fakes text[];
  v_extra text;
begin
  select pr.role into v_true
    from public.private_roles pr
   where pr.room_id = p_room_id and pr.uid = p_target_uid;
  if not found then
    return null;
  end if;

  v_cand  := public.detective_candidates(p_room_id, p_target_uid);
  v_fakes := array(select x from unnest(v_cand) x where x <> v_true);

  -- 빠진 자리를 이 판의 다른 직업으로, 없으면 전체 직업 중에서 채운다
  select x into v_extra
    from (
      select distinct pr.role as x
        from public.private_roles pr
       where pr.room_id = p_room_id
      union
      select unnest(array['CITIZEN','MAFIA','POLICE','DOCTOR','BODYGUARD','DETECTIVE',
                          'REPORTER','MEDIUM','SPY','JESTER','ASSASSIN','KILLER',
                          'VIGILANTE','SHERIFF','FORGER'])
    ) t
   where x <> v_true and not (x = any (v_fakes))
   order by random()
   limit 1;

  return array(select y from unnest(v_fakes || v_extra) y order by random());
end;
$$;

revoke all on function public.forged_candidates(uuid, uuid) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 4. 랜덤 구성 — 마피아 진영 후보에 위조범을 더했다
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
    from unnest(array['JESTER', 'KILLER']) x
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
      select x from unnest(array['JESTER', 'KILLER']) x
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
-- 5. 밤 완료 판정 — 사람 수로 세고 위조는 제외한다
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
     and not (pr.role = 'MEDIUM' and v_dead = 0);

  -- 행동한 사람 수를 센다. 위조범은 마피아 투표와 위조를 둘 다 낼 수 있으므로
  -- 행 수가 아니라 사람 수로 세고, 선택 행동인 위조는 제외한다.
  select count(distinct n.actor_uid) into v_submitted
    from public.night_actions n
    join public.players pl on pl.room_id = n.room_id and pl.uid = n.actor_uid
   where n.room_id = p_room_id
     and n.day_number = p_day
     and n.action <> 'FORGE'
     and pl.alive = true;

  return v_submitted >= v_expected;
end;
$$;

revoke all on function public.night_is_complete(uuid, int) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 6. 밤 행동 제출 — 0032 본문에 FORGE 를 더하고, 마피아 투표를 진영 기준으로 바꿨다
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
    if public.team_of(v_role) <> 'MAFIA' then
      raise exception '사용할 수 없는 능력입니다.';
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
      else null
    end;

    if v_needed is null then
      raise exception '아직 구현되지 않은 능력입니다: %', p_action;
    end if;
    if v_role <> v_needed then
      raise exception '사용할 수 없는 능력입니다.';
    end if;
  end if;

  -- 자경단은 한 번 제거하면 끝이다. 건너뛰기도 더 받지 않는다.
  if p_action = 'VIGILANTE' and v_used then
    raise exception '당신은 제거를 이미 했습니다.';
  end if;

  if p_target_uid is null then
    if p_action not in ('REPORTER', 'VIGILANTE', 'SHERIFF') then
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
      null;  -- 영매 조사를 막으려면 사망자도 위조할 수 있어야 한다. 자기 자신도 된다.
    else
      if not v_target_alive then
        raise exception '살아 있는 참가자만 지목할 수 있습니다.';
      end if;
    end if;

    if p_action in ('MAFIA_VOTE', 'BODYGUARD', 'KILLER', 'VIGILANTE', 'SHERIFF') and p_target_uid = v_uid then
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

    -- 위조 횟수: 지난 밤들에 낸 위조만 센다. 오늘 밤 것은 바꿀 수 있다.
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
-- 7. 밤 처리 — 0032 본문의 조사 결과에 위조를 반영했다
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
  v_ktarget   uuid;
  v_vactor    uuid;
  v_vtarget   uuid;
  v_sactor    uuid;
  v_starget   uuid;
  v_steam     text;
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

  -- 2-2. 살인자 공격 대상. 살인자는 혼자 정하므로 표결이 없다.
  select n.target_uid into v_ktarget
    from public.night_actions n
    join public.private_roles pr on pr.room_id = n.room_id and pr.uid = n.actor_uid
    join public.players pl       on pl.room_id = n.room_id and pl.uid = n.actor_uid
   where n.room_id = p_room_id and n.day_number = v_day
     and n.action = 'KILLER' and pr.role = 'KILLER'
     and pl.alive = true and n.target_uid is not null
   limit 1;

  -- 2-3. 자경단 공격 대상. 게임 중 한 번뿐이라 쏘는 순간 기회를 쓴다.
  --      치료·경호에 막혀도 다시 쏠 수 없다.
  select n.actor_uid, n.target_uid into v_vactor, v_vtarget
    from public.night_actions n
    join public.private_roles pr on pr.room_id = n.room_id and pr.uid = n.actor_uid
    join public.players pl       on pl.room_id = n.room_id and pl.uid = n.actor_uid
   where n.room_id = p_room_id and n.day_number = v_day
     and n.action = 'VIGILANTE' and pr.role = 'VIGILANTE'
     and pl.alive = true and pl.ability_used = false
     and n.target_uid is not null
   limit 1;

  if v_vactor is not null then
    update public.players pl
       set ability_used = true
     where pl.room_id = p_room_id and pl.uid = v_vactor;
  end if;

  -- 2-4. 보안관 공격 대상과 그 사람의 진영. 진영은 오인 사격 판정에 쓴다.
  select n.actor_uid, n.target_uid, tgt.team into v_sactor, v_starget, v_steam
    from public.night_actions n
    join public.private_roles pr  on pr.room_id = n.room_id and pr.uid = n.actor_uid
    join public.players pl        on pl.room_id = n.room_id and pl.uid = n.actor_uid
    join public.private_roles tgt on tgt.room_id = n.room_id and tgt.uid = n.target_uid
   where n.room_id = p_room_id and n.day_number = v_day
     and n.action = 'SHERIFF' and pr.role = 'SHERIFF'
     and pl.alive = true and n.target_uid is not null
   limit 1;

  -- 공격 목록: 마피아 -> 살인자 -> 자경단 -> 보안관. 같은 사람을 노렸으면 한 번만 친다.
  if v_target is not null then
    v_attacks := v_attacks || v_target;
  end if;
  if v_ktarget is not null and not (v_ktarget = any (v_attacks)) then
    v_attacks := v_attacks || v_ktarget;
  end if;
  if v_vtarget is not null and not (v_vtarget = any (v_attacks)) then
    v_attacks := v_attacks || v_vtarget;
  end if;
  if v_starget is not null and not (v_starget = any (v_attacks)) then
    v_attacks := v_attacks || v_starget;
  end if;

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
  if v_sactor is not null and v_steam = 'CITIZEN' then
    with d as (
      update public.players pl
         set alive = false
       where pl.room_id = p_room_id and pl.uid = v_sactor and pl.alive = true
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

-- ------------------------------------------------------------
-- 8. 암살자가 위조범을 찍을 수 있게 한다
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
      'DETECTIVE','REPORTER','MEDIUM','SPY','JESTER','ASSASSIN','KILLER','VIGILANTE','SHERIFF','FORGER') then
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

-- ------------------------------------------------------------
-- 9. 내 화면 정보 — 0020 본문에서 마피아 판정을 진영 기준으로 바꾸고 위조 상태를 더했다
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
begin
  select * into v_room from public.rooms r where r.id = p_room_id;
  if not found then
    raise exception '존재하지 않는 방입니다.';
  end if;

  select pr.role, pr.team into v_role, v_team
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
     and n.action <> 'FORGE';
  v_acted := coalesce(v_acted, false);

  -- 위조 상태 (위조범에게만). used 는 지난 밤들의 위조 수다.
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

  if v_team = 'MAFIA' then
    select count(*) into v_n_exp
      from public.private_roles pr
      join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
     where pr.room_id = p_room_id
       and pr.team = 'MAFIA'
       and pl.alive = true;

    select count(*) into v_n_sub
      from public.night_actions n
     where n.room_id = p_room_id and n.day_number = v_room.day_number
       and n.action = 'MAFIA_VOTE';
  end if;

  -- 이번 페이즈의 저격 상태 (암살자에게만)
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
    'nightProgress',  case when v_team = 'MAFIA'
                        then json_build_object('submitted', v_n_sub, 'expected', v_n_exp)
                        else null end,
    'dayProgress',    json_build_object('submitted', v_d_sub, 'expected', v_d_exp),
    'privateResults', v_results
  );
end;
$$;

grant execute on function public.my_game_view(uuid) to anon, authenticated;
