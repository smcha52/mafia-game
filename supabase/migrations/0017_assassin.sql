-- ============================================================
-- 마피아 게임 · 새 직업: 암살자 (Assassin)
-- ============================================================
-- 마피아 진영. 밤에 두 가지 중 하나를 고른다.
--   1) 일반 공격 투표에 참여 (마피아와 동일)
--   2) 암살 — 대상 한 명을 고르고 그 사람의 "정확한 직업" 을 맞힌다
--        맞히면 대상이 즉시 사망
--        틀리면 암살자 자신이 사망
--
-- 제한
--   · 살아 있는 다른 사람의 직업이 전부 시민이면 암살할 수 없다.
--     시민만 남으면 "시민" 을 찍어 확실히 죽이는 수단이 되어버린다.
--   · 자기 자신은 대상으로 고를 수 없다.
--   · 한 밤에 일반 공격과 암살을 동시에 할 수 없다.
--     암살을 제출하면 그 밤의 공격 투표는 취소된다.
--
-- 의사 치료와 경호원 보호는 암살을 막지 못한다.
-- 정확한 직업을 맞혀야 하고 틀리면 자기가 죽으므로, 성공에는
-- 확실한 보상이 있어야 능력이 성립한다. (§2.4 는 "마피아의 공격 대상"
-- 에만 치료가 적용된다고 한정하므로 규칙 충돌도 아니다)
--
-- 구성
--   7~11명  마피아 2 -> 마피아 1 + 암살자 1
--   12~15명 마피아 3 -> 마피아 2 + 암살자 1
--   5~6명   마피아가 1명뿐이라 넣지 않는다
--   끄면 암살자 자리는 "마피아" 로 돌아간다 (시민이 아니다)
-- ============================================================

-- ------------------------------------------------------------
-- 1. 스키마 확장
-- ------------------------------------------------------------

alter table public.private_roles drop constraint if exists private_roles_role_check;
alter table public.private_roles add constraint private_roles_role_check
  check (role in ('CITIZEN','MAFIA','POLICE','DOCTOR','BODYGUARD',
                  'DETECTIVE','REPORTER','MEDIUM','SPY','JESTER','ASSASSIN'));

alter table public.night_actions drop constraint if exists night_actions_action_check;
alter table public.night_actions add constraint night_actions_action_check
  check (action in ('MAFIA_VOTE','DOCTOR','BODYGUARD','POLICE',
                    'DETECTIVE','REPORTER','MEDIUM','ASSASSIN'));

-- 암살이 찍은 직업. 다른 행동에서는 비어 있다.
alter table public.night_actions
  add column if not exists guess_role text;

alter table public.private_results drop constraint if exists private_results_kind_check;
alter table public.private_results add constraint private_results_kind_check
  check (kind in ('POLICE','DOCTOR','BODYGUARD','DETECTIVE',
                  'REPORTER','MEDIUM','SPY','ASSASSIN'));

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
    when p_role = 'JESTER'                      then 'NEUTRAL'
    else 'CITIZEN'
  end;
$$;

create or replace function public.night_actor_roles()
returns text[]
language sql
immutable
as $$
  select array['MAFIA', 'SPY', 'ASSASSIN', 'POLICE', 'DOCTOR', 'BODYGUARD',
               'DETECTIVE', 'REPORTER', 'MEDIUM'];
$$;

create or replace function public.toggleable_roles()
returns text[]
language sql
immutable
as $$
  select array['POLICE', 'DOCTOR', 'BODYGUARD', 'DETECTIVE',
               'REPORTER', 'MEDIUM', 'SPY', 'JESTER', 'ASSASSIN'];
$$;

-- 끈 직업을 무엇으로 대체할지. 암살자만 마피아로 돌아간다.
create or replace function public.role_fallback(p_role text)
returns text
language sql
immutable
as $$
  select case when p_role = 'ASSASSIN' then 'MAFIA' else 'CITIZEN' end;
$$;

-- ------------------------------------------------------------
-- 3. 구성표에 암살자를 넣는다
-- ------------------------------------------------------------

drop function if exists public.role_composition(int, text[]);

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
    when 9  then array['MAFIA','ASSASSIN','SPY','POLICE','DOCTOR','DETECTIVE','CITIZEN','CITIZEN','CITIZEN']
    when 10 then array['MAFIA','ASSASSIN','SPY','POLICE','DOCTOR','BODYGUARD','DETECTIVE','CITIZEN','CITIZEN','CITIZEN']
    when 11 then array['MAFIA','ASSASSIN','SPY','POLICE','DOCTOR','BODYGUARD','DETECTIVE','REPORTER','CITIZEN','CITIZEN','CITIZEN']
    when 12 then array['MAFIA','MAFIA','ASSASSIN','SPY','POLICE','DOCTOR','BODYGUARD','DETECTIVE','REPORTER','JESTER','CITIZEN','CITIZEN']
    when 13 then array['MAFIA','MAFIA','ASSASSIN','SPY','POLICE','DOCTOR','BODYGUARD','DETECTIVE','REPORTER','MEDIUM','JESTER','CITIZEN','CITIZEN']
    when 14 then array['MAFIA','MAFIA','ASSASSIN','SPY','POLICE','DOCTOR','BODYGUARD','DETECTIVE','REPORTER','MEDIUM','JESTER','CITIZEN','CITIZEN','CITIZEN']
    when 15 then array['MAFIA','MAFIA','ASSASSIN','SPY','POLICE','DOCTOR','BODYGUARD','DETECTIVE','REPORTER','MEDIUM','JESTER','CITIZEN','CITIZEN','CITIZEN','CITIZEN']
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
-- 4. 암살 가능 여부 — 살아 있는 다른 사람이 전부 시민이면 불가
-- ------------------------------------------------------------

create or replace function public.can_assassinate(p_room_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
      from public.private_roles pr
      join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
     where pr.room_id = p_room_id
       and pl.alive = true
       and pr.uid <> auth.uid()
       and pr.role <> 'CITIZEN'
  );
$$;

grant execute on function public.can_assassinate(uuid) to anon, authenticated;

-- ------------------------------------------------------------
-- 5. 암살 제출
-- ------------------------------------------------------------
-- 별도 RPC 로 둔다. submit_night_action 에 인자를 더하면 이전 시그니처가
-- 남아 PostgREST 가 PGRST203 을 낸다 (0012, 0016 에서 겪은 문제).

create or replace function public.submit_assassination(
  p_room_id uuid, p_target_uid uuid, p_guess text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_room  public.rooms%rowtype;
  v_role  text;
  v_alive boolean;
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
  if v_role <> 'ASSASSIN' then
    raise exception '암살자만 사용할 수 있습니다.';
  end if;

  select pl.alive into v_alive
    from public.players pl
   where pl.room_id = p_room_id and pl.uid = v_uid;
  if not v_alive then
    raise exception '사망한 참가자는 능력을 사용할 수 없습니다.';
  end if;

  if not public.can_assassinate(p_room_id) then
    raise exception '살아 있는 사람이 모두 시민이면 암살할 수 없습니다.';
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
      'DETECTIVE','REPORTER','MEDIUM','SPY','JESTER','ASSASSIN') then
    raise exception '직업을 선택해 주세요.';
  end if;

  -- 같은 밤에 일반 공격과 암살을 동시에 할 수 없다
  delete from public.night_actions n
   where n.room_id = p_room_id
     and n.day_number = v_room.day_number
     and n.actor_uid = v_uid
     and n.action = 'MAFIA_VOTE';

  insert into public.night_actions
    (room_id, day_number, actor_uid, action, target_uid, guess_role)
  values
    (p_room_id, v_room.day_number, v_uid, 'ASSASSIN', p_target_uid, p_guess)
  on conflict (room_id, day_number, actor_uid, action)
    do update set target_uid = excluded.target_uid,
                  guess_role = excluded.guess_role,
                  created_at = now();

  if public.night_is_complete(p_room_id, v_room.day_number) then
    perform public.resolve_night(p_room_id);
    return json_build_object('resolved', true);
  end if;

  return json_build_object('resolved', false);
end;
$$;

grant execute on function public.submit_assassination(uuid, uuid, text) to anon, authenticated;

-- 일반 공격을 제출하면 그 밤의 암살은 취소된다
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

  -- 공격 투표는 마피아·스파이·암살자가 함께 낸다
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

    if p_action in ('MAFIA_VOTE', 'BODYGUARD') and p_target_uid = v_uid then
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

  -- 암살자가 일반 공격을 고르면 그 밤의 암살은 취소한다
  if p_action = 'MAFIA_VOTE' and v_role = 'ASSASSIN' then
    delete from public.night_actions n
     where n.room_id = p_room_id
       and n.day_number = v_room.day_number
       and n.actor_uid = v_uid
       and n.action = 'ASSASSIN';
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
