-- ============================================================
-- 마피아 게임 · 랜덤 구성에서 시민 끄기
-- ============================================================
-- 랜덤 구성일 때 시민(능력 없는 시민)도 끌 수 있다.
-- 시민을 끄면 시민 진영 자리는 켜진 시민 진영 직업(경찰·의사 … 각 1명)만으로 채운다.
-- 켜진 직업 수가 시민 진영 자리보다 적으면 게임을 시작할 수 없다.
--   예) 5명 = 마피아 1 · 중립 1 · 시민 진영 3. 시민을 끄고 시민 진영 직업이 2개만 켜져 있으면 시작 불가
-- 고정 구성은 끈 직업 자리를 시민이 채우는 방식이라 시민 끄기를 무시한다.
-- ============================================================

create or replace function public.toggleable_roles()
returns text[]
language sql
immutable
as $$
  select array['MAFIA', 'POLICE', 'DOCTOR', 'BODYGUARD', 'DETECTIVE',
               'REPORTER', 'MEDIUM', 'SPY', 'JESTER', 'ASSASSIN', 'KILLER',
               'VIGILANTE', 'SHERIFF', 'FORGER', 'SURVIVOR', 'CITIZEN'];
$$;

-- ------------------------------------------------------------
-- random_composition: 시민을 껐으면 시민 진영을 켜진 직업으로만 채운다 (0034 와 나머지는 같다)
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
  --   마피아가 켜져 있으면 첫 자리는 마피아, 나머지는 켜진 스파이·암살자·위조범과 마피아 중에서.
  --   마피아가 꺼져 있으면 켜진 스파이·암살자·위조범으로만 채운다 (자리 수는 이미 그 이하).
  if 'MAFIA' = any (off) then
    v_out := v_out || array(
      select x from unnest(array['SPY', 'ASSASSIN', 'FORGER']) x
       where not (x = any (off))
       order by random() limit v_m);
  else
    v_out := v_out || 'MAFIA'::text;
    if v_m > 1 then
      v_pool := array(select x from unnest(array['SPY', 'ASSASSIN', 'FORGER']) x where not (x = any (off)))
                || array_fill('MAFIA'::text, array[v_m - 1]);
      v_out := v_out || array(select x from unnest(v_pool) x order by random() limit v_m - 1);
    end if;
  end if;

  -- 중립: 켜진 중립 직업 중에서 (자리 수는 이미 켜진 직업 수 이하)
  if v_n > 0 then
    v_out := v_out || array(
      select x from unnest(array['JESTER', 'KILLER', 'SURVIVOR']) x
       where not (x = any (off))
       order by random() limit v_n);
  end if;

  -- 시민 진영: 켜진 시민 직업과 시민 중에서.
  -- 시민을 껐으면 켜진 시민 진영 직업(각 1명)만으로 채우므로, 자리보다 적으면 시작할 수 없다.
  v_pool := array(
              select x from unnest(array['POLICE', 'DOCTOR', 'BODYGUARD', 'DETECTIVE',
                                         'REPORTER', 'MEDIUM', 'VIGILANTE', 'SHERIFF']) x
               where not (x = any (off)));
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

revoke all on function public.random_composition(int, text[]) from public, anon, authenticated;

-- ------------------------------------------------------------
-- assign_roles: 고정 구성에서는 시민 끄기를 무시한다 (0034 와 나머지는 같다)
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
  v_max    int;
  v_count  int;
  v_i      int := 1;
  v_uid    uuid;
  v_role   text;
  v_team   text;
begin
  select count(*) into v_count from public.players pl where pl.room_id = p_room_id;
  select r.disabled_roles, r.random_roles, r.max_days into v_off, v_random, v_max
    from public.rooms r where r.id = p_room_id;

  -- 최대 일수가 2일 이하이면 생존자는 이길 날이 없으므로 넣지 않는다
  if public.survivor_target(v_max) is null then
    v_off := coalesce(v_off, '{}') || 'SURVIVOR'::text;
  end if;

  if coalesce(v_random, true) then
    v_roles := public.random_composition(v_count, coalesce(v_off, '{}'));
  else
    -- 고정 구성은 끈 직업 자리를 시민이 채우므로 시민 끄기는 무시한다
    v_roles := public.role_composition(v_count, array_remove(coalesce(v_off, '{}'), 'CITIZEN'));
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
