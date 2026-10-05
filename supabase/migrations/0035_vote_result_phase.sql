-- ============================================================
-- 마피아 게임 · 투표 결과 시간 (DAY_RESULT)
-- ============================================================
-- 낮 투표가 끝나면 바로 밤으로 넘어가지 않고 10초 동안 결과를 보여준다.
--
--   DAY  ──투표 마감──▶  DAY_RESULT (10초 고정)  ──▶  NIGHT
--
-- 결과 시간에 공개하는 것
--   · 사람별 득표 수 (votes)
--   · 처형된 사람과 그 사람의 득표 수 (executedVotes)
--   · 처형된 사람의 진영. 중립이면 진영 대신 직업을 그대로 (0023 과 같다)
--
-- 결과 시간은 방장이 조절할 수 없다. 투표·능력은 쓸 수 없고,
-- 살아 있는 사람은 낮처럼 대화할 수 있다.
--
-- 투표로 게임이 끝나면(승리·무승부·생존자) 결과 시간 없이 바로 종료한다.
-- ============================================================

-- ------------------------------------------------------------
-- 1. 페이즈 값
-- ------------------------------------------------------------

alter table public.rooms drop constraint if exists rooms_phase_check;
alter table public.rooms add constraint rooms_phase_check
  check (phase in ('LOBBY', 'NIGHT', 'DAY', 'DAY_RESULT', 'ENDED'));

-- ------------------------------------------------------------
-- 2. 페이즈 전환 — 결과 시간은 10초 고정
-- ------------------------------------------------------------

create or replace function public.enter_phase(p_room_id uuid, p_phase text, p_day int)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_secs int;
begin
  select case p_phase
           when 'NIGHT'      then r.night_seconds
           when 'DAY_RESULT' then 10
           else r.day_seconds
         end
    into v_secs
    from public.rooms r where r.id = p_room_id;

  update public.rooms r
     set phase = p_phase,
         day_number = p_day,
         phase_deadline = now() + make_interval(secs => v_secs)
   where r.id = p_room_id;
end;
$$;

revoke all on function public.enter_phase(uuid, text, int) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 3. 낮 처리 — 0034 본문에 득표 수를 더하고, 밤 대신 결과 시간으로 간다
-- ------------------------------------------------------------

create or replace function public.resolve_day(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day      int;
  v_max      int;
  v_target   uuid;
  v_ties     int;
  v_top      int;
  v_votes    jsonb;
  v_executed uuid := null;
  v_team     text := null;
  v_role     text := null;
  v_winner   text;
begin
  select r.day_number, r.max_days into v_day, v_max
    from public.rooms r where r.id = p_room_id;

  with tally as (
    select d.target_uid as t_uid, count(*) as c
      from public.day_votes d
     where d.room_id = p_room_id and d.day_number = v_day
     group by d.target_uid
  ), mx as (
    select max(c) as m from tally
  )
  select count(*), (array_agg(tally.t_uid))[1], max(mx.m)
    into v_ties, v_target, v_top
    from tally join mx on tally.c = mx.m;

  -- 사람별 득표 수 (많은 순)
  select coalesce(jsonb_agg(jsonb_build_object('uid', t.t_uid, 'count', t.c)
                            order by t.c desc), '[]'::jsonb)
    into v_votes
    from (
      select d.target_uid as t_uid, count(*) as c
        from public.day_votes d
       where d.room_id = p_room_id and d.day_number = v_day
       group by d.target_uid
    ) t;

  if coalesce(v_ties, 0) = 1 and v_target is not null then
    update public.players pl
       set alive = false
     where pl.room_id = p_room_id and pl.uid = v_target and pl.alive = true;
    if found then
      v_executed := v_target;
    end if;
  end if;

  if v_executed is not null then
    select pr.team, pr.role into v_team, v_role
      from public.private_roles pr
     where pr.room_id = p_room_id and pr.uid = v_executed;
  end if;

  insert into public.public_results (room_id, day_number, kind, payload)
  values (p_room_id, v_day, 'DAY', jsonb_build_object(
    'executed',      v_executed,
    'executedVotes', case when v_executed is not null then v_top else null end,
    'votes',         v_votes,
    'tie',           coalesce(v_ties, 0) > 1,
    'executedTeam',  case when v_team = 'NEUTRAL' then null else v_team end,
    'executedRole',  case when v_team = 'NEUTRAL' then v_role else null end))
  on conflict (room_id, day_number, kind) do update
    set payload = public.public_results.payload || excluded.payload;

  v_winner := public.check_winner(p_room_id, v_executed);
  if v_winner is not null then
    perform public.end_game(p_room_id, v_winner);
    return;
  end if;

  -- 생존자: 목표 날의 낮이 끝날 때 살아 있으면 단독 승리 (§4.1-3)
  if v_day >= coalesce(public.survivor_target(v_max), v_max + 1) and exists (
    select 1
      from public.private_roles pr
      join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
     where pr.room_id = p_room_id and pr.role = 'SURVIVOR' and pl.alive = true
  ) then
    perform public.end_game(p_room_id, 'SURVIVOR');
    return;
  end if;

  if v_day >= v_max then
    perform public.end_game(p_room_id, 'DRAW');
    return;
  end if;

  -- 밤은 결과 시간이 끝난 뒤 tick_phase 가 연다
  perform public.enter_phase(p_room_id, 'DAY_RESULT', v_day);
end;
$$;
revoke all on function public.resolve_day(uuid) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 4. 만료 확인 — 결과 시간이 끝나면 다음 날 밤으로
-- ------------------------------------------------------------

create or replace function public.tick_phase(p_room_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room public.rooms%rowtype;
begin
  if not public.is_room_member(p_room_id) then
    raise exception '이 방의 참가자가 아닙니다.';
  end if;

  -- 동시에 여러 명이 불러도 한 번만 처리되도록 방을 잠근다
  select * into v_room from public.rooms r where r.id = p_room_id for update;
  if not found then
    raise exception '존재하지 않는 방입니다.';
  end if;

  if v_room.phase not in ('NIGHT', 'DAY', 'DAY_RESULT') then
    return json_build_object('resolved', false, 'remaining', null);
  end if;

  if v_room.phase_deadline is null then
    return json_build_object('resolved', false, 'remaining', null);
  end if;

  if now() < v_room.phase_deadline then
    return json_build_object(
      'resolved', false,
      'remaining', ceil(extract(epoch from (v_room.phase_deadline - now())))::int);
  end if;

  if v_room.phase = 'NIGHT' then
    perform public.resolve_night(p_room_id);
  elsif v_room.phase = 'DAY' then
    perform public.resolve_day(p_room_id);
  else
    perform public.enter_phase(p_room_id, 'NIGHT', v_room.day_number + 1);
  end if;

  return json_build_object('resolved', true, 'remaining', 0);
end;
$$;

grant execute on function public.tick_phase(uuid) to anon, authenticated;

-- ------------------------------------------------------------
-- 5. 채팅 — 결과 시간에도 낮처럼 생존자가 대화한다 (0013 본문)
-- ------------------------------------------------------------

create or replace function public.send_chat(p_room_id uuid, p_body text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_room    public.rooms%rowtype;
  v_nick    text;
  v_alive   boolean;
  v_team    text;
  v_channel text;
  v_body    text := btrim(coalesce(p_body, ''));
begin
  if char_length(v_body) = 0 then
    raise exception '내용을 입력해 주세요.';
  end if;
  if char_length(v_body) > 300 then
    raise exception '300자까지 보낼 수 있습니다.';
  end if;

  select * into v_room from public.rooms r where r.id = p_room_id;
  if not found then
    raise exception '존재하지 않는 방입니다.';
  end if;

  select pl.nickname, pl.alive into v_nick, v_alive
    from public.players pl
   where pl.room_id = p_room_id and pl.uid = v_uid;
  if not found then
    raise exception '이 방의 참가자가 아닙니다.';
  end if;

  if v_room.phase = 'LOBBY' then
    v_channel := 'PUBLIC';

  elsif v_room.phase = 'ENDED' then
    -- 게임이 끝났으면 사망자도 이야기할 수 있다
    v_channel := 'PUBLIC';

  elsif v_room.phase in ('DAY', 'DAY_RESULT') then
    if not v_alive then
      raise exception '사망한 참가자는 낮에 대화할 수 없습니다.';
    end if;
    v_channel := 'PUBLIC';

  elsif v_room.phase = 'NIGHT' then
    select pr.team into v_team
      from public.private_roles pr
     where pr.room_id = p_room_id and pr.uid = v_uid;

    if coalesce(v_team, '') <> 'MAFIA' then
      raise exception '밤에는 마피아 진영만 대화할 수 있습니다.';
    end if;
    if not v_alive then
      raise exception '사망한 참가자는 대화할 수 없습니다.';
    end if;
    v_channel := 'MAFIA';

  else
    raise exception '지금은 대화할 수 없습니다.';
  end if;

  insert into public.chat_messages
    (room_id, channel, sender_uid, sender_nickname, body, day_number, phase)
  values
    (p_room_id, v_channel, v_uid, v_nick, v_body, v_room.day_number, v_room.phase);

  return json_build_object('channel', v_channel);
end;
$$;

grant execute on function public.send_chat(uuid, text) to anon, authenticated;
