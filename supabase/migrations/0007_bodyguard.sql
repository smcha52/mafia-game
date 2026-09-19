-- ============================================================
-- 마피아 게임 · §8.2-4  경호원
-- ============================================================
-- §2.5
--   · 밤마다 자신을 제외한 살아 있는 사람 한 명을 보호한다
--   · 보호 대상이 공격받으면 대상은 살아남고 경호원이 대신 사망한다
--   · 같은 사람을 연속된 밤에 보호할 수 없다
--   · 이미 죽은 사람은 보호할 수 없다
--
-- §3.1 의사·경호원 중복
--   같은 공격 대상에 치료와 보호가 동시에 걸리면
--   의사의 치료를 먼저 적용하고 경호원은 사망하지 않는다.
--
-- §3.2 조합표 (이 구현이 만족해야 하는 네 경우)
--   공격 A / 치료 -  / 보호 -   -> A 사망
--   공격 A / 치료 A / 보호 -    -> A 생존
--   공격 A / 치료 -  / 보호 A   -> A 생존, 경호원 사망
--   공격 A / 치료 A / 보호 A    -> A 생존, 경호원 생존
-- ============================================================

-- ------------------------------------------------------------
-- 1. 밤에 행동하는 직업에 경호원 추가
-- ------------------------------------------------------------

create or replace function public.night_actor_roles()
returns text[]
language sql
immutable
as $$
  select array['MAFIA', 'POLICE', 'DOCTOR', 'BODYGUARD'];
$$;

alter table public.private_results drop constraint if exists private_results_kind_check;
alter table public.private_results add constraint private_results_kind_check
  check (kind in ('POLICE', 'DOCTOR', 'BODYGUARD', 'DETECTIVE', 'MEDIUM', 'SPY'));

-- ------------------------------------------------------------
-- 2. 밤 처리 (§3 순서 1~6)
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
  v_guards    uuid[] := '{}';   -- 공격 대상을 보호한 경호원들
  v_deaths    uuid[] := '{}';
  v_saved     boolean := false; -- 의사 치료로 살았다
  v_shielded  boolean := false; -- 경호원이 대신 죽어 살았다
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
      -- 치료가 있으면 대상도 경호원도 죽지 않는다
      v_saved := true;
    elsif array_length(v_guards, 1) > 0 then
      -- 경호원이 대신 죽는다
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

  -- 의사·경호원의 직전 대상을 기록해 연속 지정을 막는다 (§6.3)
  update public.players pl
     set last_target_id = n.target_uid
    from public.night_actions n
   where n.room_id = pl.room_id
     and n.actor_uid = pl.uid
     and n.room_id = p_room_id
     and n.day_number = v_day
     and n.action in ('DOCTOR', 'BODYGUARD');

  -- 공개 결과. 사망자 목록만 알린다.
  -- 치료·보호로 막았는지는 알리지 않아야 의사·경호원 정체가 드러나지 않는다.
  insert into public.public_results (room_id, day_number, kind, payload)
  values (p_room_id, v_day, 'NIGHT',
          jsonb_build_object('nightDeaths', to_jsonb(v_deaths)))
  on conflict (room_id, day_number, kind) do update set payload = excluded.payload;

  -- 6. 경찰 조사 결과 전달 (§2.3)
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

  -- 경호원 본인에게만 결과를 알린다.
  -- 대신 죽었는지, 의사 덕에 둘 다 살았는지 구분해서 알려준다.
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
-- 3. 밤 행동 제출 — 경호원을 받는다
-- ------------------------------------------------------------

create or replace function public.submit_night_action(
  p_room_id uuid, p_action text, p_target_uid uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_room   public.rooms%rowtype;
  v_role   text;
  v_alive  boolean;
  v_last   uuid;
  v_needed text;
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

  select pl.alive, pl.last_target_id into v_alive, v_last
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
    else null
  end;

  if v_needed is null then
    raise exception '아직 구현되지 않은 능력입니다: %', p_action;
  end if;
  if v_role <> v_needed then
    raise exception '사용할 수 없는 능력입니다.';
  end if;

  -- 이미 죽은 사람은 지목할 수 없다 (§2.5)
  if not exists (
    select 1 from public.players pl
     where pl.room_id = p_room_id and pl.uid = p_target_uid and pl.alive = true
  ) then
    raise exception '살아 있는 참가자만 지목할 수 있습니다.';
  end if;

  -- 마피아와 경호원은 자신을 지목할 수 없다. 의사는 자가 치료가 허용된다.
  if p_action in ('MAFIA_VOTE', 'BODYGUARD') and p_target_uid = v_uid then
    raise exception '자신을 지목할 수 없습니다.';
  end if;

  -- 같은 사람을 연속된 밤에 지정할 수 없다 (§2.4, §2.5, §6.3)
  -- RAISE 의 메시지 자리에는 문자열 리터럴만 올 수 있어 분기로 쓴다.
  if p_action in ('DOCTOR', 'BODYGUARD')
     and v_last is not null and v_last = p_target_uid then
    if p_action = 'DOCTOR' then
      raise exception '같은 사람을 연속해서 치료할 수 없습니다.';
    else
      raise exception '같은 사람을 연속해서 보호할 수 없습니다.';
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
