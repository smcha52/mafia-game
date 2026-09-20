-- ============================================================
-- 마피아 게임 · §8.2-8  스파이 (능력 변경판)
-- ============================================================
-- 바뀐 §2.9
--   · 스파이는 마피아 진영이다 (변경 없음)
--   · 마피아와 스파이는 서로의 정체를 안다 (변경 없음)
--   · [변경] 밤에 마피아의 공격 투표에 "참여한다"
--            (기존: 참여하지 않는다)
--   · 낮의 처형 투표에서 생존자 한 명을 선택한다
--   · 투표를 확정하는 순간, 그 사람의 정확한 직업을 즉시 확인한다.
--     확률이 아니라 항상 확인된다
--   · 확인 결과는 스파이에게만 보인다
--   · 투표를 제출한 뒤에는 대상을 변경할 수 없다 (변경 없음)
--   · 하루에 한 번만 확인할 수 있다 — 투표가 하루 한 번이므로
--     별도 제한 없이 지켜진다
--   · 마피아 진영의 승리 조건을 함께 적용받는다 (변경 없음)
--   · 경찰이 조사하면 마피아 진영으로 표시된다 (변경 없음)
-- ============================================================

-- ------------------------------------------------------------
-- 1. 밤에 행동하는 직업에 스파이 추가
-- ------------------------------------------------------------

create or replace function public.night_actor_roles()
returns text[]
language sql
immutable
as $$
  select array['MAFIA', 'SPY', 'POLICE', 'DOCTOR', 'BODYGUARD',
               'DETECTIVE', 'REPORTER', 'MEDIUM'];
$$;

-- ------------------------------------------------------------
-- 2. 밤 행동 제출 — 스파이도 공격 투표를 낸다
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

  -- 공격 투표는 마피아와 스파이가 함께 낸다 (바뀐 §2.9)
  if p_action = 'MAFIA_VOTE' then
    if v_role not in ('MAFIA', 'SPY') then
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

  -- 기자만 대상 없이 제출할 수 있다 (= 오늘은 쓰지 않는다)
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
-- 3. 낮 투표 — 스파이는 확정하는 순간 직업을 확인한다 (§2.9)
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
  v_role      text;
  v_alive     boolean;
  v_t_role    text;
  v_t_nick    text;
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

  -- 제출한 뒤에는 바꿀 수 없다 (§2.9 를 전원에게 적용)
  if exists (
    select 1 from public.day_votes d
     where d.room_id = p_room_id and d.day_number = v_room.day_number
       and d.voter_uid = v_uid
  ) then
    raise exception '이미 투표했습니다. 변경할 수 없습니다.';
  end if;

  insert into public.day_votes (room_id, day_number, voter_uid, target_uid)
  values (p_room_id, v_room.day_number, v_uid, p_target_uid);

  -- 스파이는 투표를 확정하는 순간 대상의 정확한 직업을 확인한다.
  -- 확률이 아니라 항상 확인된다. 투표가 하루 한 번이므로
  -- "하루에 한 번만" 제한은 자동으로 지켜진다.
  select pr.role into v_role
    from public.private_roles pr
   where pr.room_id = p_room_id and pr.uid = v_uid;

  if v_role = 'SPY' then
    select pr.role, pl.nickname into v_t_role, v_t_nick
      from public.private_roles pr
      join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
     where pr.room_id = p_room_id and pr.uid = p_target_uid;

    insert into public.private_results (room_id, uid, day_number, kind, payload)
    values (p_room_id, v_uid, v_room.day_number, 'SPY',
            jsonb_build_object('targetUid', p_target_uid,
                               'targetNickname', v_t_nick,
                               'role', v_t_role))
    on conflict (room_id, uid, day_number, kind) do update set payload = excluded.payload;
  end if;

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

grant execute on function public.submit_day_vote(uuid, uuid) to anon, authenticated;

-- ------------------------------------------------------------
-- 4. 화면 조회 — 스파이도 공격 투표 진행 상황을 본다
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

  if v_role in ('MAFIA', 'SPY') then
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
     and n.actor_uid = v_uid;
  v_acted := coalesce(v_acted, false);

  -- 공격 투표에 참여하는 사람에게만 진행 상황을 보여준다
  if v_role in ('MAFIA', 'SPY') then
    select count(*) into v_n_exp
      from public.private_roles pr
      join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
     where pr.room_id = p_room_id
       and pr.role in ('MAFIA', 'SPY')
       and pl.alive = true;

    select count(*) into v_n_sub
      from public.night_actions n
     where n.room_id = p_room_id and n.day_number = v_room.day_number
       and n.action = 'MAFIA_VOTE';
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
    'mafiaMembers',   v_mates,
    'nightSubmitted', v_night,
    'daySubmitted',   v_day,
    'nightProgress',  case when v_role in ('MAFIA', 'SPY')
                        then json_build_object('submitted', v_n_sub, 'expected', v_n_exp)
                        else null end,
    'dayProgress',    json_build_object('submitted', v_d_sub, 'expected', v_d_exp),
    'privateResults', v_results
  );
end;
$$;

grant execute on function public.my_game_view(uuid) to anon, authenticated;
