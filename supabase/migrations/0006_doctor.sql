-- ============================================================
-- 마피아 게임 · §8.2-3  의사
-- ============================================================
-- §2.4
--   · 밤마다 살아 있는 사람 한 명을 치료한다
--   · 마피아의 공격 대상과 치료 대상이 같으면 공격 대상은 살아남는다
--   · 자기 자신도 치료할 수 있다
--   · 같은 사람을 연속된 밤에 치료할 수 없다
--
-- §3 처리 순서에서 의사는 2번(치료 대상 확인)이고,
-- 4번(생존·사망 계산)에서 반영된다.
--
-- 연속 치료 금지는 §6.3 대로 서버 데이터로 검증한다.
-- players.last_target_id 를 밤 처리 때 갱신하고 제출 때 대조한다.
-- 제출 시점에 갱신하면 같은 밤에 대상을 바꿀 때 꼬인다.
-- ============================================================

-- ------------------------------------------------------------
-- 1. 밤에 행동하는 직업에 의사를 추가
-- ------------------------------------------------------------

create or replace function public.night_actor_roles()
returns text[]
language sql
immutable
as $$
  select array['MAFIA', 'POLICE', 'DOCTOR'];
$$;

-- ------------------------------------------------------------
-- 2. 밤 처리에 치료를 반영 (§3 순서 2번, 4번)
-- ------------------------------------------------------------

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
  v_healed  uuid[] := '{}';
  v_deaths  uuid[] := '{}';
  v_saved   boolean := false;
  v_winner  text;
  v_rec     record;
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
    v_target := null;
  end if;

  -- 2. 의사 치료 대상 확인 (§2.4)
  select coalesce(array_agg(n.target_uid), '{}')
    into v_healed
    from public.night_actions n
    join public.private_roles pr on pr.room_id = n.room_id and pr.uid = n.actor_uid
    join public.players pl       on pl.room_id = n.room_id and pl.uid = n.actor_uid
   where n.room_id = p_room_id
     and n.day_number = v_day
     and n.action = 'DOCTOR'
     and pr.role = 'DOCTOR'
     and pl.alive = true
     and n.target_uid is not null;

  -- 4. 공격 대상 생존 또는 사망 계산
  if v_target is not null then
    if v_target = any (v_healed) then
      v_saved := true;                  -- 치료로 살아남는다
    else
      update public.players pl
         set alive = false
       where pl.room_id = p_room_id and pl.uid = v_target and pl.alive = true;
      if found then
        v_deaths := array[v_target];
      end if;
    end if;
  end if;

  -- 치료 대상을 기록해 다음 밤 연속 치료를 막는다 (§6.3)
  update public.players pl
     set last_target_id = n.target_uid
    from public.night_actions n
   where n.room_id = pl.room_id
     and n.actor_uid = pl.uid
     and n.room_id = p_room_id
     and n.day_number = v_day
     and n.action = 'DOCTOR';

  -- 공개 결과. 치료로 살았는지는 알리지 않는다.
  -- "아무도 죽지 않았습니다" 로만 보여야 의사의 정체가 드러나지 않는다.
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
     where n.room_id = p_room_id
       and n.day_number = v_day
       and n.action = 'POLICE'
       and pr.role = 'POLICE'
       and n.target_uid is not null
  loop
    insert into public.private_results (room_id, uid, day_number, kind, payload)
    values (p_room_id, v_rec.actor_uid, v_day, 'POLICE',
            jsonb_build_object(
              'targetUid', v_rec.target_uid,
              'targetNickname', v_rec.target_nick,
              'team', v_rec.target_team))
    on conflict (room_id, uid, day_number, kind) do update set payload = excluded.payload;
  end loop;

  -- 의사 본인에게는 치료 성공 여부를 알려준다.
  -- 공개 결과만으로는 자신이 막은 것인지 애초에 공격이 없었던 것인지 알 수 없다.
  if v_saved then
    insert into public.private_results (room_id, uid, day_number, kind, payload)
    select p_room_id, n.actor_uid, v_day, 'DOCTOR',
           jsonb_build_object('savedUid', v_target, 'savedNickname', tp.nickname)
      from public.night_actions n
      join public.players tp on tp.room_id = n.room_id and tp.uid = n.target_uid
     where n.room_id = p_room_id
       and n.day_number = v_day
       and n.action = 'DOCTOR'
       and n.target_uid = v_target
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

-- private_results 에 DOCTOR 종류를 허용
alter table public.private_results drop constraint if exists private_results_kind_check;
alter table public.private_results add constraint private_results_kind_check
  check (kind in ('POLICE', 'DOCTOR', 'DETECTIVE', 'MEDIUM', 'SPY'));

-- ------------------------------------------------------------
-- 3. 밤 행동 제출 — 의사를 받고 연속 치료를 막는다
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
  v_last      uuid;
  v_needed    text;
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
    else null
  end;

  if v_needed is null then
    raise exception '아직 구현되지 않은 능력입니다: %', p_action;
  end if;
  if v_role <> v_needed then
    raise exception '사용할 수 없는 능력입니다.';
  end if;

  -- 대상은 살아 있어야 한다
  if not exists (
    select 1 from public.players pl
     where pl.room_id = p_room_id and pl.uid = p_target_uid and pl.alive = true
  ) then
    raise exception '살아 있는 참가자만 지목할 수 있습니다.';
  end if;

  -- 마피아는 자기 자신을 공격할 수 없다. 의사는 자신을 치료할 수 있다 (§2.4)
  if p_action = 'MAFIA_VOTE' and p_target_uid = v_uid then
    raise exception '자신을 지목할 수 없습니다.';
  end if;

  -- 같은 사람을 연속된 밤에 치료할 수 없다 (§2.4, §6.3)
  if p_action = 'DOCTOR' and v_last is not null and v_last = p_target_uid then
    raise exception '같은 사람을 연속해서 치료할 수 없습니다.';
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
-- 4. 화면 조회에 직전 대상을 붙인다 (연속 치료 금지 표시용)
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
  v_last      uuid;
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

  select pl.alive, pl.last_target_id into v_alive, v_last
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

  select n.target_uid into v_night
    from public.night_actions n
   where n.room_id = p_room_id
     and n.day_number = v_room.day_number
     and n.actor_uid = v_uid;

  if v_role = 'MAFIA' then
    select count(*) into v_n_exp
      from public.private_roles pr
      join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
     where pr.room_id = p_room_id and pr.role = 'MAFIA' and pl.alive = true;

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
    'lastTargetId',   v_last,
    'mafiaMembers',   v_mates,
    'nightSubmitted', v_night,
    'daySubmitted',   v_day,
    'nightProgress',  case when v_role = 'MAFIA'
                        then json_build_object('submitted', v_n_sub, 'expected', v_n_exp)
                        else null end,
    'dayProgress',    json_build_object('submitted', v_d_sub, 'expected', v_d_exp),
    'privateResults', v_results
  );
end;
$$;

grant execute on function public.my_game_view(uuid) to anon, authenticated;
