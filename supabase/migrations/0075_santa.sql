-- ============================================================
-- 마피아 게임 · 크리스마스 한정 직업 산타 (Santa) · 트리 성 · 겨울 퀘스트 "산타로 15승"
-- ============================================================
-- 크리스마스 기간 — 해마다 12월 15일부터 12월 31일이 끝날 때까지 (한국 시간). 겨울 기간 안에 있다.
--   is_christmas() 로 본다. 화면은 theme.js 의 christmas.
--
-- 산타 — 중립 진영. 크리스마스 기간에만 나온다 (마녀처럼 그 기간에만 대기실에서 켜고 끈다).
--   · 랜덤 구성에서만 나온다. 중립 후보에 들어간다.
--   · 밤마다 다른 한 명에게 선물을 보낼 수 있다 (GIFT). 오늘은 보내지 않아도 된다.
--     같은 사람에게는 한 번만 보낸다. 선물은 여섯 가지 중 하나가 무작위로 나온다.
--       좋은 선물  BOMB1    1턴 남은 폭탄 — 3번째 턴 폭탄. 다음 밤에 넘기면 받은 사람이, 안 넘기면 본인이 터진다
--                 SHIELD   보호막       — 그 밤의 공격(마피아·살인자·마녀·자경단·보안관·선물 제거)을 막는다
--                 KILL_ON  제거 가능     — 다음 밤에 한 명을 제거할 수 있다 (GIFT_KILL, 치료·경호에 막힌다).
--                                        투표하는 마피아는 그대로(효과 없음), 폭탄광·시민·중립은 제거할 수 있다
--       나쁜 선물  BOMB0    0턴 폭탄      — 바로 터져 죽는다. 치료·보호·보호막으로 막을 수 없다
--                 REVEAL   강제 진영 공개 — 다음 아침 모두에게 진짜 진영을 공개한다
--                 KILL_OFF 제거 불가     — 다음 밤에 제거하지 못한다. 마피아 진영이면 마피아 제거 전체가 막힌다.
--                                        살인자·마녀·자경단·보안관은 자기 제거가, 선물 제거도 막힌다
--   · 선물 3개를 보내면(밤이 끝날 때 살아 있으면) 즉시 단독 승리 (rooms.winner = 'SANTA').
--   · XP 를 받지 않는다 (base_xp 의 그 밖 = 0). 승리 코인은 받는다.
--
-- 상점 — 트리 성(CASTLE_TREE, 별 50)을 크리스마스 기간에 판다. 해마다 다시 나온다.
-- 겨울 이벤트 퀘스트 — 세 번째 퀘스트 SANTA_WIN "산타로 15승", 보상 트리 성 (이미 있으면 별 25).
--   0073 에서 quests_kind_check 에 WINTER_WIN·WINTER_KILL 을 빠뜨려 겨울 퀘스트를 만들 수 없던 것도 고친다.
-- ============================================================

-- ------------------------------------------------------------
-- 1. 스키마 확장
-- ------------------------------------------------------------

alter table public.private_roles drop constraint if exists private_roles_role_check;
alter table public.private_roles add constraint private_roles_role_check
  check (role in ('CITIZEN','MAFIA','POLICE','DOCTOR','BODYGUARD',
                  'DETECTIVE','REPORTER','MEDIUM','SPY','JESTER','ASSASSIN','KILLER',
                  'VIGILANTE','SHERIFF','FORGER','SURVIVOR','WITCH','BOMBER','SANTA'));

alter table public.night_actions drop constraint if exists night_actions_action_check;
alter table public.night_actions add constraint night_actions_action_check
  check (action in ('MAFIA_VOTE','DOCTOR','BODYGUARD','POLICE',
                    'DETECTIVE','REPORTER','MEDIUM','ASSASSIN','KILLER','VIGILANTE',
                    'SHERIFF','FORGE','WITCH','BOMB','BOMB_PASS','GIFT','GIFT_KILL'));

alter table public.rooms drop constraint if exists rooms_winner_check;
alter table public.rooms add constraint rooms_winner_check
  check (winner is null or winner in ('CITIZEN', 'MAFIA', 'JESTER', 'KILLER',
                                      'SURVIVOR', 'WITCH', 'SANTA', 'DRAW'));

alter table public.private_results drop constraint if exists private_results_kind_check;
alter table public.private_results add constraint private_results_kind_check
  check (kind in ('POLICE','DOCTOR','BODYGUARD','DETECTIVE',
                  'REPORTER','MEDIUM','SPY','ASSASSIN','GIFT','GIFT_SENT'));

alter table public.quests drop constraint if exists quests_kind_check;
alter table public.quests add constraint quests_kind_check
  check (kind in ('WIN', 'STREAK', 'KILL', 'SURVIVE', 'PLAY', 'CLEAR',
                  'FIND_MAFIA', 'INVESTIGATE', 'HEAL', 'GUARD', 'REPORT', 'REPORT_MAFIA',
                  'SEANCE', 'DIE', 'KILL_MAFIA', 'KILL_NEUTRAL', 'IDENTIFY',
                  'FORGE', 'FORGE_HIT', 'VOTES', 'DUEL',
                  'PUMPKIN_BOX', 'WITCH_WIN', 'HALLOWEEN_WIN',
                  'WINTER_WIN', 'WINTER_KILL', 'SANTA_WIN'));

-- 보상이 프로필인 퀘스트 (AVATAR). reward_item 은 물건 id
alter table public.quests drop constraint if exists quests_reward_type_check;
alter table public.quests add constraint quests_reward_type_check
  check (reward_type in ('STAR', 'GEM', 'COIN', 'AVATAR'));
alter table public.quests add column if not exists reward_item text;

-- 산타의 선물. day_number 는 보낸 밤. 제거 가능·제거 불가는 그 다음 밤(day_number + 1)에 쓰인다
create table if not exists public.gifts (
  id         bigserial primary key,
  room_id    uuid not null references public.rooms(id) on delete cascade,
  santa_uid  uuid not null,
  target_uid uuid not null,
  gift       text not null check (gift in ('BOMB1', 'SHIELD', 'KILL_ON', 'BOMB0', 'REVEAL', 'KILL_OFF')),
  day_number int  not null,
  created_at timestamptz not null default now()
);
create index if not exists gifts_room_idx on public.gifts (room_id, target_uid, day_number);
-- 서버 함수만 읽고 쓴다
alter table public.gifts enable row level security;
revoke all on public.gifts from anon, authenticated;

-- 트리 성. 크리스마스 기간(12월 15일 ~ 12월 31일)에 판다
insert into public.shop_items (id, kind, price_type, price, sale_from, sale_until, repeat_yearly, sort) values
  ('CASTLE_TREE', 'AVATAR', 'STAR', 50, '2026-12-15 00:00:00+09', '2027-01-01 00:00:00+09', true, 6)
on conflict (id) do nothing;

-- ------------------------------------------------------------
-- 2. 크리스마스 기간과 산타 도우미
-- ------------------------------------------------------------

-- 그 시각이 크리스마스 기간인지 (한국 시간 12월 15일 ~ 12월 31일)
create or replace function public.is_christmas_at(p_ts timestamptz)
returns boolean
language sql
stable
as $$
  select p_ts >= timestamptz '2026-12-15 00:00:00+09'
     and extract(month from p_ts at time zone 'Asia/Seoul') = 12
     and extract(day from p_ts at time zone 'Asia/Seoul') >= 15;
$$;

-- 지금이 크리스마스 기간인지. 크리스마스에만 여는 직업·물건은 이 함수로 기간을 본다
create or replace function public.is_christmas()
returns boolean
language sql
stable
as $$
  select public.is_christmas_at(now());
$$;

-- 산타가 이기려면 보내야 하는 선물 수
create or replace function public.santa_goal()
returns int
language sql
immutable
as $$
  select 3;
$$;

-- 산타가 지금까지 보낸 선물 수
create or replace function public.santa_gifts(p_room_id uuid, p_uid uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int from public.gifts g
   where g.room_id = p_room_id and g.santa_uid = p_uid;
$$;

-- 그 밤(p_day)에 쓰이는 선물을 받았는지 — 전날 밤에 받은 것
create or replace function public.has_gift(p_room_id uuid, p_uid uuid, p_gift text, p_day int)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.gifts g
     where g.room_id = p_room_id and g.target_uid = p_uid
       and g.gift = p_gift and g.day_number = p_day - 1);
$$;

-- 그 밤에 마피아 제거가 막혔는지 — 살아 있는 마피아 진영 누군가가 제거 불가를 받았다
create or replace function public.mafia_kill_blocked(p_room_id uuid, p_day int)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.gifts g
      join public.private_roles pr on pr.room_id = g.room_id and pr.uid = g.target_uid
      join public.players pl       on pl.room_id = g.room_id and pl.uid = g.target_uid
     where g.room_id = p_room_id and g.gift = 'KILL_OFF' and g.day_number = p_day - 1
       and pr.team = 'MAFIA' and pl.alive = true);
$$;

-- 그 밤에 이 사람의 제거가 막혔는지. 자기가 제거 불가를 받았거나, 투표하는 마피아인데 마피아 제거가 막혔다
create or replace function public.kill_blocked(p_room_id uuid, p_uid uuid, p_day int)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.has_gift(p_room_id, p_uid, 'KILL_OFF', p_day)
      or coalesce((select pr.team = 'MAFIA' and pr.role <> 'BOMBER'
                     from public.private_roles pr
                    where pr.room_id = p_room_id and pr.uid = p_uid), false)
         and public.mafia_kill_blocked(p_room_id, p_day);
$$;

-- 그 밤에 선물(제거 가능)로 제거할 수 있는지. 투표하는 마피아는 원래 제거하므로 그대로다
create or replace function public.can_gift_kill(p_room_id uuid, p_uid uuid, p_day int)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.has_gift(p_room_id, p_uid, 'KILL_ON', p_day)
     and not public.kill_blocked(p_room_id, p_uid, p_day)
     and not coalesce((select pr.team = 'MAFIA' and pr.role <> 'BOMBER'
                         from public.private_roles pr
                        where pr.room_id = p_room_id and pr.uid = p_uid), false);
$$;

-- 산타 승리 판정 (내부용). 살아 있는 산타가 선물을 다 보냈으면 'SANTA'
create or replace function public.check_santa_gifts(p_room_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case when exists (
    select 1 from public.private_roles pr
      join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
     where pr.room_id = p_room_id and pr.role = 'SANTA' and pl.alive = true
       and public.santa_gifts(p_room_id, pr.uid) >= public.santa_goal()) then 'SANTA' end;
$$;

revoke all on function public.santa_gifts(uuid, uuid)                from public, anon, authenticated;
revoke all on function public.has_gift(uuid, uuid, text, int)        from public, anon, authenticated;
revoke all on function public.mafia_kill_blocked(uuid, int)          from public, anon, authenticated;
revoke all on function public.kill_blocked(uuid, uuid, int)          from public, anon, authenticated;
revoke all on function public.can_gift_kill(uuid, uuid, int)         from public, anon, authenticated;
revoke all on function public.check_santa_gifts(uuid)                from public, anon, authenticated;

-- ------------------------------------------------------------
-- 3. 진영과 목록 — 산타를 더했다 (0074 와 나머지는 같다)
-- ------------------------------------------------------------

create or replace function public.team_of(p_role text)
returns text
language sql
immutable
as $$
  select case
    when p_role in ('MAFIA', 'SPY', 'ASSASSIN', 'FORGER', 'BOMBER') then 'MAFIA'
    when p_role in ('JESTER', 'KILLER', 'SURVIVOR', 'WITCH', 'SANTA') then 'NEUTRAL'
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
               'VIGILANTE', 'SHERIFF', 'FORGER', 'SURVIVOR', 'WITCH', 'BOMBER', 'SANTA', 'CITIZEN'];
$$;

create or replace function public.special_roles()
returns text[]
language sql
immutable
as $$
  select array['POLICE', 'DOCTOR', 'BODYGUARD', 'DETECTIVE', 'REPORTER', 'MEDIUM',
               'VIGILANTE', 'SHERIFF', 'SPY', 'ASSASSIN', 'FORGER', 'BOMBER',
               'JESTER', 'KILLER', 'SURVIVOR', 'WITCH', 'SANTA'];
$$;

create or replace function public.night_actor_roles()
returns text[]
language sql
immutable
as $$
  select array['MAFIA', 'SPY', 'ASSASSIN', 'FORGER', 'BOMBER', 'POLICE', 'DOCTOR', 'BODYGUARD',
               'DETECTIVE', 'REPORTER', 'MEDIUM', 'KILLER', 'VIGILANTE', 'SHERIFF', 'WITCH', 'SANTA'];
$$;

-- ------------------------------------------------------------
-- 4. 랜덤 구성 — 중립 후보에 산타를 더했다 (0074 와 나머지는 같다)
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
    from unnest(array['JESTER', 'KILLER', 'SURVIVOR', 'WITCH', 'SANTA']) x
   where not (x = any (off));
  v_neutral := least(v_neutral, v_open);

  -- 마피아가 꺼져 있으면 마피아 진영은 켜진 스파이·암살자·위조범·폭탄광 수만큼만 채운다.
  -- 남는 자리는 시민 진영으로 간다. 0명이면 시작할 수 없다 (assign_roles).
  if 'MAFIA' = any (off) then
    select coalesce(sum(public.role_max_of(p_max, x)), 0) into v_mopen
      from unnest(array['SPY', 'ASSASSIN', 'FORGER', 'BOMBER']) x
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
      select x from public.role_pool(array['SPY', 'ASSASSIN', 'FORGER', 'BOMBER'], off, p_max) x
       order by random() limit v_m);
  else
    v_out := v_out || 'MAFIA'::text;
    if v_m > 1 then
      v_pool := array(select x from public.role_pool(array['SPY', 'ASSASSIN', 'FORGER', 'BOMBER'], off, p_max) x)
                || array_fill('MAFIA'::text, array[v_m - 1]);
      v_out := v_out || array(select x from unnest(v_pool) x order by random() limit v_m - 1);
    end if;
  end if;

  -- 중립: 켜진 중립 직업 중에서 (자리 수는 이미 켜진 직업 수 이하)
  if v_n > 0 then
    v_out := v_out || array(
      select x from public.role_pool(array['JESTER', 'KILLER', 'SURVIVOR', 'WITCH', 'SANTA'], off, p_max) x
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
-- 5. 직업 배정 — 크리스마스가 아니면 산타를 빼고, 지난 판 선물을 지운다 (0074 와 나머지는 같다)
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
  -- 같은 방의 지난 판 폭탄을 지운다
  delete from public.bombs b where b.room_id = p_room_id;
  delete from public.gifts g where g.room_id = p_room_id;

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

  -- 산타는 크리스마스 기간에만 나온다
  if not public.is_christmas() then
    v_off := coalesce(v_off, '{}') || 'SANTA'::text;
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
-- 6. 승리와 킬 수 — 산타를 더했다
--   player_won 은 0071, kills_of 는 0074 와 나머지는 같다.
--   kills_of: 누구든 선물(제거 가능)로 제거한 사람도 킬로 센다.
-- ------------------------------------------------------------

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
    when p_winner = 'SANTA' then p_role = 'SANTA' and p_alive
      and public.santa_gifts(p_room_id, p_uid) >= public.santa_goal()
    else false
  end;
$$;

revoke all on function public.player_won(uuid, text, uuid, text, text, boolean) from public, anon, authenticated;

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
  elsif p_role = 'BOMBER' then
    select count(*) into v
      from public.bombs b
     where b.room_id = p_room_id and b.bomber_uid = p_uid and b.exploded_uid is not null;
  elsif p_role = 'ASSASSIN' then
    select count(*) into v
      from public.assassinations a
     where a.room_id = p_room_id and a.actor_uid = p_uid
       and a.resolved = true and a.success;
  end if;

  -- 산타의 선물(제거 가능)로 제거한 사람
  return coalesce(v, 0) + (
    select count(*)::int
      from public.night_actions n
     where n.room_id = p_room_id and n.actor_uid = p_uid
       and n.action = 'GIFT_KILL' and n.target_uid is not null
       and public.died_at_night(p_room_id, n.day_number, n.target_uid));
end;
$$;

revoke all on function public.kills_of(uuid, uuid, text) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 7. 밤 완료 — 산타·선물을 더했다 (0074 와 나머지는 같다)
--   제거 불가를 받은 사람(마피아 진영이면 투표하는 마피아 모두)은 오늘 밤 할 일이 없다.
--   제거 가능을 받은 사람은 직업 행동과 따로 선물 제거(사용하지 않기 포함)를 내야 한다.
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
  v_holders   int;
  v_passed    int;
  v_mblock    boolean := public.mafia_kill_blocked(p_room_id, p_day);
  v_gholders  int;
  v_gacted    int;
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
     and not (pr.role in ('REPORTER', 'VIGILANTE') and pl.ability_used = true)
     -- 사망자가 없으면 영매는 능력을 쓸 수 없다 (§2.8)
     and not (pr.role = 'MEDIUM' and v_dead = 0)
     -- 준 폭탄이 아직 돌고 있으면 폭탄광은 새 폭탄을 줄 수 없다
     and not (pr.role = 'BOMBER' and public.has_live_bomb(p_room_id, pr.uid))
     -- 산타의 선물(제거 불가): 투표하는 마피아는 모두, 혼자 제거하는 직업은 받은 사람만 쉰다
     and not (v_mblock and pr.role in ('MAFIA', 'SPY', 'ASSASSIN', 'FORGER'))
     and not (pr.role in ('KILLER', 'WITCH', 'VIGILANTE', 'SHERIFF')
              and public.kill_blocked(p_room_id, pr.uid, p_day));

  -- 행동한 사람 수를 센다. 선택 행동인 위조와 따로 세는 폭탄 넘기기는 제외한다.
  select count(distinct n.actor_uid) into v_submitted
    from public.night_actions n
    join public.players pl on pl.room_id = n.room_id and pl.uid = n.actor_uid
   where n.room_id = p_room_id
     and n.day_number = p_day
     and n.action not in ('FORGE', 'BOMB_PASS', 'GIFT_KILL')
     and pl.alive = true;

  -- 폭탄을 가진 사람이 모두 넘기기를 냈는지
  select count(distinct b.holder_uid),
         count(distinct b.holder_uid) filter (where exists (
           select 1 from public.night_actions n
            where n.room_id = p_room_id and n.day_number = p_day
              and n.actor_uid = b.holder_uid and n.action = 'BOMB_PASS'))
    into v_holders, v_passed
    from public.bombs b
    join public.players pl on pl.room_id = b.room_id and pl.uid = b.holder_uid
   where b.room_id = p_room_id and b.active and pl.alive = true;

  -- 선물(제거 가능)을 받은 사람이 모두 선물 제거를 냈는지
  select count(*),
         count(*) filter (where exists (
           select 1 from public.night_actions n
            where n.room_id = p_room_id and n.day_number = p_day
              and n.actor_uid = pl.uid and n.action = 'GIFT_KILL'))
    into v_gholders, v_gacted
    from public.players pl
   where pl.room_id = p_room_id and pl.alive = true
     and public.can_gift_kill(p_room_id, pl.uid, p_day);

  return v_submitted >= v_expected and v_passed >= v_holders and v_gacted >= v_gholders;
end;
$$;

revoke all on function public.night_is_complete(uuid, int) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 8. 밤 행동 제출 — 선물 주기(GIFT)·선물 제거(GIFT_KILL)와 제거 불가를 더했다 (0074 와 나머지는 같다)
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
    -- 폭탄광은 마피아 진영이지만 제거 투표에 참여하지 않는다
    if public.team_of(v_role) <> 'MAFIA' or v_role = 'BOMBER' then
      raise exception '사용할 수 없는 능력입니다.';
    end if;
  elsif p_action = 'GIFT_KILL' then
    -- 선물(제거 가능)은 직업과 상관없이 받은 사람이 한다
    if not public.can_gift_kill(p_room_id, v_uid, v_room.day_number) then
      raise exception '사용할 수 없는 능력입니다.';
    end if;
  elsif p_action = 'BOMB_PASS' then
    -- 폭탄 넘기기는 직업과 상관없이 폭탄을 가진 사람이 한다
    if not exists (select 1 from public.bombs b
                    where b.room_id = p_room_id and b.holder_uid = v_uid and b.active) then
      raise exception '폭탄을 가지고 있지 않습니다.';
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
      when 'BOMB'      then 'BOMBER'
      when 'GIFT'      then 'SANTA'
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

  -- 산타의 선물(제거 불가): 오늘 밤은 제거할 수 없다
  if p_action in ('MAFIA_VOTE', 'KILLER', 'WITCH', 'VIGILANTE', 'SHERIFF')
     and public.kill_blocked(p_room_id, v_uid, v_room.day_number) then
    raise exception '산타의 선물로 오늘 밤은 제거할 수 없습니다.';
  end if;

  -- 폭탄은 한 번에 하나만. 준 폭탄이 터지거나 사라져야 새로 줄 수 있다
  if p_action = 'BOMB' and public.has_live_bomb(p_room_id, v_uid) then
    raise exception '폭탄이 아직 돌고 있어 새 폭탄을 줄 수 없습니다.';
  end if;

  if p_target_uid is null then
    if p_action not in ('REPORTER', 'VIGILANTE', 'SHERIFF', 'WITCH', 'BOMB', 'BOMB_PASS',
                        'GIFT', 'GIFT_KILL') then
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

    if p_action in ('MAFIA_VOTE', 'BODYGUARD', 'KILLER', 'VIGILANTE', 'SHERIFF', 'WITCH',
                    'BOMB', 'BOMB_PASS', 'GIFT', 'GIFT_KILL')
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

    -- 산타는 한 사람에게 한 번만 선물한다
    if p_action = 'GIFT' and exists (
      select 1 from public.gifts g
       where g.room_id = p_room_id and g.santa_uid = v_uid and g.target_uid = p_target_uid) then
      raise exception '이미 선물을 보낸 사람입니다.';
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
-- 9. 밤 처리 — 산타의 선물을 더했다 (0074 와 나머지는 같다)
--   선물은 밤 처리 맨 앞에서 열어 보호막이 오늘 밤 공격을 막게 한다.
--   제거 가능·제거 불가는 다음 밤에 쓰인다 (gifts.day_number = 그 밤 - 1).
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
  v_bgives    jsonb := '[]'::jsonb;
  v_bpasses   jsonb := '[]'::jsonb;
  v_gifts     jsonb := '[]'::jsonb;
  v_gshield   uuid[] := '{}';
  v_gktargets uuid[] := '{}';
  v_greveal   jsonb := '[]'::jsonb;
  v_mblock    boolean;
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

  -- 1-1. 산타의 선물(제거 불가)을 마피아 진영이 받았으면 오늘 밤 마피아는 제거하지 못한다
  v_mblock := public.mafia_kill_blocked(p_room_id, v_day);
  if v_mblock then
    v_target := null;
  end if;

  -- 1-2. 산타의 선물 (§2.18). 산타마다 한 명에게, 여섯 가지 중 하나를 무작위로.
  --   같은 산타가 이미 선물한 사람에게는 다시 보내지 않는다
  with picked as (
    insert into public.gifts (room_id, santa_uid, target_uid, gift, day_number)
    select p_room_id, n.actor_uid, n.target_uid,
           (array['BOMB1', 'SHIELD', 'KILL_ON', 'BOMB0', 'REVEAL', 'KILL_OFF'])[1 + floor(random() * 6)::int],
           v_day
      from public.night_actions n
      join public.private_roles pr on pr.room_id = n.room_id and pr.uid = n.actor_uid
      join public.players pl       on pl.room_id = n.room_id and pl.uid = n.actor_uid
      join public.players tp       on tp.room_id = n.room_id and tp.uid = n.target_uid
     where n.room_id = p_room_id and n.day_number = v_day
       and n.action = 'GIFT' and pr.role = 'SANTA'
       and pl.alive = true and tp.alive = true
       and n.target_uid is not null and n.target_uid <> n.actor_uid
       and not exists (select 1 from public.gifts g
                        where g.room_id = p_room_id and g.santa_uid = n.actor_uid
                          and g.target_uid = n.target_uid)
    returning santa_uid, target_uid, gift
  )
  select coalesce(jsonb_agg(jsonb_build_object('s', santa_uid, 't', target_uid, 'g', gift)), '[]'::jsonb)
    into v_gifts
    from picked;

  select coalesce(array_agg((e ->> 't')::uuid), '{}') into v_gshield
    from jsonb_array_elements(v_gifts) e where e ->> 'g' = 'SHIELD';

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
     and not public.kill_blocked(p_room_id, n.actor_uid, v_day)
     and pl.alive = true and n.target_uid is not null;

  -- 2-2-1. 마녀 공격 대상. 살인자와 같이 마녀마다 혼자 정한다
  select coalesce(array_agg(n.target_uid), '{}') into v_wtargets
    from public.night_actions n
    join public.private_roles pr on pr.room_id = n.room_id and pr.uid = n.actor_uid
    join public.players pl       on pl.room_id = n.room_id and pl.uid = n.actor_uid
   where n.room_id = p_room_id and n.day_number = v_day
     and n.action = 'WITCH' and pr.role = 'WITCH'
     and not public.kill_blocked(p_room_id, n.actor_uid, v_day)
     and pl.alive = true and n.target_uid is not null;

  -- 2-3. 자경단 공격 대상. 게임 중 한 번뿐이라 쏘는 순간 기회를 쓴다.
  select coalesce(array_agg(n.actor_uid), '{}'), coalesce(array_agg(n.target_uid), '{}')
    into v_vactors, v_vtargets
    from public.night_actions n
    join public.private_roles pr on pr.room_id = n.room_id and pr.uid = n.actor_uid
    join public.players pl       on pl.room_id = n.room_id and pl.uid = n.actor_uid
   where n.room_id = p_room_id and n.day_number = v_day
     and n.action = 'VIGILANTE' and pr.role = 'VIGILANTE'
     and not public.kill_blocked(p_room_id, n.actor_uid, v_day)
     and pl.alive = true and pl.ability_used = false
     and n.target_uid is not null;

  update public.players pl
     set ability_used = true
   where pl.room_id = p_room_id and pl.uid = any (v_vactors);

  -- 2-3-1. 폭탄 주기·넘기기. 오늘 밤 죽더라도 살아서 낸 행동이므로 먼저 모아 둔다
  select coalesce(jsonb_agg(jsonb_build_object('b', n.actor_uid, 't', n.target_uid)), '[]'::jsonb)
    into v_bgives
    from public.night_actions n
    join public.private_roles pr on pr.room_id = n.room_id and pr.uid = n.actor_uid
    join public.players pl       on pl.room_id = n.room_id and pl.uid = n.actor_uid
   where n.room_id = p_room_id and n.day_number = v_day
     and n.action = 'BOMB' and pr.role = 'BOMBER'
     and pl.alive = true and n.target_uid is not null
     and not public.has_live_bomb(p_room_id, n.actor_uid);

  select coalesce(jsonb_agg(jsonb_build_object('h', n.actor_uid, 't', n.target_uid)), '[]'::jsonb)
    into v_bpasses
    from public.night_actions n
    join public.players pl on pl.room_id = n.room_id and pl.uid = n.actor_uid
   where n.room_id = p_room_id and n.day_number = v_day
     and n.action = 'BOMB_PASS' and pl.alive = true and n.target_uid is not null;

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
     and not public.kill_blocked(p_room_id, n.actor_uid, v_day)
     and pl.alive = true and n.target_uid is not null;

  -- 2-5. 산타의 선물(제거 가능)로 제거. 살인자와 같이 치료·경호에 막힌다
  select coalesce(array_agg(n.target_uid), '{}') into v_gktargets
    from public.night_actions n
    join public.players pl on pl.room_id = n.room_id and pl.uid = n.actor_uid
   where n.room_id = p_room_id and n.day_number = v_day
     and n.action = 'GIFT_KILL' and pl.alive = true and n.target_uid is not null
     and public.can_gift_kill(p_room_id, n.actor_uid, v_day);

  -- 공격 목록: 마피아 -> 살인자 -> 마녀 -> 자경단 -> 보안관 -> 선물 제거. 같은 사람을 노렸으면 한 번만 친다.
  if v_target is not null then
    v_attacks := v_attacks || v_target;
  end if;
  foreach v_t in array v_ktargets || v_wtargets || v_vtargets || v_stargets || v_gktargets loop
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

    -- 산타의 선물(보호막)도 치료처럼 오늘 밤 공격을 막는다
    v_saved := v_t = any (v_healed) or v_t = any (v_gshield);
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

  -- 5-2-0. 산타의 선물(0턴 폭탄) — 바로 터진다. 치료·보호·보호막으로 막을 수 없다
  with d as (
    update public.players pl
       set alive = false
     where pl.room_id = p_room_id and pl.alive = true
       and pl.uid in (select (e ->> 't')::uuid from jsonb_array_elements(v_gifts) e
                       where e ->> 'g' = 'BOMB0')
    returning pl.uid
  )
  select coalesce(array_agg(d.uid), '{}') into v_died from d;
  v_deaths := v_deaths || v_died;

  -- 5-2-1. 폭탄 (§2.17). 치료·보호로 막을 수 없다.
  --   넘기기 -> 가진 사람이 죽었으면 사라짐 -> 턴 +1, 4번째 턴이면 가진 사람이 터져 죽음 -> 새 폭탄
  update public.bombs b
     set holder_uid = (e ->> 't')::uuid
    from jsonb_array_elements(v_bpasses) e
   where b.room_id = p_room_id and b.active and b.holder_uid = (e ->> 'h')::uuid;

  update public.bombs b
     set active = false
    from public.players pl
   where b.room_id = p_room_id and b.active
     and pl.room_id = b.room_id and pl.uid = b.holder_uid and pl.alive = false;

  update public.bombs b
     set turn = b.turn + 1
   where b.room_id = p_room_id and b.active;

  with boom as (
    update public.bombs b
       set active = false, exploded_uid = b.holder_uid, exploded_day = v_day
     where b.room_id = p_room_id and b.active and b.turn >= 4
    returning b.holder_uid
  ), d as (
    update public.players pl
       set alive = false
     where pl.room_id = p_room_id and pl.alive = true
       and pl.uid in (select boom.holder_uid from boom)
    returning pl.uid
  )
  select coalesce(array_agg(d.uid), '{}') into v_died from d;
  v_deaths := v_deaths || v_died;

  insert into public.bombs (room_id, bomber_uid, holder_uid, turn, given_day)
  select p_room_id, (e ->> 'b')::uuid, (e ->> 't')::uuid, 1, v_day
    from jsonb_array_elements(v_bgives) e
    join public.players pl on pl.room_id = p_room_id and pl.uid = (e ->> 't')::uuid
   where pl.alive = true;

  -- 산타의 선물(1턴 남은 폭탄) — 3번째 턴으로 준다. 다음 밤에 넘기면 받은 사람이, 안 넘기면 본인이 터진다
  insert into public.bombs (room_id, bomber_uid, holder_uid, turn, given_day)
  select p_room_id, (e ->> 's')::uuid, (e ->> 't')::uuid, 3, v_day
    from jsonb_array_elements(v_gifts) e
    join public.players pl on pl.room_id = p_room_id and pl.uid = (e ->> 't')::uuid
   where e ->> 'g' = 'BOMB1' and pl.alive = true;

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

  -- 9-1. 산타의 선물 결과. 받은 사람에게 선물을, 산타에게 보낸 선물을 알린다.
  --   강제 진영 공개는 아침에 모두에게 진짜 진영을 보여준다 (위조와 상관없다)
  insert into public.private_results (room_id, uid, day_number, kind, payload)
  select p_room_id, (e ->> 't')::uuid, v_day, 'GIFT',
         jsonb_build_object('gifts', jsonb_agg(e ->> 'g'))
    from jsonb_array_elements(v_gifts) e
   group by (e ->> 't')
  on conflict (room_id, uid, day_number, kind) do update set payload = excluded.payload;

  insert into public.private_results (room_id, uid, day_number, kind, payload)
  select p_room_id, (e ->> 's')::uuid, v_day, 'GIFT_SENT',
         jsonb_build_object('targetUid', e ->> 't', 'targetNickname', tp.nickname, 'gift', e ->> 'g')
    from jsonb_array_elements(v_gifts) e
    join public.players tp on tp.room_id = p_room_id and tp.uid = (e ->> 't')::uuid
  on conflict (room_id, uid, day_number, kind) do update set payload = excluded.payload;

  select coalesce(jsonb_agg(jsonb_build_object(
           'targetUid', tp.uid, 'targetNickname', tp.nickname, 'team', tgt.team)), '[]'::jsonb)
    into v_greveal
    from public.players tp
    join public.private_roles tgt on tgt.room_id = tp.room_id and tgt.uid = tp.uid
   where tp.room_id = p_room_id
     and tp.uid in (select (e ->> 't')::uuid from jsonb_array_elements(v_gifts) e
                     where e ->> 'g' = 'REVEAL');

  -- 공개 결과 — 사망자, 취재 성공분, 선물로 공개된 진영. 사인은 구분하지 않는다.
  insert into public.public_results (room_id, day_number, kind, payload)
  values (p_room_id, v_day, 'NIGHT',
          jsonb_build_object('nightDeaths', to_jsonb(v_deaths),
                             'reporterReveal', v_reveal,
                             'giftReveal', v_greveal))
  on conflict (room_id, day_number, kind) do update
    set payload = public.public_results.payload || excluded.payload;

  -- 10. 승리 조건. 마녀가 제거 퀘스트를 깼으면 즉시 승리 (다른 승리보다 먼저)
  v_winner := public.check_witch_kills(p_room_id);
  -- 산타: 선물 3개를 보내고 살아 있으면 즉시 단독 승리
  if v_winner is null then
    v_winner := public.check_santa_gifts(p_room_id);
  end if;
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
-- 10. 저격 — 폭탄광·산타도 찍을 수 있게 한다 (0071 과 나머지는 같다)
--   0074 에서 폭탄광을 빠뜨려 저격수가 폭탄광을 고르면 "직업을 선택해 주세요." 가 났다.
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
      'DETECTIVE','REPORTER','MEDIUM','SPY','JESTER','ASSASSIN','KILLER','VIGILANTE','SHERIFF','FORGER','SURVIVOR','WITCH',
      'BOMBER','SANTA') then
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
-- 11. 내 화면 정보 — 산타·선물을 더했다 (0074 와 나머지는 같다)
--   santa: { sent, goal, gifted } 산타에게만. gifted 는 이미 선물한 사람들
--   giftKill: { target, acted } 다가오는(또는 지금) 밤에 선물(제거 가능)을 쓸 수 있으면
--   giftBlocked: 다가오는(또는 지금) 밤에 선물(제거 불가)로 제거가 막혔는지
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
  v_bomber    json := null;
  v_bomb      json := null;
  v_santa     json := null;
  v_gkill     json := null;
  v_nday      int;
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
     and n.action not in ('FORGE', 'BOMB_PASS', 'GIFT_KILL');
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

  -- 폭탄광: 준 폭탄이 아직 돌고 있으면 새 폭탄을 줄 수 없다
  if v_role = 'BOMBER' then
    v_bomber := json_build_object('active', public.has_live_bomb(p_room_id, v_uid));
  end if;

  -- 내가 가진 폭탄. 여러 개면 가장 많이 간 턴을 보여준다. passed 는 오늘 밤 넘기기를 냈는지
  if v_alive then
    select json_build_object(
             'turn',  max(b.turn),
             'count', count(*),
             'passed', v_room.phase = 'NIGHT' and exists (
                         select 1 from public.night_actions n
                          where n.room_id = p_room_id and n.day_number = v_room.day_number
                            and n.actor_uid = v_uid and n.action = 'BOMB_PASS'),
             'passTarget', (select n.target_uid from public.night_actions n
                             where v_room.phase = 'NIGHT'
                               and n.room_id = p_room_id and n.day_number = v_room.day_number
                               and n.actor_uid = v_uid and n.action = 'BOMB_PASS'))
      into v_bomb
      from public.bombs b
     where b.room_id = p_room_id and b.holder_uid = v_uid and b.active
    having count(*) > 0;
  end if;

  -- 선물이 쓰이는 밤. 밤이면 지금 밤, 낮이면 다가오는 밤
  v_nday := case when v_room.phase = 'NIGHT' then v_room.day_number else v_room.day_number + 1 end;

  if v_role = 'SANTA' then
    select json_build_object(
             'sent',   count(*),
             'goal',   public.santa_goal(),
             'gifted', coalesce(json_agg(g.target_uid), '[]'::json))
      into v_santa
      from public.gifts g
     where g.room_id = p_room_id and g.santa_uid = v_uid;
  end if;

  if v_alive and public.can_gift_kill(p_room_id, v_uid, v_nday) then
    select json_build_object(
             'target', (select n.target_uid from public.night_actions n
                         where v_room.phase = 'NIGHT'
                           and n.room_id = p_room_id and n.day_number = v_room.day_number
                           and n.actor_uid = v_uid and n.action = 'GIFT_KILL'),
             'acted',  v_room.phase = 'NIGHT' and exists (
                         select 1 from public.night_actions n
                          where n.room_id = p_room_id and n.day_number = v_room.day_number
                            and n.actor_uid = v_uid and n.action = 'GIFT_KILL'))
      into v_gkill;
  end if;

  -- 제거 투표 진행도. 폭탄광은 투표하지 않으므로 뺀다
  if v_team = 'MAFIA' then
    select count(*) into v_n_exp
      from public.private_roles pr
      join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
     where pr.room_id = p_room_id
       and pr.team = 'MAFIA'
       and pr.role <> 'BOMBER'
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
    'bomber',         v_bomber,
    'bomb',           v_bomb,
    'santa',          v_santa,
    'giftKill',       v_gkill,
    'giftBlocked',    v_alive and public.kill_blocked(p_room_id, v_uid, v_nday),
    'bombExploded',   exists (select 1 from public.bombs b
                               where b.room_id = p_room_id and b.exploded_uid = v_uid),
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
-- 12. 겨울 이벤트 퀘스트 — 세 번째 퀘스트 "산타로 15승" (보상 트리 성, 있으면 별 25)
--   보상이 프로필인 퀘스트는 reward_type = 'AVATAR', reward_item = 물건 id,
--   reward_amount = 이미 가졌을 때 대신 주는 별 수다. (0073 과 나머지는 같다)
-- ------------------------------------------------------------

create or replace function public.winter_quest_pool()
returns jsonb
language sql
immutable
as $$
  select '[["WINTER_WIN",50,"STAR",100],["WINTER_KILL",100,"STAR",90],["SANTA_WIN",15,"AVATAR",25,"CASTLE_TREE"]]'::jsonb;
$$;

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
  when 'WINTER_WIN' then
    select count(*) into v from public.game_records g
     where g.uid = p_uid and g.ended_at >= p_since and g.won
       and public.is_winter_at(g.ended_at);
  when 'WINTER_KILL' then
    select sum(g.kills) into v from public.game_records g
     where g.uid = p_uid and g.ended_at >= p_since
       and public.is_winter_at(g.ended_at);
  when 'SANTA_WIN' then
    select count(*) into v from public.game_records g
     where g.uid = p_uid and g.ended_at >= p_since and g.won and g.role = 'SANTA';
  else
    v := 0;
  end case;
  return coalesce(v, 0);
end;
$$;

revoke all on function public.quest_progress(uuid, text, timestamptz, text) from public, anon, authenticated;

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
  v_pool   jsonb;
  v_pick   jsonb;
begin
  if public.is_halloween() then
    v_start := public.halloween_start();
    v_base  := extract(year from v_start at time zone 'Asia/Seoul')::int * 100;
    v_pool  := public.event_quest_pool();
  elsif public.is_winter() then
    v_start := public.winter_start();
    v_base  := extract(year from v_start at time zone 'Asia/Seoul')::int * 100 + 50;
    v_pool  := public.winter_quest_pool();
  else
    return;
  end if;

  v_due   := floor(extract(epoch from now() - v_start) / extract(epoch from v_period))::int;
  v_first := case when public.event_launch() <= v_start then 0
                  else floor(extract(epoch from public.event_launch() - v_start)
                             / extract(epoch from v_period))::int end;

  select coalesce(max(q.slot), v_base - 1) into v_last
    from public.quests q
   where q.uid = p_uid and q.category = 'EVENT' and q.slot >= v_base and q.slot < v_base + 50;

  for k in greatest(v_last - v_base + 1, v_first, v_due - 29) .. v_due loop
    v_pick := v_pool -> floor(random() * jsonb_array_length(v_pool))::int;
    insert into public.quests (uid, category, slot, kind, target,
                               reward_type, reward_amount, reward_item, created_at)
    values (p_uid, 'EVENT', v_base + k, v_pick ->> 0, (v_pick ->> 1)::int,
            v_pick ->> 2, (v_pick ->> 3)::int, v_pick ->> 4, v_start + v_period * k)
    on conflict do nothing;
  end loop;

  delete from public.quests q
   where q.uid = p_uid and q.category = 'EVENT'
     and q.slot not in (
       select q2.slot from public.quests q2
        where q2.uid = p_uid and q2.category = 'EVENT'
        order by q2.slot desc
        limit 30);
end;
$$;

revoke all on function public.generate_event_quests(uuid) from public, anon, authenticated;

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
  v_winter boolean := public.is_winter();
  v_start  timestamptz := case when public.is_winter() then public.winter_start()
                                else public.halloween_start() end;
  v_enext  timestamptz := null;
begin
  select pf.created_at into v_anchor from public.profiles pf where pf.uid = v_uid;
  if not found then
    raise exception '로그인이 필요합니다.';
  end if;

  perform public.generate_quests(v_uid);
  perform public.generate_event_quests(v_uid);

  if v_hw or v_winter then
    v_enext := v_start + public.quest_period('EVENT') * (
                 floor(extract(epoch from now() - v_start)
                       / extract(epoch from public.quest_period('EVENT')))::int + 1);
    if not (case when v_winter then public.is_winter_at(v_enext)
                 else public.is_halloween_at(v_enext) end) then
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
               'rewardItem',   q.reward_item,
               'createdAt',    q.created_at,
               'claimed',      q.claimed_at is not null)
             order by q.slot desc)
        from public.quests q
       where q.uid = v_uid
         and (q.category <> 'EVENT' or ((v_hw or v_winter) and q.created_at >= v_start))), '[]'::json),
    'next', (
      select json_object_agg(c, v_anchor + public.quest_period(c) * (
               floor(extract(epoch from now() - v_anchor)
                     / extract(epoch from public.quest_period(c)))::int + 1))
        from unnest(array['MAIN', 'DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY', 'ROLE']) c
    )::jsonb || jsonb_build_object('EVENT', v_enext),
    'halloween', v_hw,
    'winter', v_winter
  );
end;
$$;

grant execute on function public.my_quests() to authenticated;

create or replace function public.claim_quest(p_quest_id bigint)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_q   public.quests%rowtype;
  v_dup boolean := false;
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
     and not ((public.is_halloween() and v_q.created_at >= public.halloween_start())
              or (public.is_winter() and v_q.created_at >= public.winter_start())) then
    raise exception '이벤트 기간이 끝났습니다.';
  end if;
  if public.quest_progress(v_uid, v_q.kind, v_q.created_at, v_q.role) < v_q.target then
    raise exception '아직 퀘스트를 깨지 못했습니다.';
  end if;

  update public.quests q set claimed_at = now() where q.id = v_q.id;
  insert into public.quest_clears (uid, quest_id) values (v_uid, v_q.id);

  -- 프로필 보상: 없으면 준다. 이미 가졌으면 reward_amount 만큼 별로 대신 준다
  if v_q.reward_type = 'AVATAR' then
    insert into public.owned_items (uid, item_id) values (v_uid, v_q.reward_item)
    on conflict (uid, item_id) do nothing;
    v_dup := not found;
    if v_dup then
      update public.profiles pf set stars = pf.stars + v_q.reward_amount where pf.uid = v_uid;
    end if;
    return json_build_object('rewardType', v_q.reward_type, 'rewardAmount', v_q.reward_amount,
                             'rewardItem', v_q.reward_item, 'dup', v_dup);
  end if;

  update public.profiles pf
     set stars = pf.stars + case when v_q.reward_type = 'STAR' then v_q.reward_amount else 0 end,
         gems  = pf.gems  + case when v_q.reward_type = 'GEM'  then v_q.reward_amount else 0 end,
         coins = pf.coins + case when v_q.reward_type = 'COIN' then v_q.reward_amount else 0 end
   where pf.uid = v_uid;

  return json_build_object('rewardType', v_q.reward_type, 'rewardAmount', v_q.reward_amount);
end;
$$;

grant execute on function public.claim_quest(bigint) to authenticated;

