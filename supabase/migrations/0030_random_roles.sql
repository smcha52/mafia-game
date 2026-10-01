-- ============================================================
-- 마피아 게임 · 랜덤 구성
-- ============================================================
-- 방장이 대기실에서 "랜덤 구성" 을 켜면(기본값) 고정 구성표 대신
-- 진영별 인원만 정해 두고, 각 진영 안에서 직업을 무작위로 뽑는다.
-- 끄면 지금까지의 고정 구성표(role_composition)를 그대로 쓴다.
--
-- 진영별 인원
--   마피아 진영  기존 구성표의 마피아·스파이·암살자 합계
--                5~6명 1 · 7~8명 2 · 9~11명 3 · 12~15명 4
--   중립         5~8명 1 · 9명 이상 2
--   시민 진영    나머지 전부
--
-- 직업 뽑기
--   · 특수 직업(마피아·시민 외)은 한 게임에 최대 1명이다.
--     광대·살인자·자경단 처리가 한 명 기준이라 중복을 허용하지 않는다.
--   · 마피아 진영은 첫 자리가 반드시 마피아다. 나머지는 스파이·암살자·마피아 중에서.
--   · 시민 진영은 켜진 시민 직업과 시민 중에서 뽑는다. 시민은 여러 명 나올 수 있다.
--   · 중립은 켜진 중립 직업 중에서 뽑는다. 모자라면 그 자리는 시민이 된다.
--   · 꺼진 직업은 뽑히지 않는다.
--
-- 마피아 끄기
--   · 이제 마피아도 끌 수 있다. 대신 마피아가 꺼져 있으면 게임을 시작할 수 없다.
-- ============================================================

alter table public.rooms
  add column if not exists random_roles boolean not null default true;

-- ------------------------------------------------------------
-- 0. 마피아도 끌 수 있는 직업 목록에 넣는다
-- ------------------------------------------------------------

create or replace function public.toggleable_roles()
returns text[]
language sql
immutable
as $$
  select array['MAFIA', 'POLICE', 'DOCTOR', 'BODYGUARD', 'DETECTIVE',
               'REPORTER', 'MEDIUM', 'SPY', 'JESTER', 'ASSASSIN', 'KILLER',
               'VIGILANTE'];
$$;

-- ------------------------------------------------------------
-- 1. 진영별 인원
-- ------------------------------------------------------------

create or replace function public.team_composition(
  p_count int, p_disabled text[] default '{}')
returns json
language plpgsql
immutable
as $$
declare
  off       text[] := coalesce(p_disabled, '{}');
  v_mafia   int;
  v_neutral int;
  v_open    int;
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

  -- 켜진 중립 직업보다 자리가 많으면 남는 자리는 시민 진영으로 간다
  select count(*) into v_open
    from unnest(array['JESTER', 'KILLER']) x
   where not (x = any (off));
  v_neutral := least(v_neutral, v_open);

  return json_build_object(
    'mafia',   v_mafia,
    'neutral', v_neutral,
    'citizen', p_count - v_mafia - v_neutral);
end;
$$;

grant execute on function public.team_composition(int, text[]) to anon, authenticated;

-- ------------------------------------------------------------
-- 2. 랜덤 구성
-- ------------------------------------------------------------

create or replace function public.random_composition(
  p_count int, p_disabled text[] default '{}')
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
  v_teams := public.team_composition(p_count, off);
  v_m := (v_teams ->> 'mafia')::int;
  v_n := (v_teams ->> 'neutral')::int;
  v_c := (v_teams ->> 'citizen')::int;

  -- 마피아 진영: 첫 자리는 마피아. 나머지는 켜진 스파이·암살자와 마피아 중에서.
  v_out := v_out || 'MAFIA'::text;
  if v_m > 1 then
    v_pool := array(select x from unnest(array['SPY', 'ASSASSIN']) x where not (x = any (off)))
              || array_fill('MAFIA'::text, array[v_m - 1]);
    v_out := v_out || array(select x from unnest(v_pool) x order by random() limit v_m - 1);
  end if;

  -- 중립: 켜진 중립 직업 중에서 (자리 수는 이미 켜진 직업 수 이하)
  if v_n > 0 then
    v_out := v_out || array(
      select x from unnest(array['JESTER', 'KILLER']) x
       where not (x = any (off))
       order by random() limit v_n);
  end if;

  -- 시민 진영: 켜진 시민 직업과 시민 중에서
  v_pool := array(
              select x from unnest(array['POLICE', 'DOCTOR', 'BODYGUARD', 'DETECTIVE',
                                         'REPORTER', 'MEDIUM', 'VIGILANTE']) x
               where not (x = any (off)))
            || array_fill('CITIZEN'::text, array[v_c]);
  v_out := v_out || array(select x from unnest(v_pool) x order by random() limit v_c);

  if coalesce(array_length(v_out, 1), 0) <> p_count then
    raise exception '랜덤 구성 오류: %명 구성의 직업 수가 %개입니다.',
      p_count, coalesce(array_length(v_out, 1), 0);
  end if;

  return v_out;
end;
$$;

revoke all on function public.random_composition(int, text[]) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 3. 배정 — 0016 본문에서 구성을 고르는 부분만 바꿨다
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
  v_count  int;
  v_i      int := 1;
  v_uid    uuid;
  v_role   text;
  v_team   text;
begin
  select count(*) into v_count from public.players pl where pl.room_id = p_room_id;
  select r.disabled_roles, r.random_roles into v_off, v_random
    from public.rooms r where r.id = p_room_id;

  -- 마피아가 없으면 시작과 동시에 시민이 이기므로 시작을 막는다.
  -- start_game 안에서 불리므로 여기서 거절하면 시작 전체가 취소된다.
  if 'MAFIA' = any (coalesce(v_off, '{}')) then
    raise exception '마피아가 꺼져 있어 게임을 시작할 수 없습니다.';
  end if;

  if coalesce(v_random, true) then
    v_roles := public.random_composition(v_count, coalesce(v_off, '{}'));
  else
    v_roles := public.role_composition(v_count, coalesce(v_off, '{}'));
  end if;

  -- 무작위 순서로 배정한다
  for v_uid in
    select pl.uid from public.players pl
     where pl.room_id = p_room_id
     order by random()
  loop
    v_role := v_roles[v_i];
    v_team := public.team_of(v_role);

    insert into public.private_roles (room_id, uid, role, team)
    values (p_room_id, v_uid, v_role, v_team)
    on conflict (room_id, uid) do update set role = excluded.role, team = excluded.team;

    if v_role = 'JESTER' then
      update public.rooms r set jester_uid = v_uid where r.id = p_room_id;
    end if;

    v_i := v_i + 1;
  end loop;
end;
$$;

revoke all on function public.assign_roles(uuid) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 4. 방장이 랜덤 구성을 켜고 끈다
-- ------------------------------------------------------------

create or replace function public.set_random_roles(p_room_id uuid, p_on boolean)
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
    raise exception '방장만 구성을 바꿀 수 있습니다.';
  end if;
  if v_room.phase <> 'LOBBY' then
    raise exception '대기실에서만 바꿀 수 있습니다.';
  end if;

  update public.rooms r
     set random_roles = coalesce(p_on, true)
   where r.id = p_room_id;
end;
$$;

grant execute on function public.set_random_roles(uuid, boolean) to anon, authenticated;
