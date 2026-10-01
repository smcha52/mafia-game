-- ============================================================
-- 마피아 게임 · 마피아 진영 중 하나만 있어도 시작
-- ============================================================
-- 0030 에서는 마피아가 꺼져 있으면 무조건 시작을 막았다.
-- 이제 마피아·스파이·암살자 중 하나라도 실제로 배정되면 시작할 수 있다.
--
-- 마피아가 꺼져 있을 때
--   · 랜덤 구성: 마피아 진영 자리를 켜진 스파이·암살자로만 채운다.
--     특수 직업은 1명까지라 자리가 남으면 그 자리는 시민 진영으로 간다.
--   · 고정 구성: 마피아 자리는 시민이 된다 (role_fallback 그대로).
--     그 인원의 구성표에 스파이·암살자가 없으면 마피아 진영이 0명이 된다.
--   · 어느 쪽이든 배정 결과에 마피아 진영이 0명이면 시작을 거절한다.
-- ============================================================

-- ------------------------------------------------------------
-- 1. 진영별 인원 — 0030 본문에 마피아가 꺼진 경우를 더했다
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

  -- 켜진 중립 직업보다 자리가 많으면 남는 자리는 시민 진영으로 간다
  select count(*) into v_open
    from unnest(array['JESTER', 'KILLER']) x
   where not (x = any (off));
  v_neutral := least(v_neutral, v_open);

  -- 마피아가 꺼져 있으면 마피아 진영은 켜진 스파이·암살자 수만큼만 채운다.
  -- 남는 자리는 시민 진영으로 간다. 0명이면 시작할 수 없다 (assign_roles).
  if 'MAFIA' = any (off) then
    select count(*) into v_mopen
      from unnest(array['SPY', 'ASSASSIN']) x
     where not (x = any (off));
    v_mafia := least(v_mafia, v_mopen);
  end if;

  return json_build_object(
    'mafia',   v_mafia,
    'neutral', v_neutral,
    'citizen', p_count - v_mafia - v_neutral);
end;
$$;

grant execute on function public.team_composition(int, text[]) to anon, authenticated;

-- ------------------------------------------------------------
-- 2. 랜덤 구성 — 0030 본문에서 마피아 진영 뽑기만 바꿨다
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

  -- 마피아 진영
  --   마피아가 켜져 있으면 첫 자리는 마피아, 나머지는 켜진 스파이·암살자와 마피아 중에서.
  --   마피아가 꺼져 있으면 켜진 스파이·암살자로만 채운다 (자리 수는 이미 그 이하).
  if 'MAFIA' = any (off) then
    v_out := v_out || array(
      select x from unnest(array['SPY', 'ASSASSIN']) x
       where not (x = any (off))
       order by random() limit v_m);
  else
    v_out := v_out || 'MAFIA'::text;
    if v_m > 1 then
      v_pool := array(select x from unnest(array['SPY', 'ASSASSIN']) x where not (x = any (off)))
                || array_fill('MAFIA'::text, array[v_m - 1]);
      v_out := v_out || array(select x from unnest(v_pool) x order by random() limit v_m - 1);
    end if;
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
-- 3. 배정 — 시작 조건을 "마피아 켜짐" 에서 "마피아 진영 1명 이상" 으로 바꿨다
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

  if coalesce(v_random, true) then
    v_roles := public.random_composition(v_count, coalesce(v_off, '{}'));
  else
    v_roles := public.role_composition(v_count, coalesce(v_off, '{}'));
  end if;

  -- 마피아 진영이 한 명도 없으면 시작과 동시에 시민이 이기므로 시작을 막는다.
  -- start_game 안에서 불리므로 여기서 거절하면 시작 전체가 취소된다.
  if not exists (select 1 from unnest(v_roles) x where public.team_of(x) = 'MAFIA') then
    raise exception '마피아 진영 직업이 하나도 없어 게임을 시작할 수 없습니다.';
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
