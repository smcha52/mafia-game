-- ============================================================
-- 마피아 게임 · 새 직업: 살인자 (Killer)
-- ============================================================
-- 중립 진영. 광대와는 다른 승리 조건을 가진다.
--
-- 능력
--   · 밤마다 혼자 제거할 사람을 고른다. 마피아·시민·중립 누구든 된다.
--     마피아 공격과 별개로 처리되므로 한 밤에 두 명이 죽을 수 있다.
--   · 자기 자신은 고를 수 없다.
--   · 의사 치료와 경호원 보호가 마피아 공격과 똑같이 막는다.
--
-- 승리
--   · 살인자가 살아 있고 생존자가 2명 이하가 되면(누구와든 1:1) 살인자 단독 승리.
--     마피아와 1:1 이어도 살인자가 이긴다.
--   · 살인자가 살아 있는 동안에는 시민·마피아 모두 이길 수 없다.
--     시민은 마피아와 살인자를 모두 없애야 하고, 마피아도 살인자를 없애야 한다.
--   · 광대 처형 승리(§4.1)는 그대로 가장 먼저 본다.
--
-- 조사 결과
--   · 경찰: 중립 (private_roles.team = 'NEUTRAL' 그대로)
--   · 기자: 시민 — 0022 의 광대 위장이 team 기준이라 그대로 적용된다
--   · 탐정·영매·스파이: 정확한 직업 (기존 동작)
--   · 낮 처형 공개(0023): 중립이라 직업(KILLER)이 공개된다
--
-- 구성 — 9명 이상에서 시민 한 자리를 살인자로 바꾼다.
--   방장이 끄면 시민으로 돌아간다 (role_fallback 기본값).
-- ============================================================

-- ------------------------------------------------------------
-- 1. 스키마 확장
-- ------------------------------------------------------------

alter table public.private_roles drop constraint if exists private_roles_role_check;
alter table public.private_roles add constraint private_roles_role_check
  check (role in ('CITIZEN','MAFIA','POLICE','DOCTOR','BODYGUARD',
                  'DETECTIVE','REPORTER','MEDIUM','SPY','JESTER','ASSASSIN','KILLER'));

alter table public.night_actions drop constraint if exists night_actions_action_check;
alter table public.night_actions add constraint night_actions_action_check
  check (action in ('MAFIA_VOTE','DOCTOR','BODYGUARD','POLICE',
                    'DETECTIVE','REPORTER','MEDIUM','ASSASSIN','KILLER'));

alter table public.rooms drop constraint if exists rooms_winner_check;
alter table public.rooms add constraint rooms_winner_check
  check (winner is null or winner in ('CITIZEN', 'MAFIA', 'JESTER', 'KILLER', 'DRAW'));

-- ------------------------------------------------------------
-- 2. 진영과 목록
-- ------------------------------------------------------------

create or replace function public.team_of(p_role text)
returns text
language sql
immutable
as $$
  select case
    when p_role in ('MAFIA', 'SPY', 'ASSASSIN') then 'MAFIA'
    when p_role in ('JESTER', 'KILLER')         then 'NEUTRAL'
    else 'CITIZEN'
  end;
$$;

create or replace function public.night_actor_roles()
returns text[]
language sql
immutable
as $$
  select array['MAFIA', 'SPY', 'ASSASSIN', 'POLICE', 'DOCTOR', 'BODYGUARD',
               'DETECTIVE', 'REPORTER', 'MEDIUM', 'KILLER'];
$$;

create or replace function public.toggleable_roles()
returns text[]
language sql
immutable
as $$
  select array['POLICE', 'DOCTOR', 'BODYGUARD', 'DETECTIVE',
               'REPORTER', 'MEDIUM', 'SPY', 'JESTER', 'ASSASSIN', 'KILLER'];
$$;

-- ------------------------------------------------------------
-- 3. 구성표 — 9명 이상에서 시민 한 자리를 살인자로
-- ------------------------------------------------------------

create or replace function public.role_composition(
  p_count int, p_disabled text[] default '{}')
returns text[]
language plpgsql
immutable
as $$
declare
  v   text[];
  v2  text[];
  off text[] := coalesce(p_disabled, '{}');
begin
  v := case p_count
    when 5  then array['MAFIA','POLICE','DOCTOR','CITIZEN','CITIZEN']
    when 6  then array['MAFIA','POLICE','DOCTOR','BODYGUARD','CITIZEN','CITIZEN']
    when 7  then array['MAFIA','ASSASSIN','POLICE','DOCTOR','JESTER','CITIZEN','CITIZEN']
    when 8  then array['MAFIA','ASSASSIN','POLICE','DOCTOR','BODYGUARD','JESTER','CITIZEN','CITIZEN']
    when 9  then array['MAFIA','ASSASSIN','SPY','POLICE','DOCTOR','DETECTIVE','KILLER','CITIZEN','CITIZEN']
    when 10 then array['MAFIA','ASSASSIN','SPY','POLICE','DOCTOR','BODYGUARD','DETECTIVE','KILLER','CITIZEN','CITIZEN']
    when 11 then array['MAFIA','ASSASSIN','SPY','POLICE','DOCTOR','BODYGUARD','DETECTIVE','REPORTER','KILLER','CITIZEN','CITIZEN']
    when 12 then array['MAFIA','MAFIA','ASSASSIN','SPY','POLICE','DOCTOR','BODYGUARD','DETECTIVE','REPORTER','JESTER','KILLER','CITIZEN']
    when 13 then array['MAFIA','MAFIA','ASSASSIN','SPY','POLICE','DOCTOR','BODYGUARD','DETECTIVE','REPORTER','MEDIUM','JESTER','KILLER','CITIZEN']
    when 14 then array['MAFIA','MAFIA','ASSASSIN','SPY','POLICE','DOCTOR','BODYGUARD','DETECTIVE','REPORTER','MEDIUM','JESTER','KILLER','CITIZEN','CITIZEN']
    when 15 then array['MAFIA','MAFIA','ASSASSIN','SPY','POLICE','DOCTOR','BODYGUARD','DETECTIVE','REPORTER','MEDIUM','JESTER','KILLER','CITIZEN','CITIZEN','CITIZEN']
    else null
  end;

  if v is null then
    raise exception '% 명은 지원하지 않습니다. (5~15명)', p_count;
  end if;

  -- 꺼진 직업은 대체 직업으로 바꾼다. 순서를 지켜 인원수가 변하지 않게 한다.
  select array_agg(
           case when t.x = any (off) then public.role_fallback(t.x) else t.x end
           order by t.ord)
    into v2
    from unnest(v) with ordinality as t(x, ord);

  if array_length(v2, 1) <> p_count then
    raise exception '구성표 오류: %명 구성의 직업 수가 %개입니다.', p_count, array_length(v2, 1);
  end if;

  return v2;
end;
$$;

grant execute on function public.role_composition(int, text[]) to anon, authenticated;

-- ------------------------------------------------------------
-- 4. 승리 조건
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
  -- §4.1 광대 승리 — 다른 조건보다 먼저 검사한다
  if p_executed_uid is not null then
    select r.jester_uid into v_jester from public.rooms r where r.id = p_room_id;
    if v_jester is not null and v_jester = p_executed_uid then
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
-- 5. 밤 행동 제출 — 0019 본문에 KILLER 만 더했다
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
    if v_role not in ('MAFIA', 'SPY', 'ASSASSIN') then
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
      else null
    end;

    if v_needed is null then
      raise exception '아직 구현되지 않은 능력입니다: %', p_action;
    end if;
    if v_role <> v_needed then
      raise exception '사용할 수 없는 능력입니다.';
    end if;
  end if;

  if p_target_uid is null then
    if p_action <> 'REPORTER' then
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
    else
      if not v_target_alive then
        raise exception '살아 있는 참가자만 지목할 수 있습니다.';
      end if;
    end if;

    if p_action in ('MAFIA_VOTE', 'BODYGUARD', 'KILLER') and p_target_uid = v_uid then
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
-- 6. 밤 처리 — 0022 본문에서 공격을 "마피아 -> 살인자" 목록으로 바꿨다
-- ------------------------------------------------------------
-- 치료·경호 판정과 의사·경호원 결과를 공격마다 따로 계산한다.
-- 저격(치료·경호 무시)과 조사·취재 부분은 그대로다.

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

  -- 공격 목록: 마피아 -> 살인자. 같은 사람을 노렸으면 한 번만 친다.
  if v_target is not null then
    v_attacks := v_attacks || v_target;
  end if;
  if v_ktarget is not null and not (v_ktarget = any (v_attacks)) then
    v_attacks := v_attacks || v_ktarget;
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
                               'team', v_rec.target_team))
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
                public.detective_candidates(p_room_id, v_rec.target_uid))))
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
                               'role', v_rec.target_role))
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
                                          when v_rec.target_team = 'NEUTRAL' then 'CITIZEN'
                                          else v_rec.target_team end))
    on conflict (room_id, uid, day_number, kind) do update set payload = excluded.payload;

    if v_ok then
      v_reveal := v_reveal || jsonb_build_object(
        'targetUid', v_rec.target_uid,
        'targetNickname', v_rec.target_nick,
        'team', case when v_rec.target_team = 'NEUTRAL' then 'CITIZEN'
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
-- 7. 암살자가 살인자를 찍을 수 있게 한다 — 0021 본문에서 직업 목록만 바꿨다
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
      'DETECTIVE','REPORTER','MEDIUM','SPY','JESTER','ASSASSIN','KILLER') then
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
