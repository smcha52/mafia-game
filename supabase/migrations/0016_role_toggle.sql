-- ============================================================
-- 마피아 게임 · 직업 켜기/끄기
-- ============================================================
-- 방장이 대기실에서 직업을 끌 수 있다. 끈 직업은 배정되지 않고
-- 그 자리는 시민이 대신 채운다. 인원수가 유지되어야 §5.1 의
-- "직업 수 합계 = 참가 인원" 이 계속 성립한다.
--
-- 끌 수 없는 직업
--   MAFIA   0명이 되면 시작과 동시에 시민이 승리한다
--   CITIZEN 대체용이라 끄면 빈자리가 생긴다
--
-- 끌 수 있는 직업 (8개)
--   POLICE DOCTOR BODYGUARD DETECTIVE REPORTER MEDIUM SPY JESTER
-- ============================================================

alter table public.rooms
  add column if not exists disabled_roles text[] not null default '{}';

-- ------------------------------------------------------------
-- 1. 끌 수 있는 직업 목록
-- ------------------------------------------------------------

create or replace function public.toggleable_roles()
returns text[]
language sql
immutable
as $$
  select array['POLICE', 'DOCTOR', 'BODYGUARD', 'DETECTIVE',
               'REPORTER', 'MEDIUM', 'SPY', 'JESTER'];
$$;

grant execute on function public.toggleable_roles() to anon, authenticated;

-- ------------------------------------------------------------
-- 2. 구성표에 "끈 직업" 을 반영
-- ------------------------------------------------------------
-- 인자를 추가하므로 이전 1인자 시그니처를 먼저 지운다.
-- create or replace 는 인자가 다르면 교체가 아니라 추가라서,
-- 두 함수가 공존하면 PostgREST 가 PGRST203 을 낸다.

drop function if exists public.role_composition(int);

create or replace function public.role_composition(
  p_count int, p_disabled text[] default '{}')
returns text[]
language plpgsql
immutable
as $$
declare
  v   text[];
  v2  text[];
  off text[] := coalesce(p_disabled, '{}');
begin
  v := case p_count
    when 5  then array['MAFIA','POLICE','DOCTOR','CITIZEN','CITIZEN']
    when 6  then array['MAFIA','POLICE','DOCTOR','BODYGUARD','CITIZEN','CITIZEN']
    when 7  then array['MAFIA','MAFIA','POLICE','DOCTOR','JESTER','CITIZEN','CITIZEN']
    when 8  then array['MAFIA','MAFIA','POLICE','DOCTOR','BODYGUARD','JESTER','CITIZEN','CITIZEN']
    when 9  then array['MAFIA','MAFIA','SPY','POLICE','DOCTOR','DETECTIVE','CITIZEN','CITIZEN','CITIZEN']
    when 10 then array['MAFIA','MAFIA','SPY','POLICE','DOCTOR','BODYGUARD','DETECTIVE','CITIZEN','CITIZEN','CITIZEN']
    when 11 then array['MAFIA','MAFIA','SPY','POLICE','DOCTOR','BODYGUARD','DETECTIVE','REPORTER','CITIZEN','CITIZEN','CITIZEN']
    when 12 then array['MAFIA','MAFIA','MAFIA','SPY','POLICE','DOCTOR','BODYGUARD','DETECTIVE','REPORTER','JESTER','CITIZEN','CITIZEN']
    when 13 then array['MAFIA','MAFIA','MAFIA','SPY','POLICE','DOCTOR','BODYGUARD','DETECTIVE','REPORTER','MEDIUM','JESTER','CITIZEN','CITIZEN']
    when 14 then array['MAFIA','MAFIA','MAFIA','SPY','POLICE','DOCTOR','BODYGUARD','DETECTIVE','REPORTER','MEDIUM','JESTER','CITIZEN','CITIZEN','CITIZEN']
    when 15 then array['MAFIA','MAFIA','MAFIA','SPY','POLICE','DOCTOR','BODYGUARD','DETECTIVE','REPORTER','MEDIUM','JESTER','CITIZEN','CITIZEN','CITIZEN','CITIZEN']
    else null
  end;

  if v is null then
    raise exception '% 명은 지원하지 않습니다. (5~15명)', p_count;
  end if;

  -- 꺼진 직업은 시민으로 대체한다. 순서를 지켜 인원수가 변하지 않게 한다.
  select array_agg(case when t.x = any (off) then 'CITIZEN' else t.x end order by t.ord)
    into v2
    from unnest(v) with ordinality as t(x, ord);

  -- §5.1 직업 수의 합계가 참가 인원과 정확히 일치하는지 검증
  if array_length(v2, 1) <> p_count then
    raise exception '구성표 오류: %명 구성의 직업 수가 %개입니다.', p_count, array_length(v2, 1);
  end if;

  return v2;
end;
$$;

grant execute on function public.role_composition(int, text[]) to anon, authenticated;

-- ------------------------------------------------------------
-- 3. 배정 시 방의 설정을 반영
-- ------------------------------------------------------------

create or replace function public.assign_roles(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_roles text[];
  v_off   text[];
  v_count int;
  v_i     int := 1;
  v_uid   uuid;
  v_role  text;
  v_team  text;
begin
  select count(*) into v_count from public.players pl where pl.room_id = p_room_id;
  select r.disabled_roles into v_off from public.rooms r where r.id = p_room_id;
  v_roles := public.role_composition(v_count, coalesce(v_off, '{}'));

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
-- 4. 방장이 직업을 켜고 끈다
-- ------------------------------------------------------------

create or replace function public.set_disabled_roles(p_room_id uuid, p_disabled text[])
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room public.rooms%rowtype;
  v_off  text[] := coalesce(p_disabled, '{}');
  v_bad  text;
begin
  select * into v_room from public.rooms r where r.id = p_room_id;
  if not found then
    raise exception '존재하지 않는 방입니다.';
  end if;
  if v_room.host_uid <> auth.uid() then
    raise exception '방장만 직업을 바꿀 수 있습니다.';
  end if;
  if v_room.phase <> 'LOBBY' then
    raise exception '대기실에서만 바꿀 수 있습니다.';
  end if;

  -- 끌 수 없는 직업이 들어오면 거부한다
  select x into v_bad
    from unnest(v_off) x
   where not (x = any (public.toggleable_roles()))
   limit 1;

  if v_bad is not null then
    raise exception '% 는 끌 수 없는 직업입니다.', v_bad;
  end if;

  update public.rooms r
     set disabled_roles = (select coalesce(array_agg(distinct x), '{}') from unnest(v_off) x)
   where r.id = p_room_id;
end;
$$;

grant execute on function public.set_disabled_roles(uuid, text[]) to anon, authenticated;
