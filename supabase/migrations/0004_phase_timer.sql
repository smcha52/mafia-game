-- ============================================================
-- 마피아 게임 · 페이즈 제한시간
-- ============================================================
-- 전원이 제출해야만 페이즈가 끝나면, 한 명이 자리를 비울 때 게임이
-- 영원히 멈춘다. 마감 시각을 서버에 두고 시간이 지나면 넘긴다.
--
-- Supabase 에는 기본 스케줄러가 없으므로 클라이언트가 만료를 감지해
-- tick_phase 를 호출한다. 여러 명이 동시에 불러도 방을 잠그고
-- 페이즈를 다시 확인하므로 한 번만 처리된다.
--
-- 시간이 지나도 미제출자는 기권으로 본다.
--   · 밤에 마피아가 아무도 내지 않았으면 공격 없음
--   · 낮에 표가 없으면 처형 없음 (동점 규칙과 같다)
-- ============================================================

alter table public.rooms
  add column if not exists phase_deadline timestamptz;

alter table public.rooms
  add column if not exists night_seconds int not null default 90
  check (night_seconds between 10 and 600);

alter table public.rooms
  add column if not exists day_seconds int not null default 180
  check (day_seconds between 10 and 600);

-- ------------------------------------------------------------
-- 페이즈 전환을 한 곳으로 모은다
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
  select case when p_phase = 'NIGHT' then r.night_seconds else r.day_seconds end
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
-- 기존 전환 지점을 enter_phase 로 교체
-- ------------------------------------------------------------

create or replace function public.end_game(p_room_id uuid, p_winner text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.players pl
     set team = pr.team
    from public.private_roles pr
   where pr.room_id = pl.room_id
     and pr.uid = pl.uid
     and pl.room_id = p_room_id;

  update public.rooms r
     set phase = 'ENDED', winner = p_winner, phase_deadline = null
   where r.id = p_room_id;
end;
$$;

revoke all on function public.end_game(uuid, text) from public, anon, authenticated;

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
  v_deaths  uuid[] := '{}';
  v_winner  text;
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
    v_target := null;          -- 동점이거나 표가 없으면 공격하지 않는다
  end if;

  -- 4. 공격 대상 사망 처리
  if v_target is not null then
    update public.players pl
       set alive = false
     where pl.room_id = p_room_id and pl.uid = v_target and pl.alive = true;
    if found then
      v_deaths := array[v_target];
    end if;
  end if;

  insert into public.public_results (room_id, day_number, kind, payload)
  values (p_room_id, v_day, 'NIGHT',
          jsonb_build_object('nightDeaths', to_jsonb(v_deaths)))
  on conflict (room_id, day_number, kind) do update set payload = excluded.payload;

  v_winner := public.check_winner(p_room_id);
  if v_winner is not null then
    perform public.end_game(p_room_id, v_winner);
    return;
  end if;

  perform public.enter_phase(p_room_id, 'DAY', v_day);
end;
$$;

revoke all on function public.resolve_night(uuid) from public, anon, authenticated;

create or replace function public.resolve_day(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day      int;
  v_target   uuid;
  v_ties     int;
  v_executed uuid := null;
  v_winner   text;
begin
  select r.day_number into v_day from public.rooms r where r.id = p_room_id;

  with tally as (
    select d.target_uid as t_uid, count(*) as c
      from public.day_votes d
     where d.room_id = p_room_id and d.day_number = v_day
     group by d.target_uid
  ), mx as (
    select max(c) as m from tally
  )
  select count(*), (array_agg(tally.t_uid))[1]
    into v_ties, v_target
    from tally join mx on tally.c = mx.m;

  if coalesce(v_ties, 0) = 1 and v_target is not null then
    update public.players pl
       set alive = false
     where pl.room_id = p_room_id and pl.uid = v_target and pl.alive = true;
    if found then
      v_executed := v_target;
    end if;
  end if;

  insert into public.public_results (room_id, day_number, kind, payload)
  values (p_room_id, v_day, 'DAY',
          jsonb_build_object('executed', v_executed))
  on conflict (room_id, day_number, kind) do update set payload = excluded.payload;

  -- 광대 승리를 먼저 검사한다 (§4.1)
  v_winner := public.check_winner(p_room_id, v_executed);
  if v_winner is not null then
    perform public.end_game(p_room_id, v_winner);
    return;
  end if;

  perform public.enter_phase(p_room_id, 'NIGHT', v_day + 1);
end;
$$;

revoke all on function public.resolve_day(uuid) from public, anon, authenticated;

-- start_game 도 마감 시각을 세팅한다
create or replace function public.start_game(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_room      public.rooms%rowtype;
  v_total     int;
  v_not_ready int;
begin
  select * into v_room from public.rooms r where r.id = p_room_id for update;
  if not found then
    raise exception '존재하지 않는 방입니다.';
  end if;
  if v_room.host_uid <> v_uid then
    raise exception '방장만 게임을 시작할 수 있습니다.';
  end if;
  if v_room.phase <> 'LOBBY' then
    raise exception '이미 시작된 게임입니다.';
  end if;

  select count(*) into v_total from public.players pl where pl.room_id = p_room_id;

  if v_total < 5 then
    raise exception '최소 5명이 필요합니다. (현재 %명)', v_total;
  end if;
  if v_total > 15 then
    raise exception '최대 15명까지 가능합니다. (현재 %명)', v_total;
  end if;

  select count(*) into v_not_ready
    from public.players pl
   where pl.room_id = p_room_id and pl.is_ready = false;

  if v_not_ready > 0 then
    raise exception '아직 준비하지 않은 참가자가 %명 있습니다.', v_not_ready;
  end if;

  update public.rooms r set started_at = now() where r.id = p_room_id;

  perform public.assign_roles(p_room_id);
  perform public.enter_phase(p_room_id, 'NIGHT', 1);
end;
$$;

-- ------------------------------------------------------------
-- 만료 확인 — 클라이언트가 호출한다
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

  if v_room.phase not in ('NIGHT', 'DAY') then
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
  else
    perform public.resolve_day(p_room_id);
  end if;

  return json_build_object('resolved', true, 'remaining', 0);
end;
$$;

grant execute on function public.tick_phase(uuid) to anon, authenticated;

-- ------------------------------------------------------------
-- 방장이 제한시간을 조절한다 (대기실에서만)
-- ------------------------------------------------------------

create or replace function public.set_timers(p_room_id uuid, p_night int, p_day int)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room public.rooms%rowtype;
begin
  select * into v_room from public.rooms r where r.id = p_room_id;
  if not found then
    raise exception '존재하지 않는 방입니다.';
  end if;
  if v_room.host_uid <> auth.uid() then
    raise exception '방장만 제한시간을 바꿀 수 있습니다.';
  end if;
  if v_room.phase <> 'LOBBY' then
    raise exception '대기실에서만 바꿀 수 있습니다.';
  end if;

  update public.rooms r
     set night_seconds = p_night, day_seconds = p_day
   where r.id = p_room_id;
end;
$$;

grant execute on function public.set_timers(uuid, int, int) to anon, authenticated;
