-- ============================================================
-- 마피아 게임 · §8.2-7  영매
-- ============================================================
-- §2.8
--   · 밤마다 사망자 한 명을 선택한다
--   · 선택한 사망자의 "정확한 직업" 을 확인한다
--   · 확인 결과는 영매에게만 보인다
--   · 아직 사망자가 없으면 능력을 사용할 수 없다
--
-- 다른 직업과 다른 점
--   1. 대상이 살아 있는 사람이 아니라 사망자다
--   2. 사망자가 없는 밤(보통 1일차)에는 아예 행동할 수 없다.
--      이때 영매를 기다리면 밤이 제한시간까지 멈추므로
--      밤 종료 조건에서 빼야 한다.
-- ============================================================

create or replace function public.night_actor_roles()
returns text[]
language sql
immutable
as $$
  select array['MAFIA', 'POLICE', 'DOCTOR', 'BODYGUARD',
               'DETECTIVE', 'REPORTER', 'MEDIUM'];
$$;

-- ------------------------------------------------------------
-- 1. 밤 종료 조건 — 사망자가 없으면 영매를 기다리지 않는다
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
     and not (pr.role = 'REPORTER' and pl.ability_used = true)
     -- 사망자가 없으면 영매는 능력을 쓸 수 없다 (§2.8)
     and not (pr.role = 'MEDIUM' and v_dead = 0);

  select count(*) into v_submitted
    from public.night_actions n
    join public.players pl on pl.room_id = n.room_id and pl.uid = n.actor_uid
   where n.room_id = p_room_id
     and n.day_number = p_day
     and pl.alive = true;

  return v_submitted >= v_expected;
end;
$$;

revoke all on function public.night_is_complete(uuid, int) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 2. 밤 처리에 영매를 끼워 넣는다 (§3 순서 8번)
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
begin
  select r.day_number into v_day from public.rooms r where r.id = p_room_id;

  -- 1. 마피아 공격 대상 확정 (§2.2)
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

  -- 2. 의사 치료 대상 확인 (§2.4)
  select coalesce(array_agg(n.target_uid), '{}')
    into v_healed
    from public.night_actions n
    join public.private_roles pr on pr.room_id = n.room_id and pr.uid = n.actor_uid
    join public.players pl       on pl.room_id = n.room_id and pl.uid = n.actor_uid
   where n.room_id = p_room_id and n.day_number = v_day
     and n.action = 'DOCTOR' and pr.role = 'DOCTOR'
     and pl.alive = true and n.target_uid is not null;

  -- 3. 경호원 보호 대상 확인 (§2.5)
  if v_target is not null then
    select coalesce(array_agg(n.actor_uid), '{}')
      into v_guards
      from public.night_actions n
      join public.private_roles pr on pr.room_id = n.room_id and pr.uid = n.actor_uid
      join public.players pl       on pl.room_id = n.room_id and pl.uid = n.actor_uid
     where n.room_id = p_room_id and n.day_number = v_day
       and n.action = 'BODYGUARD' and pr.role = 'BODYGUARD'
       and pl.alive = true and n.target_uid = v_target;
  end if;

  -- 4~5. 생존·사망 계산 (§3.1 — 치료를 먼저 적용한다)
  if v_target is not null then
    if v_target = any (v_healed) then
      v_saved := true;
    elsif array_length(v_guards, 1) > 0 then
      v_shielded := true;
      update public.players pl
         set alive = false
       where pl.room_id = p_room_id and pl.uid = any (v_guards) and pl.alive = true;
      select coalesce(array_agg(g), '{}') into v_deaths from unnest(v_guards) g;
    else
      update public.players pl
         set alive = false
       where pl.room_id = p_room_id and pl.uid = v_target and pl.alive = true;
      if found then
        v_deaths := array[v_target];
      end if;
    end if;
  end if;

  -- 의사·경호원의 직전 대상 기록 (§6.3)
  update public.players pl
     set last_target_id = n.target_uid
    from public.night_actions n
   where n.room_id = pl.room_id
     and n.actor_uid = pl.uid
     and n.room_id = p_room_id
     and n.day_number = v_day
     and n.action in ('DOCTOR', 'BODYGUARD');

  -- 6. 경찰 조사 결과 (§2.3)
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

  -- 7. 탐정 결과 (바뀐 §2.6)
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

  -- 8. 영매 결과 (§2.8) — 사망자의 정확한 직업
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

  -- 9. 기자 취재 결과 (바뀐 §2.7) — 성공률 50%
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
                               'team', case when v_ok then v_rec.target_team else null end))
    on conflict (room_id, uid, day_number, kind) do update set payload = excluded.payload;

    if v_ok then
      v_reveal := v_reveal || jsonb_build_object(
        'targetUid', v_rec.target_uid,
        'targetNickname', v_rec.target_nick,
        'team', v_rec.target_team);
    end if;
  end loop;

  -- 공개 결과 — 사망자 목록과 취재 성공분만
  insert into public.public_results (room_id, day_number, kind, payload)
  values (p_room_id, v_day, 'NIGHT',
          jsonb_build_object('nightDeaths', to_jsonb(v_deaths),
                             'reporterReveal', v_reveal))
  on conflict (room_id, day_number, kind) do update set payload = excluded.payload;

  -- 의사 본인에게만 치료 성공을 알린다
  if v_saved then
    insert into public.private_results (room_id, uid, day_number, kind, payload)
    select p_room_id, n.actor_uid, v_day, 'DOCTOR',
           jsonb_build_object('savedUid', v_target, 'savedNickname', tp.nickname)
      from public.night_actions n
      join public.players tp on tp.room_id = n.room_id and tp.uid = n.target_uid
     where n.room_id = p_room_id and n.day_number = v_day
       and n.action = 'DOCTOR' and n.target_uid = v_target
    on conflict (room_id, uid, day_number, kind) do update set payload = excluded.payload;
  end if;

  -- 경호원 본인에게만 결과를 알린다
  if v_target is not null and (v_shielded or (v_saved and array_length(v_guards, 1) > 0)) then
    insert into public.private_results (room_id, uid, day_number, kind, payload)
    select p_room_id, g, v_day, 'BODYGUARD',
           jsonb_build_object('protectedUid', v_target,
                              'protectedNickname', tp.nickname,
                              'sacrificed', v_shielded)
      from unnest(v_guards) g
      join public.players tp on tp.room_id = p_room_id and tp.uid = v_target
    on conflict (room_id, uid, day_number, kind) do update set payload = excluded.payload;
  end if;

  -- 10. 승리 조건 확인
  v_winner := public.check_winner(p_room_id);
  if v_winner is not null then
    perform public.end_game(p_room_id, v_winner);
    return;
  end if;

  -- 11. 낮으로 이동
  perform public.enter_phase(p_room_id, 'DAY', v_day);
end;
$$;

revoke all on function public.resolve_night(uuid) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 3. 밤 행동 제출 — 영매는 사망자를 지목한다
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
  v_target_dead boolean;
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

  v_needed := case p_action
    when 'MAFIA_VOTE' then 'MAFIA'
    when 'POLICE'     then 'POLICE'
    when 'DOCTOR'     then 'DOCTOR'
    when 'BODYGUARD'  then 'BODYGUARD'
    when 'DETECTIVE'  then 'DETECTIVE'
    when 'REPORTER'   then 'REPORTER'
    when 'MEDIUM'     then 'MEDIUM'
    else null
  end;

  if v_needed is null then
    raise exception '아직 구현되지 않은 능력입니다: %', p_action;
  end if;
  if v_role <> v_needed then
    raise exception '사용할 수 없는 능력입니다.';
  end if;

  -- 기자만 대상 없이 제출할 수 있다 (= 오늘은 쓰지 않는다)
  if p_target_uid is null then
    if p_action <> 'REPORTER' then
      raise exception '대상을 선택해 주세요.';
    end if;
  else
    select pl.alive into v_target_dead
      from public.players pl
     where pl.room_id = p_room_id and pl.uid = p_target_uid;

    if not found then
      raise exception '이 방의 참가자가 아닙니다.';
    end if;

    if p_action = 'MEDIUM' then
      -- 영매는 사망자만 지목할 수 있다 (§2.8)
      if v_target_dead then
        raise exception '사망한 참가자만 확인할 수 있습니다.';
      end if;
    else
      if not v_target_dead then
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

    -- 1회 제한 (§2.7, §6.3)
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
