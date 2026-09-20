-- ============================================================
-- 마피아 게임 · 암살자 (2) 밤 처리와 화면 조회
-- ============================================================
-- 암살은 공격 사망 계산이 끝난 뒤에 처리한다.
-- 의사 치료와 경호원 보호는 암살을 막지 못한다.
-- ============================================================

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
  v_hit       boolean;
begin
  select r.day_number into v_day from public.rooms r where r.id = p_room_id;

  -- 1. 마피아 공격 대상 확정 (§2.2). 스파이·암살자의 표도 함께 센다
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

  -- 5-2. 암살 처리
  --      맞히면 대상이 죽고, 틀리면 암살자가 죽는다.
  --      치료·보호로 막을 수 없다.
  for v_rec in
    select n.actor_uid, n.target_uid, n.guess_role,
           tgt.role as actual_role, tp.nickname as target_nick
      from public.night_actions n
      join public.private_roles pr  on pr.room_id = n.room_id and pr.uid = n.actor_uid
      join public.private_roles tgt on tgt.room_id = n.room_id and tgt.uid = n.target_uid
      join public.players tp        on tp.room_id = n.room_id and tp.uid = n.target_uid
     where n.room_id = p_room_id and n.day_number = v_day
       and n.action = 'ASSASSIN' and pr.role = 'ASSASSIN'
       and n.target_uid is not null and n.guess_role is not null
  loop
    v_hit := (v_rec.guess_role = v_rec.actual_role);

    if v_hit then
      update public.players pl
         set alive = false
       where pl.room_id = p_room_id and pl.uid = v_rec.target_uid and pl.alive = true;
      if found then
        v_deaths := v_deaths || v_rec.target_uid;
      end if;
    else
      update public.players pl
         set alive = false
       where pl.room_id = p_room_id and pl.uid = v_rec.actor_uid and pl.alive = true;
      if found then
        v_deaths := v_deaths || v_rec.actor_uid;
      end if;
    end if;

    -- 암살자 본인에게만 결과를 알린다. 틀렸으면 실제 직업도 알려준다.
    insert into public.private_results (room_id, uid, day_number, kind, payload)
    values (p_room_id, v_rec.actor_uid, v_day, 'ASSASSIN',
            jsonb_build_object('targetUid', v_rec.target_uid,
                               'targetNickname', v_rec.target_nick,
                               'guess', v_rec.guess_role,
                               'actualRole', v_rec.actual_role,
                               'success', v_hit))
    on conflict (room_id, uid, day_number, kind) do update set payload = excluded.payload;
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

  -- 7. 탐정 결과
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

  -- 8. 영매 결과
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

  -- 9. 기자 취재 (성공률 50%)
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

  -- 공개 결과 — 사망자 목록과 취재 성공분만.
  -- 암살이었는지 일반 공격이었는지는 알리지 않는다.
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
-- 화면 조회 — 암살자 정보 추가
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
  v_act       text;
  v_guess     text;
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

  if v_role in ('MAFIA', 'SPY', 'ASSASSIN') then
    select json_agg(json_build_object(
             'uid', pl.uid, 'nickname', pl.nickname, 'role', pr.role, 'alive', pl.alive)
             order by pl.joined_at)
      into v_mates
      from public.private_roles pr
      join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
     where pr.room_id = p_room_id and pr.team = 'MAFIA';
  end if;

  -- 내가 이 밤에 제출한 행동
  select n.target_uid, n.action, n.guess_role, true
    into v_night, v_act, v_guess, v_acted
    from public.night_actions n
   where n.room_id = p_room_id
     and n.day_number = v_room.day_number
     and n.actor_uid = v_uid
   order by n.created_at desc
   limit 1;
  v_acted := coalesce(v_acted, false);

  if v_role in ('MAFIA', 'SPY', 'ASSASSIN') then
    select count(*) into v_n_exp
      from public.private_roles pr
      join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
     where pr.room_id = p_room_id
       and pr.role in ('MAFIA', 'SPY', 'ASSASSIN')
       and pl.alive = true;

    select count(*) into v_n_sub
      from public.night_actions n
     where n.room_id = p_room_id and n.day_number = v_room.day_number
       and n.action in ('MAFIA_VOTE', 'ASSASSIN');
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
    'role',            v_role,
    'team',            v_team,
    'alive',           v_alive,
    'abilityUsed',     coalesce(v_used, false),
    'lastTargetId',    v_last,
    'nightActed',      v_acted,
    'nightActionKind', v_act,
    'nightGuess',      v_guess,
    'canAssassinate',  case when v_role = 'ASSASSIN'
                         then public.can_assassinate(p_room_id) else null end,
    'mafiaMembers',    v_mates,
    'nightSubmitted',  v_night,
    'daySubmitted',    v_day,
    'nightProgress',   case when v_role in ('MAFIA', 'SPY', 'ASSASSIN')
                         then json_build_object('submitted', v_n_sub, 'expected', v_n_exp)
                         else null end,
    'dayProgress',     json_build_object('submitted', v_d_sub, 'expected', v_d_exp),
    'privateResults',  v_results
  );
end;
$$;

grant execute on function public.my_game_view(uuid) to anon, authenticated;
