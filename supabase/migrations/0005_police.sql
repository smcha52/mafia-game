-- ============================================================
-- 마피아 게임 · §8.2-2  경찰
-- ============================================================
-- §2.3
--   · 밤마다 살아 있는 사람 한 명을 조사한다
--   · 결과는 시민 진영 / 마피아 진영 / 중립 진영 중 하나
--   · 스파이는 마피아 진영, 광대는 중립 진영으로 보인다
--   · 결과는 경찰 본인에게만 보인다
--
-- 스파이·광대 처리는 private_roles.team 이 이미 그렇게 저장되어 있으므로
-- 별도 분기 없이 team 을 그대로 돌려주면 규칙이 지켜진다.
--
-- 밤 종료 조건을 "마피아 전원 제출" 에서 "밤에 행동하는 직업 전원 제출"
-- 로 바꾼다. 그렇지 않으면 경찰이 조사하기 전에 밤이 끝난다.
-- ============================================================

-- ------------------------------------------------------------
-- 1. 비밀 결과 저장소 (§7.2) — 권한을 주지 않는다
-- ------------------------------------------------------------

create table if not exists public.private_results (
  room_id    uuid not null references public.rooms(id) on delete cascade,
  uid        uuid not null,
  day_number int  not null,
  kind       text not null check (kind in ('POLICE', 'DETECTIVE', 'MEDIUM', 'SPY')),
  payload    jsonb not null,
  created_at timestamptz not null default now(),
  primary key (room_id, uid, day_number, kind)
);

alter table public.private_results enable row level security;

-- 정책도 권한도 없다. RPC 로만 읽힌다.
revoke all on public.private_results from anon, authenticated;

-- ------------------------------------------------------------
-- 2. 밤에 행동해야 하는 인원
-- ------------------------------------------------------------
-- 직업을 추가할 때마다 이 목록에 넣는다. (§8.2 순서)

create or replace function public.night_actor_roles()
returns text[]
language sql
immutable
as $$
  select array['MAFIA', 'POLICE'];
$$;

create or replace function public.night_is_complete(p_room_id uuid, p_day int)
returns boolean
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_expected  int;
  v_submitted int;
begin
  select count(*) into v_expected
    from public.private_roles pr
    join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
   where pr.room_id = p_room_id
     and pl.alive = true
     and pr.role = any (public.night_actor_roles());

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
-- 3. 밤 처리에 경찰 조사를 끼워 넣는다 (§3 순서 6번)
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
  v_deaths  uuid[] := '{}';
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

  -- 6. 경찰 조사 결과 전달 (§2.3)
  --    조사한 밤에 경찰이 죽어도 결과는 전달한다.
  --    이미 조사는 이루어졌고, 죽은 뒤에는 어차피 발언권이 없다.
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
-- 4. 밤 행동 제출 — 경찰을 받는다
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

  select pl.alive into v_alive
    from public.players pl
   where pl.room_id = p_room_id and pl.uid = v_uid;
  if not v_alive then
    raise exception '사망한 참가자는 능력을 사용할 수 없습니다.';
  end if;

  -- 이 행동을 쓸 수 있는 직업
  v_needed := case p_action
    when 'MAFIA_VOTE' then 'MAFIA'
    when 'POLICE'     then 'POLICE'
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

  insert into public.night_actions (room_id, day_number, actor_uid, action, target_uid)
  values (p_room_id, v_room.day_number, v_uid, p_action, p_target_uid)
  on conflict (room_id, day_number, actor_uid, action)
    do update set target_uid = excluded.target_uid, created_at = now();

  -- 밤에 행동하는 직업이 모두 제출했으면 밤을 처리한다
  if public.night_is_complete(p_room_id, v_room.day_number) then
    perform public.resolve_night(p_room_id);
    return json_build_object('resolved', true);
  end if;

  return json_build_object('resolved', false);
end;
$$;

grant execute on function public.submit_night_action(uuid, text, uuid) to anon, authenticated;

-- ------------------------------------------------------------
-- 5. 화면 조회에 비밀 결과를 붙인다
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

  select pl.alive into v_alive
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

  -- 마피아 동료들의 제출 진행 상황. 다른 직업에는 주지 않는다
  -- (밤에 행동하는 인원수를 알려주면 특수직업 수가 드러난다)
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

  -- 내 비밀 결과만 (§6.1)
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
