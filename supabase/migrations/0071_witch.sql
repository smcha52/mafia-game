-- ============================================================
-- 마피아 게임 · 할로윈 한정 직업 마녀 (Witch) · 이벤트 퀘스트
-- ============================================================
-- 마녀 — 중립 진영. 할로윈 기간(is_halloween, 0054)에만 나온다.
--   · 할로윈 기간에만 대기실에서 켜고 끌 수 있다. 기간이 아니면 꺼진 것으로 본다 (assign_roles).
--   · 랜덤 구성에서만 나온다. 중립 후보에 들어간다.
--   · 밤마다 한 명을 제거할 수 있다 (살인자와 같이 치료·경호에 막힌다). 오늘은 쓰지 않아도 된다.
--   · 게임이 시작되면 퀘스트 하나를 무작위로 받는다. 화면 옆에서 진행도를 볼 수 있다.
--       CITIZEN   시민 진영 제거   5~8명 2명 · 9~12명 3명 · 13~15명 5명
--       MAFIA     마피아 진영 제거 5~11명 1명 · 12~15명 2명
--       NEUTRAL   중립 제거        5~11명 1명 · 12~15명 2명 (다른 중립)
--       SURVIVE   목표 날 생존     생존자와 같다 (survivor_target, 0069)
--     이 판에 그만한 대상이 없거나 생존 목표 날이 없으면 그 퀘스트는 나오지 않는다.
--     제거는 마녀가 밤에 지목한 사람이 그 밤에 죽은 수로 센다.
--   · 퀘스트를 깨면 즉시 단독 승리, 게임 종료 (rooms.winner = 'WITCH').
--       제거 퀘스트  밤 처리에서 다른 승리보다 먼저 본다. 마녀가 살아 있어야 한다.
--       생존 퀘스트  목표 날의 낮이 끝날 때 살아 있으면 (생존자와 같은 때)
--     이긴 마녀는 private_roles.witch_won 에 남긴다 (마녀가 여럿일 수 있다).
--   · XP 를 받지 않는다 (base_xp 의 그 밖 = 0 이라 이겨도 0). 승리 코인은 받는다.
--
-- 이벤트 퀘스트 (quests.category = 'EVENT')
--   할로윈 기간에만 3일마다 하나씩 생긴다. 기준은 그해 할로윈 시작(10월 5일 0시, 한국 시간).
--   이 마이그레이션 전의 칸은 만들지 않는다. 최근 10개만 남기고, 화면에는 이번 할로윈 것만 준다.
--     PUMPKIN_BOX    호박상자 5번 열기         별 10
--     WITCH_WIN      마녀로 10번 이기기        별 15
--     HALLOWEEN_WIN  할로윈 기간에 30번 이기기  보석 2
--   호박상자를 연 기록은 box_opens 에 남긴다 (open_box).
-- ============================================================

-- ------------------------------------------------------------
-- 1. 스키마 확장
-- ------------------------------------------------------------

alter table public.private_roles drop constraint if exists private_roles_role_check;
alter table public.private_roles add constraint private_roles_role_check
  check (role in ('CITIZEN','MAFIA','POLICE','DOCTOR','BODYGUARD',
                  'DETECTIVE','REPORTER','MEDIUM','SPY','JESTER','ASSASSIN','KILLER',
                  'VIGILANTE','SHERIFF','FORGER','SURVIVOR','WITCH'));

-- 마녀 퀘스트 (마녀에게만)
alter table public.private_roles add column if not exists witch_quest text
  check (witch_quest in ('CITIZEN', 'MAFIA', 'NEUTRAL', 'SURVIVE'));
alter table public.private_roles add column if not exists witch_goal int;
alter table public.private_roles add column if not exists witch_won boolean not null default false;

alter table public.night_actions drop constraint if exists night_actions_action_check;
alter table public.night_actions add constraint night_actions_action_check
  check (action in ('MAFIA_VOTE','DOCTOR','BODYGUARD','POLICE',
                    'DETECTIVE','REPORTER','MEDIUM','ASSASSIN','KILLER','VIGILANTE',
                    'SHERIFF','FORGE','WITCH'));

alter table public.rooms drop constraint if exists rooms_winner_check;
alter table public.rooms add constraint rooms_winner_check
  check (winner is null or winner in ('CITIZEN', 'MAFIA', 'JESTER', 'KILLER',
                                      'SURVIVOR', 'WITCH', 'DRAW'));

alter table public.quests drop constraint if exists quests_category_check;
alter table public.quests add constraint quests_category_check
  check (category in ('MAIN', 'DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY', 'ROLE', 'EVENT'));

alter table public.quests drop constraint if exists quests_kind_check;
alter table public.quests add constraint quests_kind_check
  check (kind in ('WIN', 'STREAK', 'KILL', 'SURVIVE', 'PLAY', 'CLEAR',
                  'FIND_MAFIA', 'INVESTIGATE', 'HEAL', 'GUARD', 'REPORT', 'REPORT_MAFIA',
                  'SEANCE', 'DIE', 'KILL_MAFIA', 'KILL_NEUTRAL', 'IDENTIFY',
                  'FORGE', 'FORGE_HIT', 'VOTES', 'DUEL',
                  'PUMPKIN_BOX', 'WITCH_WIN', 'HALLOWEEN_WIN'));

-- 상자를 연 기록 (이벤트 퀘스트용)
create table if not exists public.box_opens (
  id        bigserial primary key,
  uid       uuid not null,
  box       text not null,
  opened_at timestamptz not null default now()
);
create index if not exists box_opens_uid_idx on public.box_opens (uid, box, opened_at);
alter table public.box_opens enable row level security;

-- ------------------------------------------------------------
-- 2. 진영과 목록
-- ------------------------------------------------------------

create or replace function public.team_of(p_role text)
returns text
language sql
immutable
as $$
  select case
    when p_role in ('MAFIA', 'SPY', 'ASSASSIN', 'FORGER')       then 'MAFIA'
    when p_role in ('JESTER', 'KILLER', 'SURVIVOR', 'WITCH')    then 'NEUTRAL'
    else 'CITIZEN'
  end;
$$;

create or replace function public.toggleable_roles()
returns text[]
language sql
immutable
as $$
  select array['MAFIA', 'POLICE', 'DOCTOR', 'BODYGUARD', 'DETECTIVE',
               'REPORTER', 'MEDIUM', 'SPY', 'JESTER', 'ASSASSIN', 'KILLER',
               'VIGILANTE', 'SHERIFF', 'FORGER', 'SURVIVOR', 'WITCH', 'CITIZEN'];
$$;

create or replace function public.special_roles()
returns text[]
language sql
immutable
as $$
  select array['POLICE', 'DOCTOR', 'BODYGUARD', 'DETECTIVE', 'REPORTER', 'MEDIUM',
               'VIGILANTE', 'SHERIFF', 'SPY', 'ASSASSIN', 'FORGER',
               'JESTER', 'KILLER', 'SURVIVOR', 'WITCH'];
$$;

create or replace function public.night_actor_roles()
returns text[]
language sql
immutable
as $$
  select array['MAFIA', 'SPY', 'ASSASSIN', 'FORGER', 'POLICE', 'DOCTOR', 'BODYGUARD',
               'DETECTIVE', 'REPORTER', 'MEDIUM', 'KILLER', 'VIGILANTE', 'SHERIFF', 'WITCH'];
$$;

-- ------------------------------------------------------------
-- 3. 할로윈 기간 도우미
-- ------------------------------------------------------------

-- 그 시각이 할로윈 기간인지 (한국 시간 10월 5일 ~ 11월 1일, is_halloween 과 같은 기간)
create or replace function public.is_halloween_at(p_ts timestamptz)
returns boolean
language sql
stable
as $$
  select p_ts >= timestamptz '2026-10-05 00:00:00+09'
     and ((extract(month from p_ts at time zone 'Asia/Seoul') = 10
           and extract(day from p_ts at time zone 'Asia/Seoul') >= 5)
       or (extract(month from p_ts at time zone 'Asia/Seoul') = 11
           and extract(day from p_ts at time zone 'Asia/Seoul') = 1));
$$;

-- 지금 속한 해의 할로윈 시작 (10월 5일 0시, 한국 시간)
create or replace function public.halloween_start()
returns timestamptz
language sql
stable
as $$
  select timestamptz '2026-10-05 00:00:00+09'
         + public.shop_shift(timestamptz '2026-10-05 00:00:00+09', true);
$$;

-- 이벤트 퀘스트를 연 시각. 이 전의 칸은 만들지 않는다
do $$
begin
  execute format($f$
    create or replace function public.event_launch()
    returns timestamptz
    language sql
    immutable
    as $b$ select %L::timestamptz $b$
  $f$, now());
end;
$$;

-- ------------------------------------------------------------
-- 4. 랜덤 구성 — 중립 후보에 마녀를 더했다 (0041 과 나머지는 같다)
-- ------------------------------------------------------------

create or replace function public.team_composition(
  p_count int, p_disabled text[] default '{}', p_max jsonb default '{}')
returns json
language plpgsql
immutable
as $$
declare
  off       text[] := coalesce(p_disabled, '{}');
  v_mafia   int;
  v_neutral int;
  v_open    int;
  v_mopen   int;
begin
  if p_count is null or p_count < 5 or p_count > 15 then
    raise exception '% 명은 지원하지 않습니다. (5~15명)', p_count;
  end if;

  v_mafia := case
    when p_count <= 6  then 1
    when p_count <= 8  then 2
    when p_count <= 11 then 3
    else 4
  end;
  v_neutral := case when p_count >= 9 then 2 else 1 end;

  -- 켜진 중립 직업의 최대 인원 합보다 자리가 많으면 남는 자리는 시민 진영으로 간다
  select coalesce(sum(public.role_max_of(p_max, x)), 0) into v_open
    from unnest(array['JESTER', 'KILLER', 'SURVIVOR', 'WITCH']) x
   where not (x = any (off));
  v_neutral := least(v_neutral, v_open);

  -- 마피아가 꺼져 있으면 마피아 진영은 켜진 스파이·암살자·위조범 수만큼만 채운다.
  -- 남는 자리는 시민 진영으로 간다. 0명이면 시작할 수 없다 (assign_roles).
  if 'MAFIA' = any (off) then
    select coalesce(sum(public.role_max_of(p_max, x)), 0) into v_mopen
      from unnest(array['SPY', 'ASSASSIN', 'FORGER']) x
     where not (x = any (off));
    v_mafia := least(v_mafia, v_mopen);
  end if;

  return json_build_object(
    'mafia',   v_mafia,
    'neutral', v_neutral,
    'citizen', p_count - v_mafia - v_neutral);
end;
$$;

grant execute on function public.team_composition(int, text[], jsonb) to anon, authenticated;

create or replace function public.random_composition(
  p_count int, p_disabled text[] default '{}', p_max jsonb default '{}')
returns text[]
language plpgsql
volatile
as $$
declare
  off      text[] := coalesce(p_disabled, '{}');
  v_teams  json;
  v_m      int;
  v_n      int;
  v_c      int;
  v_pool   text[];
  v_out    text[] := '{}';
begin
  v_teams := public.team_composition(p_count, off, p_max);
  v_m := (v_teams ->> 'mafia')::int;
  v_n := (v_teams ->> 'neutral')::int;
  v_c := (v_teams ->> 'citizen')::int;

  if 'MAFIA' = any (off) then
    v_out := v_out || array(
      select x from public.role_pool(array['SPY', 'ASSASSIN', 'FORGER'], off, p_max) x
       order by random() limit v_m);
  else
    v_out := v_out || 'MAFIA'::text;
    if v_m > 1 then
      v_pool := array(select x from public.role_pool(array['SPY', 'ASSASSIN', 'FORGER'], off, p_max) x)
                || array_fill('MAFIA'::text, array[v_m - 1]);
      v_out := v_out || array(select x from unnest(v_pool) x order by random() limit v_m - 1);
    end if;
  end if;

  -- 중립: 켜진 중립 직업 중에서 (자리 수는 이미 켜진 직업 수 이하)
  if v_n > 0 then
    v_out := v_out || array(
      select x from public.role_pool(array['JESTER', 'KILLER', 'SURVIVOR', 'WITCH'], off, p_max) x
       order by random() limit v_n);
  end if;

  v_pool := array(
              select x from public.role_pool(array['POLICE', 'DOCTOR', 'BODYGUARD', 'DETECTIVE',
                                                   'REPORTER', 'MEDIUM', 'VIGILANTE', 'SHERIFF'],
                                             off, p_max) x);
  if 'CITIZEN' = any (off) then
    if coalesce(array_length(v_pool, 1), 0) < v_c then
      raise exception '시민 진영 직업이 부족해 게임을 시작할 수 없습니다. (필요 %명, 켜진 직업 %개)',
        v_c, coalesce(array_length(v_pool, 1), 0);
    end if;
  else
    v_pool := v_pool || array_fill('CITIZEN'::text, array[v_c]);
  end if;
  v_out := v_out || array(select x from unnest(v_pool) x order by random() limit v_c);

  if coalesce(array_length(v_out, 1), 0) <> p_count then
    raise exception '랜덤 구성 오류: %명 구성의 직업 수가 %개입니다.',
      p_count, coalesce(array_length(v_out, 1), 0);
  end if;

  return v_out;
end;
$$;

revoke all on function public.random_composition(int, text[], jsonb) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 5. 마녀 퀘스트
-- ------------------------------------------------------------

-- 퀘스트 목표. 제거 퀘스트는 인원수로, 생존은 목표 날 (없으면 null)
create or replace function public.witch_goal(p_quest text, p_players int, p_max int)
returns int
language sql
immutable
as $$
  select case p_quest
    when 'CITIZEN' then case when p_players <= 8 then 2 when p_players <= 12 then 3 else 5 end
    when 'MAFIA'   then case when p_players <= 11 then 1 else 2 end
    when 'NEUTRAL' then case when p_players <= 11 then 1 else 2 end
    when 'SURVIVE' then public.survivor_target(p_max, p_players)
  end;
$$;

-- 마녀가 지금까지 퀘스트 진영을 제거한 수 (밤에 지목한 사람이 그 밤에 죽었다)
create or replace function public.witch_kills(p_room_id uuid, p_uid uuid, p_team text)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int
    from public.night_actions n
    join public.private_roles tgt on tgt.room_id = n.room_id and tgt.uid = n.target_uid
   where n.room_id = p_room_id and n.actor_uid = p_uid
     and n.action = 'WITCH' and n.target_uid is not null
     and tgt.team = p_team
     and public.died_at_night(p_room_id, n.day_number, n.target_uid);
$$;

-- 배정 뒤 마녀마다 퀘스트를 고른다. 이 판에서 깰 수 있는 것 중에서 무작위
create or replace function public.assign_witch_quests(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
  v_max   int;
  v_rec   record;
  v_quest text;
begin
  select count(*) into v_count from public.players pl where pl.room_id = p_room_id;
  select r.max_days into v_max from public.rooms r where r.id = p_room_id;

  for v_rec in
    select pr.uid from public.private_roles pr
     where pr.room_id = p_room_id and pr.role = 'WITCH'
  loop
    select q into v_quest
      from unnest(array['CITIZEN', 'MAFIA', 'NEUTRAL', 'SURVIVE']) q
     where public.witch_goal(q, v_count, v_max) is not null
       and (q = 'SURVIVE' or public.witch_goal(q, v_count, v_max) <= (
             select count(*) from public.private_roles o
              where o.room_id = p_room_id and o.team = q and o.uid <> v_rec.uid))
     order by random()
     limit 1;

    v_quest := coalesce(v_quest, 'CITIZEN');

    update public.private_roles pr
       set witch_quest = v_quest,
           witch_goal  = public.witch_goal(v_quest, v_count, v_max)
     where pr.room_id = p_room_id and pr.uid = v_rec.uid;
  end loop;
end;
$$;

revoke all on function public.witch_goal(text, int, int)          from public, anon, authenticated;
revoke all on function public.witch_kills(uuid, uuid, text)        from public, anon, authenticated;
revoke all on function public.assign_witch_quests(uuid)            from public, anon, authenticated;

-- ------------------------------------------------------------
-- 6. 직업 배정 — 할로윈이 아니면 마녀를 빼고, 마녀 퀘스트를 고른다 (0069 와 나머지는 같다)
-- ------------------------------------------------------------

create or replace function public.assign_roles(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_roles  text[];
  v_off    text[];
  v_random boolean;
  v_rmax   jsonb;
  v_max    int;
  v_count  int;
  v_i      int := 1;
  v_uid    uuid;
  v_role   text;
  v_team   text;
begin
  select count(*) into v_count from public.players pl where pl.room_id = p_room_id;
  select r.disabled_roles, r.random_roles, r.max_days, r.role_max
    into v_off, v_random, v_max, v_rmax
    from public.rooms r where r.id = p_room_id;

  -- 목표 날이 최대 일수를 넘으면 생존자는 이길 날이 없으므로 넣지 않는다
  if public.survivor_target(v_max, v_count) is null then
    v_off := coalesce(v_off, '{}') || 'SURVIVOR'::text;
  end if;

  -- 마녀는 할로윈 기간에만 나온다
  if not public.is_halloween() then
    v_off := coalesce(v_off, '{}') || 'WITCH'::text;
  end if;

  if coalesce(v_random, true) then
    v_roles := public.random_composition(v_count, coalesce(v_off, '{}'), coalesce(v_rmax, '{}'));
  else
    -- 고정 구성은 끈 직업 자리를 시민이 채우므로 시민 끄기는 무시한다
    v_roles := public.role_composition(v_count, array_remove(coalesce(v_off, '{}'), 'CITIZEN'));
  end if;

  if not exists (select 1 from unnest(v_roles) x where public.team_of(x) = 'MAFIA') then
    raise exception '마피아 진영 직업이 하나도 없어 게임을 시작할 수 없습니다.';
  end if;

  for v_uid in
    select pl.uid from public.players pl
     where pl.room_id = p_room_id
     order by random()
  loop
    v_role := v_roles[v_i];
    v_team := public.team_of(v_role);

    insert into public.private_roles (room_id, uid, role, team)
    values (p_room_id, v_uid, v_role, v_team)
    on conflict (room_id, uid) do update
      set role = excluded.role, team = excluded.team,
          witch_quest = null, witch_goal = null, witch_won = false;

    if v_role = 'JESTER' then
      update public.rooms r set jester_uid = v_uid where r.id = p_room_id;
    end if;

    v_i := v_i + 1;
  end loop;

  perform public.assign_witch_quests(p_room_id);
end;
$$;

revoke all on function public.assign_roles(uuid) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 7. 마녀 승리 판정 (내부용). 깬 마녀를 witch_won 에 남기고 'WITCH' 또는 null
-- ------------------------------------------------------------

-- 제거 퀘스트: 살아 있는 마녀가 목표만큼 제거했으면
create or replace function public.check_witch_kills(p_room_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.private_roles pr
     set witch_won = true
    from public.players pl
   where pl.room_id = pr.room_id and pl.uid = pr.uid and pl.alive = true
     and pr.room_id = p_room_id and pr.role = 'WITCH'
     and pr.witch_quest in ('CITIZEN', 'MAFIA', 'NEUTRAL')
     and public.witch_kills(p_room_id, pr.uid, pr.witch_quest) >= pr.witch_goal;
  return case when found then 'WITCH' end;
end;
$$;

-- 생존 퀘스트: 목표 날의 낮이 끝날 때 살아 있으면
create or replace function public.check_witch_survive(p_room_id uuid, p_day int)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.private_roles pr
     set witch_won = true
    from public.players pl
   where pl.room_id = pr.room_id and pl.uid = pr.uid and pl.alive = true
     and pr.room_id = p_room_id and pr.role = 'WITCH'
     and pr.witch_quest = 'SURVIVE'
     and p_day >= pr.witch_goal;
  return case when found then 'WITCH' end;
end;
$$;

revoke all on function public.check_witch_kills(uuid)        from public, anon, authenticated;
revoke all on function public.check_witch_survive(uuid, int) from public, anon, authenticated;

-- 이 사람이 이겼는지 (0041 에 마녀를 더했다)
create or replace function public.player_won(
  p_room_id uuid, p_winner text, p_uid uuid, p_role text, p_team text, p_alive boolean)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when p_winner in ('CITIZEN', 'MAFIA') then p_team = p_winner
    when p_winner = 'JESTER' then
      p_uid = (select r.jester_uid from public.rooms r where r.id = p_room_id)
    when p_winner in ('KILLER', 'SURVIVOR') then p_role = p_winner and p_alive
    when p_winner = 'WITCH' then p_role = 'WITCH' and coalesce((
      select pr.witch_won from public.private_roles pr
       where pr.room_id = p_room_id and pr.uid = p_uid), false)
    else false
  end;
$$;

revoke all on function public.player_won(uuid, text, uuid, text, text, boolean) from public, anon, authenticated;

-- 퀘스트 킬 수에 마녀를 더한다 (0047 과 나머지는 같다)
create or replace function public.kills_of(p_room_id uuid, p_uid uuid, p_role text)
returns int
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v int := 0;
begin
  if p_role in ('MAFIA', 'SPY') then
    select count(*) into v
      from public.night_actions n
     where n.room_id = p_room_id and n.actor_uid = p_uid
       and n.action = 'MAFIA_VOTE' and n.target_uid is not null
       and n.target_uid = public.mafia_target(p_room_id, n.day_number)
       and public.died_at_night(p_room_id, n.day_number, n.target_uid);
  elsif p_role in ('VIGILANTE', 'KILLER', 'SHERIFF', 'WITCH') then
    select count(*) into v
      from public.night_actions n
     where n.room_id = p_room_id and n.actor_uid = p_uid
       and n.action = p_role and n.target_uid is not null
       and public.died_at_night(p_room_id, n.day_number, n.target_uid);
  elsif p_role = 'ASSASSIN' then
    select count(*) into v
      from public.assassinations a
     where a.room_id = p_room_id and a.actor_uid = p_uid
       and a.resolved = true and a.success;
  end if;
  return coalesce(v, 0);
end;
$$;

revoke all on function public.kills_of(uuid, uuid, text) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 8. 밤 행동 제출 — 마녀를 더했다. 마녀는 오늘 쓰지 않고 넘길 수 있다 (0033 과 나머지는 같다)
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
  v_forged      int;
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
    if public.team_of(v_role) <> 'MAFIA' then
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
      when 'KILLER'    then 'KILLER'
      when 'VIGILANTE' then 'VIGILANTE'
      when 'SHERIFF'   then 'SHERIFF'
      when 'FORGE'     then 'FORGER'
      when 'WITCH'     then 'WITCH'
      else null
    end;

    if v_needed is null then
      raise exception '아직 구현되지 않은 능력입니다: %', p_action;
    end if;
    if v_role <> v_needed then
      raise exception '사용할 수 없는 능력입니다.';
    end if;
  end if;

  if p_action = 'VIGILANTE' and v_used then
    raise exception '당신은 제거를 이미 했습니다.';
  end if;

  if p_target_uid is null then
    if p_action not in ('REPORTER', 'VIGILANTE', 'SHERIFF', 'WITCH') then
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
    elsif p_action = 'FORGE' then
      null;
    else
      if not v_target_alive then
        raise exception '살아 있는 참가자만 지목할 수 있습니다.';
      end if;
    end if;

    if p_action in ('MAFIA_VOTE', 'BODYGUARD', 'KILLER', 'VIGILANTE', 'SHERIFF', 'WITCH')
       and p_target_uid = v_uid then
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

    if p_action = 'FORGE' then
      select count(*) into v_forged
        from public.night_actions n
       where n.room_id = p_room_id and n.actor_uid = v_uid
         and n.action = 'FORGE' and n.target_uid is not null
         and n.day_number < v_room.day_number;
      if v_forged >= public.forge_limit(p_room_id) then
        raise exception '위조 기회를 모두 썼습니다.';
      end if;
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
-- 9. 밤 처리 — 마녀 공격과 마녀 승리를 더했다 (0041 과 나머지는 같다)
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
  v_dead      uuid;
  v_ktargets  uuid[] := '{}';
  v_wtargets  uuid[] := '{}';
  v_vactors   uuid[] := '{}';
  v_vtargets  uuid[] := '{}';
  v_stargets  uuid[] := '{}';
  v_smisfire  uuid[] := '{}';
  v_forged    uuid[] := '{}';
  v_attacks   uuid[] := '{}';
  v_guardmap  jsonb := '[]'::jsonb;
  v_t         uuid;
  v_died      uuid[];
begin
  select r.day_number into v_day from public.rooms r where r.id = p_room_id;

  -- 1. 마피아 공격 대상 확정. 스파이·암살자의 표도 함께 센다 (§2.2)
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

  -- 2. 의사 치료 대상 (§2.4)
  select coalesce(array_agg(n.target_uid), '{}')
    into v_healed
    from public.night_actions n
    join public.private_roles pr on pr.room_id = n.room_id and pr.uid = n.actor_uid
    join public.players pl       on pl.room_id = n.room_id and pl.uid = n.actor_uid
   where n.room_id = p_room_id and n.day_number = v_day
     and n.action = 'DOCTOR' and pr.role = 'DOCTOR'
     and pl.alive = true and n.target_uid is not null;

  -- 2-2. 살인자 공격 대상. 살인자마다 혼자 정하므로 표결이 없다
  select coalesce(array_agg(n.target_uid), '{}') into v_ktargets
    from public.night_actions n
    join public.private_roles pr on pr.room_id = n.room_id and pr.uid = n.actor_uid
    join public.players pl       on pl.room_id = n.room_id and pl.uid = n.actor_uid
   where n.room_id = p_room_id and n.day_number = v_day
     and n.action = 'KILLER' and pr.role = 'KILLER'
     and pl.alive = true and n.target_uid is not null;

  -- 2-2-1. 마녀 공격 대상. 살인자와 같이 마녀마다 혼자 정한다
  select coalesce(array_agg(n.target_uid), '{}') into v_wtargets
    from public.night_actions n
    join public.private_roles pr on pr.room_id = n.room_id and pr.uid = n.actor_uid
    join public.players pl       on pl.room_id = n.room_id and pl.uid = n.actor_uid
   where n.room_id = p_room_id and n.day_number = v_day
     and n.action = 'WITCH' and pr.role = 'WITCH'
     and pl.alive = true and n.target_uid is not null;

  -- 2-3. 자경단 공격 대상. 게임 중 한 번뿐이라 쏘는 순간 기회를 쓴다.
  select coalesce(array_agg(n.actor_uid), '{}'), coalesce(array_agg(n.target_uid), '{}')
    into v_vactors, v_vtargets
    from public.night_actions n
    join public.private_roles pr on pr.room_id = n.room_id and pr.uid = n.actor_uid
    join public.players pl       on pl.room_id = n.room_id and pl.uid = n.actor_uid
   where n.room_id = p_room_id and n.day_number = v_day
     and n.action = 'VIGILANTE' and pr.role = 'VIGILANTE'
     and pl.alive = true and pl.ability_used = false
     and n.target_uid is not null;

  update public.players pl
     set ability_used = true
   where pl.room_id = p_room_id and pl.uid = any (v_vactors);

  -- 2-4. 보안관 공격 대상. 시민 진영을 쏜 보안관은 오인 사격으로 함께 죽는다.
  select coalesce(array_agg(n.target_uid), '{}'),
         coalesce(array_agg(n.actor_uid) filter (where tgt.team = 'CITIZEN'), '{}')
    into v_stargets, v_smisfire
    from public.night_actions n
    join public.private_roles pr  on pr.room_id = n.room_id and pr.uid = n.actor_uid
    join public.players pl        on pl.room_id = n.room_id and pl.uid = n.actor_uid
    join public.private_roles tgt on tgt.room_id = n.room_id and tgt.uid = n.target_uid
   where n.room_id = p_room_id and n.day_number = v_day
     and n.action = 'SHERIFF' and pr.role = 'SHERIFF'
     and pl.alive = true and n.target_uid is not null;

  -- 공격 목록: 마피아 -> 살인자 -> 마녀 -> 자경단 -> 보안관. 같은 사람을 노렸으면 한 번만 친다.
  if v_target is not null then
    v_attacks := v_attacks || v_target;
  end if;
  foreach v_t in array v_ktargets || v_wtargets || v_vtargets || v_stargets loop
    if not (v_t = any (v_attacks)) then
      v_attacks := v_attacks || v_t;
    end if;
  end loop;

  -- 3. 경호원 보호 대상 (§2.5)
  select coalesce(jsonb_agg(jsonb_build_object('t', n.target_uid, 'g', n.actor_uid)),
                  '[]'::jsonb)
    into v_guardmap
    from public.night_actions n
    join public.private_roles pr on pr.room_id = n.room_id and pr.uid = n.actor_uid
    join public.players pl       on pl.room_id = n.room_id and pl.uid = n.actor_uid
   where n.room_id = p_room_id and n.day_number = v_day
     and n.action = 'BODYGUARD' and pr.role = 'BODYGUARD'
     and pl.alive = true and n.target_uid = any (v_attacks);

  -- 4~5. 공격마다 생존·사망 계산 (§3.1 — 치료 우선, 다음이 경호)
  foreach v_t in array v_attacks loop
    select coalesce(array_agg((e ->> 'g')::uuid), '{}')
      into v_guards
      from jsonb_array_elements(v_guardmap) e
     where (e ->> 't')::uuid = v_t;

    v_saved := v_t = any (v_healed);
    v_shielded := not v_saved and coalesce(array_length(v_guards, 1), 0) > 0;

    if not v_saved then
      with d as (
        update public.players pl
           set alive = false
         where pl.room_id = p_room_id and pl.alive = true
           and (case when v_shielded then pl.uid = any (v_guards) else pl.uid = v_t end)
        returning pl.uid
      )
      select coalesce(array_agg(d.uid), '{}') into v_died from d;
      v_deaths := v_deaths || v_died;
    end if;

    if v_saved then
      insert into public.private_results (room_id, uid, day_number, kind, payload)
      select p_room_id, n.actor_uid, v_day, 'DOCTOR',
             jsonb_build_object('savedUid', v_t, 'savedNickname', tp.nickname)
        from public.night_actions n
        join public.players tp on tp.room_id = n.room_id and tp.uid = n.target_uid
       where n.room_id = p_room_id and n.day_number = v_day
         and n.action = 'DOCTOR' and n.target_uid = v_t
      on conflict (room_id, uid, day_number, kind) do update set payload = excluded.payload;
    end if;

    if coalesce(array_length(v_guards, 1), 0) > 0 then
      insert into public.private_results (room_id, uid, day_number, kind, payload)
      select p_room_id, g, v_day, 'BODYGUARD',
             jsonb_build_object('protectedUid', v_t,
                                'protectedNickname', tp.nickname,
                                'sacrificed', v_shielded)
        from unnest(v_guards) g
        join public.players tp on tp.room_id = p_room_id and tp.uid = v_t
      on conflict (room_id, uid, day_number, kind) do update set payload = excluded.payload;
    end if;
  end loop;

  -- 5-1. 보안관 오인 사격
  if coalesce(array_length(v_smisfire, 1), 0) > 0 then
    with d as (
      update public.players pl
         set alive = false
       where pl.room_id = p_room_id and pl.uid = any (v_smisfire) and pl.alive = true
      returning pl.uid
    )
    select coalesce(array_agg(d.uid), '{}') into v_died from d;
    v_deaths := v_deaths || v_died;
  end if;

  -- 5-2. 밤 저격. 치료·보호로 막을 수 없다.
  for v_rec in
    select a.actor_uid
      from public.assassinations a
      join public.private_roles pr on pr.room_id = a.room_id and pr.uid = a.actor_uid
     where a.room_id = p_room_id and a.day_number = v_day
       and a.phase = 'NIGHT' and a.resolved = false
       and pr.role = 'ASSASSIN'
  loop
    v_dead := public.apply_assassination(p_room_id, v_day, 'NIGHT', v_rec.actor_uid);
    if v_dead is not null then
      v_deaths := v_deaths || v_dead;
    end if;
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

  -- 5-3. 위조 대상
  select coalesce(array_agg(n.target_uid), '{}')
    into v_forged
    from public.night_actions n
    join public.private_roles pr on pr.room_id = n.room_id and pr.uid = n.actor_uid
   where n.room_id = p_room_id and n.day_number = v_day
     and n.action = 'FORGE' and pr.role = 'FORGER'
     and n.target_uid is not null;

  -- 6. 경찰 조사 (§2.3)
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
                               'team', case when v_rec.target_uid = any (v_forged)
                                            then public.forged_team(v_rec.target_team)
                                            else v_rec.target_team end))
    on conflict (room_id, uid, day_number, kind) do update set payload = excluded.payload;
  end loop;

  -- 7. 탐정
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
                case when v_rec.target_uid = any (v_forged)
                     then public.forged_candidates(p_room_id, v_rec.target_uid)
                     else public.detective_candidates(p_room_id, v_rec.target_uid) end)))
    on conflict (room_id, uid, day_number, kind) do update set payload = excluded.payload;
  end loop;

  -- 8. 영매
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
                               'role', case when v_rec.target_uid = any (v_forged)
                                            then case when public.team_of(v_rec.target_role) = 'MAFIA'
                                                      then 'CITIZEN' else 'MAFIA' end
                                            else v_rec.target_role end))
    on conflict (room_id, uid, day_number, kind) do update set payload = excluded.payload;
  end loop;

  -- 9. 기자 (성공률 50%)
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
                               'team', case when not v_ok then null
                                          when v_rec.target_uid = any (v_forged)
                                            then public.forged_team(v_rec.target_team)
                                          when v_rec.target_team = 'NEUTRAL' then 'CITIZEN'
                                          else v_rec.target_team end))
    on conflict (room_id, uid, day_number, kind) do update set payload = excluded.payload;

    if v_ok then
      v_reveal := v_reveal || jsonb_build_object(
        'targetUid', v_rec.target_uid,
        'targetNickname', v_rec.target_nick,
        'team', case when v_rec.target_uid = any (v_forged)
                       then public.forged_team(v_rec.target_team)
                     when v_rec.target_team = 'NEUTRAL' then 'CITIZEN'
                     else v_rec.target_team end);
    end if;
  end loop;

  -- 공개 결과 — 사망자와 취재 성공분만. 사인은 구분하지 않는다.
  insert into public.public_results (room_id, day_number, kind, payload)
  values (p_room_id, v_day, 'NIGHT',
          jsonb_build_object('nightDeaths', to_jsonb(v_deaths),
                             'reporterReveal', v_reveal))
  on conflict (room_id, day_number, kind) do update
    set payload = public.public_results.payload || excluded.payload;

  -- 10. 승리 조건. 마녀가 제거 퀘스트를 깼으면 즉시 승리 (다른 승리보다 먼저)
  v_winner := public.check_witch_kills(p_room_id);
  if v_winner is null then
    v_winner := public.check_winner(p_room_id);
  end if;
  if v_winner is not null then
    perform public.end_game(p_room_id, v_winner);
    return;
  end if;

  -- 11. 낮으로
  perform public.enter_phase(p_room_id, 'DAY', v_day);
end;
$$;

revoke all on function public.resolve_night(uuid) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 10. 낮 처리 — 마녀 생존 퀘스트를 더했다 (0069 와 나머지는 같다)
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
  v_skip     int;
  v_skipped  boolean;
  v_executed uuid := null;
  v_team     text := null;
  v_role     text := null;
  v_winner   text;
  v_count    int;
begin
  select r.day_number, r.max_days into v_day, v_max
    from public.rooms r where r.id = p_room_id;

  select count(*) into v_count from public.players pl where pl.room_id = p_room_id;

  select count(*) into v_skip
    from public.day_votes d
   where d.room_id = p_room_id and d.day_number = v_day
     and d.target_uid = public.skip_vote_uid();

  with tally as (
    select d.target_uid as t_uid, count(*) as c
      from public.day_votes d
     where d.room_id = p_room_id and d.day_number = v_day
       and d.target_uid <> public.skip_vote_uid()
     group by d.target_uid
  ), mx as (
    select max(c) as m from tally
  )
  select count(*), (array_agg(tally.t_uid))[1], max(mx.m)
    into v_ties, v_target, v_top
    from tally join mx on tally.c = mx.m;

  select coalesce(jsonb_agg(jsonb_build_object('uid', t.t_uid, 'count', t.c)
                            order by t.c desc), '[]'::jsonb)
    into v_votes
    from (
      select d.target_uid as t_uid, count(*) as c
        from public.day_votes d
       where d.room_id = p_room_id and d.day_number = v_day
         and d.target_uid <> public.skip_vote_uid()
       group by d.target_uid
    ) t;

  v_skipped := v_skip > 0 and v_skip >= coalesce(v_top, 0);

  if not v_skipped and coalesce(v_ties, 0) = 1 and v_target is not null then
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
    'tie',           not v_skipped and coalesce(v_ties, 0) > 1,
    'skipVotes',     v_skip,
    'skipped',       v_skipped,
    'executedTeam',  case when v_team = 'NEUTRAL' then null else v_team end,
    'executedRole',  case when v_team = 'NEUTRAL' then v_role else null end))
  on conflict (room_id, day_number, kind) do update
    set payload = public.public_results.payload || excluded.payload;

  v_winner := public.check_winner(p_room_id, v_executed);
  if v_winner is not null then
    perform public.end_game(p_room_id, v_winner);
    return;
  end if;

  -- 마녀: 생존 퀘스트의 목표 날 낮이 끝날 때 살아 있으면 단독 승리
  if public.check_witch_survive(p_room_id, v_day) is not null then
    perform public.end_game(p_room_id, 'WITCH');
    return;
  end if;

  -- 생존자: 목표 날의 낮이 끝날 때 살아 있으면 단독 승리 (§4.1-3)
  if v_day >= coalesce(public.survivor_target(v_max, v_count), v_max + 1) and exists (
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

  perform public.enter_phase(p_room_id, 'DAY_RESULT', v_day);
end;
$$;
revoke all on function public.resolve_day(uuid) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 11. 저격수가 마녀를 찍을 수 있게 한다 (0042 와 나머지는 같다)
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
    raise exception '저격수만 사용할 수 있습니다.';
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
    raise exception '상대가 모두 시민이면 저격할 수 없습니다.';
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
      'DETECTIVE','REPORTER','MEDIUM','SPY','JESTER','ASSASSIN','KILLER','VIGILANTE','SHERIFF','FORGER','SURVIVOR','WITCH') then
    raise exception '직업을 선택해 주세요.';
  end if;

  insert into public.assassinations
    (room_id, day_number, phase, actor_uid, target_uid, guess_role)
  values
    (p_room_id, v_room.day_number, v_room.phase, v_uid, p_target_uid, p_guess);

  if v_room.phase = 'NIGHT' then
    return json_build_object('resolved', false, 'phase', 'NIGHT');
  end if;

  v_dead := public.apply_assassination(p_room_id, v_room.day_number, 'DAY', v_uid);

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
-- 12. 내 화면 정보 — 마녀 퀘스트를 더했다 (0033 과 나머지는 같다)
--   witch: { quest, goal, progress } — progress 는 제거 수, 생존이면 지금 날
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
  v_as        json := null;
  v_forge     json := null;
  v_witch     json := null;
  v_wquest    text;
  v_wgoal     int;
begin
  select * into v_room from public.rooms r where r.id = p_room_id;
  if not found then
    raise exception '존재하지 않는 방입니다.';
  end if;

  select pr.role, pr.team, pr.witch_quest, pr.witch_goal
    into v_role, v_team, v_wquest, v_wgoal
    from public.private_roles pr
   where pr.room_id = p_room_id and pr.uid = v_uid;
  if not found then
    raise exception '아직 직업이 배정되지 않았습니다.';
  end if;

  select pl.alive, pl.last_target_id, pl.ability_used
    into v_alive, v_last, v_used
    from public.players pl
   where pl.room_id = p_room_id and pl.uid = v_uid;

  if v_team = 'MAFIA' then
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
     and n.actor_uid = v_uid
     and n.action <> 'FORGE';
  v_acted := coalesce(v_acted, false);

  if v_role = 'FORGER' then
    select json_build_object(
             'limit', public.forge_limit(p_room_id),
             'used', count(*) filter (where n.day_number < v_room.day_number
                                        or v_room.phase <> 'NIGHT'),
             'tonight', max(n.target_uid::text) filter (
                          where n.day_number = v_room.day_number and v_room.phase = 'NIGHT'))
      into v_forge
      from public.night_actions n
     where n.room_id = p_room_id and n.actor_uid = v_uid
       and n.action = 'FORGE' and n.target_uid is not null;
  end if;

  -- 마녀 퀘스트 (마녀에게만). 밤 처리가 끝난 제거만 센다
  if v_role = 'WITCH' and v_wquest is not null then
    v_witch := json_build_object(
      'quest',    v_wquest,
      'goal',     v_wgoal,
      'progress', case when v_wquest = 'SURVIVE' then v_room.day_number
                       else public.witch_kills(p_room_id, v_uid, v_wquest) end);
  end if;

  if v_team = 'MAFIA' then
    select count(*) into v_n_exp
      from public.private_roles pr
      join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
     where pr.room_id = p_room_id
       and pr.team = 'MAFIA'
       and pl.alive = true;

    select count(*) into v_n_sub
      from public.night_actions n
     where n.room_id = p_room_id and n.day_number = v_room.day_number
       and n.action = 'MAFIA_VOTE';
  end if;

  if v_role = 'ASSASSIN' then
    select json_build_object(
             'done', true,
             'targetUid', a.target_uid,
             'guess', a.guess_role,
             'resolved', a.resolved,
             'success', a.success,
             'actualRole', a.actual_role)
      into v_as
      from public.assassinations a
     where a.room_id = p_room_id
       and a.day_number = v_room.day_number
       and a.phase = v_room.phase
       and a.actor_uid = v_uid;
    v_as := coalesce(v_as, json_build_object('done', false));
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
    'assassin',       v_as,
    'canAssassinate', case when v_role = 'ASSASSIN'
                        then public.can_assassinate(p_room_id) else null end,
    'mafiaMembers',   v_mates,
    'nightSubmitted', v_night,
    'daySubmitted',   v_day,
    'forger',         v_forge,
    'witch',          v_witch,
    'nightProgress',  case when v_team = 'MAFIA'
                        then json_build_object('submitted', v_n_sub, 'expected', v_n_exp)
                        else null end,
    'dayProgress',    json_build_object('submitted', v_d_sub, 'expected', v_d_exp),
    'privateResults', v_results
  );
end;
$$;

grant execute on function public.my_game_view(uuid) to anon, authenticated;

-- ------------------------------------------------------------
-- 13. 상자를 열면 기록을 남긴다 (0063 과 나머지는 같다)
-- ------------------------------------------------------------

create or replace function public.open_box(p_uid uuid, p_box text, p_bonus int default 0)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_r    jsonb := public.roll_box(p_box);
  v_type text  := v_r ->> 'type';
  v_amt  int   := (v_r ->> 'amount')::int;
  v_item text  := v_r ->> 'item';
  v_dup  boolean := false;
begin
  if v_item is not null then
    insert into public.owned_items (uid, item_id) values (p_uid, v_item)
    on conflict (uid, item_id) do nothing;
    if not found then
      v_dup := true;
      select s.price_type, s.price / 2 into v_type, v_amt from public.shop_items s where s.id = v_item;
    end if;
  end if;

  if v_type is not null then
    v_amt := public.with_bonus(v_amt, p_bonus);
    perform public.give_currency(p_uid, v_type, v_amt);
  end if;

  insert into public.box_opens (uid, box) values (p_uid, p_box);

  return jsonb_build_object('box', p_box, 'type', v_type, 'amount', v_amt, 'item', v_item, 'dup', v_dup);
end;
$$;

revoke all on function public.open_box(uuid, text, int) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 14. 이벤트 퀘스트
-- ------------------------------------------------------------

create or replace function public.quest_period(p_category text)
returns interval
language sql
immutable
as $$
  select case p_category
    when 'MAIN'    then interval '2 days'
    when 'DAILY'   then interval '1 day'
    when 'WEEKLY'  then interval '7 days'
    when 'MONTHLY' then interval '30 days'
    when 'YEARLY'  then interval '365 days'
    when 'ROLE'    then interval '7 days'
    when 'EVENT'   then interval '3 days'
  end;
$$;

-- 할로윈 이벤트 퀘스트 [종류, 목표, 보상 재화, 보상 개수]
create or replace function public.event_quest_pool()
returns jsonb
language sql
immutable
as $$
  select '[["PUMPKIN_BOX",5,"STAR",10],["WITCH_WIN",10,"STAR",15],["HALLOWEEN_WIN",30,"GEM",2]]'::jsonb;
$$;

-- 진행도. 이벤트 종류를 더했다 (0049 와 나머지는 같다)
create or replace function public.quest_progress(p_uid uuid, p_kind text, p_since timestamptz, p_role text)
returns int
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v int;
begin
  if p_role is not null then
    select case p_kind
             when 'WIN'     then count(*) filter (where g.won)
             when 'KILL'    then sum(g.kills)
             when 'SURVIVE' then sum(g.days)
             else sum(coalesce((g.stats ->> p_kind)::int, 0))
           end
      into v
      from public.game_records g
     where g.uid = p_uid and g.ended_at >= p_since and g.role = p_role;
    return coalesce(v, 0);
  end if;

  case p_kind
  when 'WIN' then
    select count(*) into v from public.game_records g
     where g.uid = p_uid and g.ended_at >= p_since and g.won;
  when 'PLAY' then
    select count(*) into v from public.game_records g
     where g.uid = p_uid and g.ended_at >= p_since;
  when 'KILL' then
    select sum(g.kills) into v from public.game_records g
     where g.uid = p_uid and g.ended_at >= p_since;
  when 'SURVIVE' then
    select sum(g.days) into v from public.game_records g
     where g.uid = p_uid and g.ended_at >= p_since;
  when 'STREAK' then
    select max(c) into v from (
      select count(*) as c from (
        select g.won,
               sum(case when g.won then 0 else 1 end) over (order by g.ended_at, g.id) as grp
          from public.game_records g
         where g.uid = p_uid and g.ended_at >= p_since
      ) s
       where s.won
       group by s.grp
    ) x;
  when 'CLEAR' then
    select count(*) into v from public.quest_clears c
     where c.uid = p_uid and c.claimed_at >= p_since;
  when 'PUMPKIN_BOX' then
    select count(*) into v from public.box_opens b
     where b.uid = p_uid and b.box = 'PUMPKIN' and b.opened_at >= p_since;
  when 'WITCH_WIN' then
    select count(*) into v from public.game_records g
     where g.uid = p_uid and g.ended_at >= p_since and g.won and g.role = 'WITCH';
  when 'HALLOWEEN_WIN' then
    select count(*) into v from public.game_records g
     where g.uid = p_uid and g.ended_at >= p_since and g.won
       and public.is_halloween_at(g.ended_at);
  else
    v := 0;
  end case;
  return coalesce(v, 0);
end;
$$;

revoke all on function public.quest_progress(uuid, text, timestamptz, text) from public, anon, authenticated;

-- 이벤트 퀘스트를 만든다. 할로윈 기간에만, 그해 할로윈 시작부터 3일마다.
-- 칸 번호는 해 * 100 + 순번이다. 이벤트를 연 시각 전의 칸은 만들지 않는다. 최근 10개만 남긴다
create or replace function public.generate_event_quests(p_uid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_start  timestamptz;
  v_period interval := public.quest_period('EVENT');
  v_base   int;
  v_due    int;
  v_first  int;
  v_last   int;
  v_pool   jsonb := public.event_quest_pool();
  v_pick   jsonb;
begin
  if not public.is_halloween() then
    return;
  end if;

  v_start := public.halloween_start();
  v_base  := extract(year from v_start at time zone 'Asia/Seoul')::int * 100;
  v_due   := floor(extract(epoch from now() - v_start) / extract(epoch from v_period))::int;
  v_first := case when public.event_launch() <= v_start then 0
                  else floor(extract(epoch from public.event_launch() - v_start)
                             / extract(epoch from v_period))::int end;

  select coalesce(max(q.slot), v_base - 1) into v_last
    from public.quests q
   where q.uid = p_uid and q.category = 'EVENT' and q.slot >= v_base and q.slot < v_base + 100;

  for k in greatest(v_last - v_base + 1, v_first, v_due - 9) .. v_due loop
    v_pick := v_pool -> floor(random() * jsonb_array_length(v_pool))::int;
    insert into public.quests (uid, category, slot, kind, target,
                               reward_type, reward_amount, created_at)
    values (p_uid, 'EVENT', v_base + k, v_pick ->> 0, (v_pick ->> 1)::int,
            v_pick ->> 2, (v_pick ->> 3)::int, v_start + v_period * k)
    on conflict do nothing;
  end loop;

  delete from public.quests q
   where q.uid = p_uid and q.category = 'EVENT'
     and q.slot not in (
       select q2.slot from public.quests q2
        where q2.uid = p_uid and q2.category = 'EVENT'
        order by q2.slot desc
        limit 10);
end;
$$;

revoke all on function public.generate_event_quests(uuid) from public, anon, authenticated;

-- 내 퀘스트 목록 — 이벤트 퀘스트를 더했다 (0049 와 나머지는 같다)
--   이벤트 퀘스트는 이번 할로윈 것만 준다. next.EVENT 는 다음 이벤트 퀘스트 시각
--   (할로윈이 아니거나 이번 할로윈에 더 없으면 null). halloween 은 지금이 할로윈 기간인지
create or replace function public.my_quests()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_anchor timestamptz;
  v_hw     boolean := public.is_halloween();
  v_start  timestamptz := public.halloween_start();
  v_enext  timestamptz := null;
begin
  select pf.created_at into v_anchor from public.profiles pf where pf.uid = v_uid;
  if not found then
    raise exception '로그인이 필요합니다.';
  end if;

  perform public.generate_quests(v_uid);
  perform public.generate_event_quests(v_uid);

  if v_hw then
    v_enext := v_start + public.quest_period('EVENT') * (
                 floor(extract(epoch from now() - v_start)
                       / extract(epoch from public.quest_period('EVENT')))::int + 1);
    if not public.is_halloween_at(v_enext) then
      v_enext := null;
    end if;
  end if;

  return json_build_object(
    'quests', coalesce((
      select json_agg(json_build_object(
               'id',           q.id,
               'category',     q.category,
               'role',         q.role,
               'difficulty',   q.difficulty,
               'kind',         q.kind,
               'target',       q.target,
               'progress',     least(q.target,
                                     public.quest_progress(v_uid, q.kind, q.created_at, q.role)),
               'rewardType',   q.reward_type,
               'rewardAmount', q.reward_amount,
               'createdAt',    q.created_at,
               'claimed',      q.claimed_at is not null)
             order by q.slot desc)
        from public.quests q
       where q.uid = v_uid
         and (q.category <> 'EVENT' or (v_hw and q.created_at >= v_start))), '[]'::json),
    'next', (
      select json_object_agg(c, v_anchor + public.quest_period(c) * (
               floor(extract(epoch from now() - v_anchor)
                     / extract(epoch from public.quest_period(c)))::int + 1))
        from unnest(array['MAIN', 'DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY', 'ROLE']) c
    )::jsonb || jsonb_build_object('EVENT', v_enext),
    'halloween', v_hw
  );
end;
$$;

grant execute on function public.my_quests() to authenticated;

-- 보상 받기 — 이벤트 퀘스트는 그 기간에만 받는다 (0049 와 나머지는 같다)
create or replace function public.claim_quest(p_quest_id bigint)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_q   public.quests%rowtype;
begin
  select * into v_q from public.quests q
   where q.id = p_quest_id and q.uid = v_uid
   for update;
  if not found then
    raise exception '없는 퀘스트입니다.';
  end if;
  if v_q.claimed_at is not null then
    raise exception '이미 보상을 받았습니다.';
  end if;
  if v_q.category = 'EVENT'
     and not (public.is_halloween() and v_q.created_at >= public.halloween_start()) then
    raise exception '이벤트 기간이 끝났습니다.';
  end if;
  if public.quest_progress(v_uid, v_q.kind, v_q.created_at, v_q.role) < v_q.target then
    raise exception '아직 퀘스트를 깨지 못했습니다.';
  end if;

  update public.quests q set claimed_at = now() where q.id = v_q.id;
  insert into public.quest_clears (uid, quest_id) values (v_uid, v_q.id);

  update public.profiles pf
     set stars = pf.stars + case when v_q.reward_type = 'STAR' then v_q.reward_amount else 0 end,
         gems  = pf.gems  + case when v_q.reward_type = 'GEM'  then v_q.reward_amount else 0 end,
         coins = pf.coins + case when v_q.reward_type = 'COIN' then v_q.reward_amount else 0 end
   where pf.uid = v_uid;

  return json_build_object('rewardType', v_q.reward_type, 'rewardAmount', v_q.reward_amount);
end;
$$;

grant execute on function public.claim_quest(bigint) to authenticated;
