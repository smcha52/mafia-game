-- ============================================================
-- 마피아 게임 · 암살자 변경: 제거와 저격 동시 가능 / 밤낮 모두 저격
-- ============================================================
-- 바뀐 점
--   1) 밤에 일반 공격 투표와 저격을 "둘 다" 할 수 있다 (이전: 택일)
--   2) 저격을 밤과 낮 모두 할 수 있다 (이전: 밤만)
--   3) 페이즈마다 1회 — 밤1, 낮1, 밤2, 낮2 ... 각각 한 번
--
-- 처리 시점
--   밤 저격  밤 처리 때 다른 능력과 함께 (밤은 동시 진행이다)
--   낮 저격  즉시 (낮은 동시 진행이 아니라 몇 분 뒤 결과가 나오면 어색하다)
--
-- 밤 종료 조건에는 영향이 없다. 암살자의 밤 의무는 공격 투표이고
-- 저격은 선택적 추가 행동이다.
--
-- 의사 치료와 경호원 보호는 여전히 저격을 막지 못한다.
-- ============================================================

-- ------------------------------------------------------------
-- 1. 저격 기록 — 페이즈 단위로 남긴다
-- ------------------------------------------------------------
-- night_actions 는 (room, day, actor, action) 이 키라서 같은 날의
-- 밤과 낮을 구분하지 못한다. 별도 표를 둔다.

create table if not exists public.assassinations (
  room_id     uuid not null references public.rooms(id) on delete cascade,
  day_number  int  not null,
  phase       text not null check (phase in ('NIGHT', 'DAY')),
  actor_uid   uuid not null,
  target_uid  uuid not null,
  guess_role  text not null,
  resolved    boolean not null default false,
  success     boolean,
  actual_role text,
  created_at  timestamptz not null default now(),
  primary key (room_id, day_number, phase, actor_uid)
);

alter table public.assassinations enable row level security;
revoke all on public.assassinations from anon, authenticated;

-- ------------------------------------------------------------
-- 2. 저격 한 건을 처리한다
-- ------------------------------------------------------------
-- 맞히면 대상이 죽고 틀리면 암살자가 죽는다. 죽은 uid 를 돌려준다.

create or replace function public.apply_assassination(
  p_room_id uuid, p_day int, p_phase text, p_actor uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rec    record;
  v_hit    boolean;
  v_dead   uuid := null;
begin
  select a.target_uid, a.guess_role, tgt.role as actual_role, tp.nickname as target_nick
    into v_rec
    from public.assassinations a
    join public.private_roles tgt on tgt.room_id = a.room_id and tgt.uid = a.target_uid
    join public.players tp        on tp.room_id = a.room_id and tp.uid = a.target_uid
   where a.room_id = p_room_id and a.day_number = p_day
     and a.phase = p_phase and a.actor_uid = p_actor
     and a.resolved = false;

  if not found then
    return null;
  end if;

  v_hit := (v_rec.guess_role = v_rec.actual_role);

  if v_hit then
    update public.players pl
       set alive = false
     where pl.room_id = p_room_id and pl.uid = v_rec.target_uid and pl.alive = true;
    if found then
      v_dead := v_rec.target_uid;
    end if;
  else
    update public.players pl
       set alive = false
     where pl.room_id = p_room_id and pl.uid = p_actor and pl.alive = true;
    if found then
      v_dead := p_actor;
    end if;
  end if;

  update public.assassinations a
     set resolved = true, success = v_hit, actual_role = v_rec.actual_role
   where a.room_id = p_room_id and a.day_number = p_day
     and a.phase = p_phase and a.actor_uid = p_actor;

  -- 암살자 본인에게만 결과를 알린다
  insert into public.private_results (room_id, uid, day_number, kind, payload)
  values (p_room_id, p_actor, p_day, 'ASSASSIN',
          jsonb_build_object('phase', p_phase,
                             'targetUid', v_rec.target_uid,
                             'targetNickname', v_rec.target_nick,
                             'guess', v_rec.guess_role,
                             'actualRole', v_rec.actual_role,
                             'success', v_hit))
  on conflict (room_id, uid, day_number, kind) do update set payload = excluded.payload;

  return v_dead;
end;
$$;

revoke all on function public.apply_assassination(uuid, int, text, uuid)
  from public, anon, authenticated;

-- ------------------------------------------------------------
-- 3. 저격 제출 — 밤이든 낮이든
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
-- 4. 낮 처리 — 기존 공개 결과에 덧붙인다
-- ------------------------------------------------------------
-- 낮 저격 사망자를 지우지 않도록 payload 를 합친다.

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
  v_executed uuid := null;
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
  values (p_room_id, v_day, 'DAY', jsonb_build_object('executed', v_executed))
  on conflict (room_id, day_number, kind) do update
    set payload = public.public_results.payload || excluded.payload;

  v_winner := public.check_winner(p_room_id, v_executed);
  if v_winner is not null then
    perform public.end_game(p_room_id, v_winner);
    return;
  end if;

  if v_day >= v_max then
    perform public.end_game(p_room_id, 'DRAW');
    return;
  end if;

  perform public.enter_phase(p_room_id, 'NIGHT', v_day + 1);
end;
$$;

revoke all on function public.resolve_day(uuid) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 5. 일반 공격과 저격을 함께 할 수 있게 한다
-- ------------------------------------------------------------
-- 이전 버전은 한쪽을 제출하면 다른 쪽을 지웠다. 그 삭제를 없앤다.

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
-- 6. 다시하기 시 저격 기록도 지운다
-- ------------------------------------------------------------

create or replace function public.restart_game(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room public.rooms%rowtype;
begin
  select * into v_room from public.rooms r where r.id = p_room_id for update;
  if not found then
    raise exception '존재하지 않는 방입니다.';
  end if;
  if v_room.host_uid <> auth.uid() then
    raise exception '방장만 다시 시작할 수 있습니다.';
  end if;
  if v_room.phase <> 'ENDED' then
    raise exception '게임이 끝난 뒤에만 다시 시작할 수 있습니다.';
  end if;

  delete from public.private_results where room_id = p_room_id;
  delete from public.public_results  where room_id = p_room_id;
  delete from public.night_actions   where room_id = p_room_id;
  delete from public.assassinations  where room_id = p_room_id;
  delete from public.day_votes       where room_id = p_room_id;
  delete from public.private_roles   where room_id = p_room_id;
  delete from public.chat_messages   where room_id = p_room_id;

  update public.players pl
     set alive          = true,
         ability_used   = false,
         last_target_id = null,
         team           = null,
         is_ready       = pl.is_host
   where pl.room_id = p_room_id;

  update public.rooms r
     set phase          = 'LOBBY',
         day_number     = 0,
         winner         = null,
         jester_uid     = null,
         started_at     = null,
         phase_deadline = null
   where r.id = p_room_id;
end;
$$;

grant execute on function public.restart_game(uuid) to anon, authenticated;
