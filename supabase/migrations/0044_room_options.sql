-- ============================================================
-- 마피아 게임 · 방 설정 (나이 · 레벨 제한, 공개 / 비공개)
-- ============================================================
-- 방 만들기를 누르면 방 설정 화면이 뜨고, 고른 설정으로 방을 만든다.
--
-- 나이 (만 나이, profiles.birth 로 계산)
--   NONE   설정 안 함 — 누구나
--   ALL    전체 — 누구나 (방 찾기에 '전체' 로 표시)
--   PLUS   a 세 이상 (a: 0~25. +7 +13 +16 +19 는 화면의 바로가기)
--   MINUS  a 세 미만 (a: 1~25. 0세 미만은 아무도 들어올 수 없어 막는다)
--   RANGE  a 세 이상 b 세 이하 (0~25, a <= b)
--
-- 레벨 (players.level 과 같은 계산, level_of)
--   NONE   설정 안 함
--   PLUS   a 레벨 이상 (5~50)
--   MINUS  a 레벨 미만 (5~50)
--   RANGE  a 레벨 이상 b 레벨 이하 (5~50, a <= b)
--
-- 조건에 맞지 않으면 '방 설정 때문에 들어가실 수 없습니다.' 로 입장을 막는다.
-- 방장(만든 사람)은 검사하지 않는다. 생년월일이 없는 사용자(익명 테스트)는
-- 나이 제한이 있는 방에 들어갈 수 없다.
--
-- 공개   빠른 시작 · 방 찾기에 나온다
-- 비공개 방 코드로만 들어올 수 있다
-- 화면은 공개 / 비공개를 반드시 고르게 한다. 서버 기본값은 공개(기존 테스트 호환).
-- ============================================================

alter table public.rooms add column if not exists is_public  boolean not null default true;
alter table public.rooms add column if not exists age_mode   text    not null default 'NONE';
alter table public.rooms add column if not exists age_a      int;
alter table public.rooms add column if not exists age_b      int;
alter table public.rooms add column if not exists level_mode text    not null default 'NONE';
alter table public.rooms add column if not exists level_a    int;
alter table public.rooms add column if not exists level_b    int;

alter table public.rooms drop constraint if exists rooms_age_mode_check;
alter table public.rooms add constraint rooms_age_mode_check
  check (age_mode in ('NONE', 'ALL', 'PLUS', 'MINUS', 'RANGE'));
alter table public.rooms drop constraint if exists rooms_level_mode_check;
alter table public.rooms add constraint rooms_level_mode_check
  check (level_mode in ('NONE', 'PLUS', 'MINUS', 'RANGE'));

-- ------------------------------------------------------------
-- 1. 조건 검사 (내부용)
-- ------------------------------------------------------------

-- 값 하나가 규칙에 맞는지. NONE·ALL 은 항상 통과, 값이 없으면 통과하지 못한다
create or replace function public.rule_allows(p_mode text, p_a int, p_b int, p_value int)
returns boolean
language sql
immutable
as $$
  select case p_mode
    when 'NONE'  then true
    when 'ALL'   then true
    when 'PLUS'  then coalesce(p_value >= p_a, false)
    when 'MINUS' then coalesce(p_value <  p_a, false)
    when 'RANGE' then coalesce(p_value between p_a and p_b, false)
    else false
  end;
$$;

-- 이 사람이 이 방의 나이 · 레벨 조건에 맞는지
create or replace function public.room_allows(p_room_id uuid, p_uid uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_room  public.rooms%rowtype;
  v_age   int;
  v_level int;
begin
  select * into v_room from public.rooms r where r.id = p_room_id;
  if not found then
    return false;
  end if;
  if v_room.host_uid = p_uid then
    return true;
  end if;

  select date_part('year', age(current_date, pf.birth))::int,
         public.level_of(pf.xp)
    into v_age, v_level
    from public.profiles pf
   where pf.uid = p_uid;

  return public.rule_allows(v_room.age_mode, v_room.age_a, v_room.age_b, v_age)
     and public.rule_allows(v_room.level_mode, v_room.level_a, v_room.level_b,
                            coalesce(v_level, 1));
end;
$$;

revoke all on function public.room_allows(uuid, uuid) from public, anon, authenticated;

-- 설정값이 범위에 맞는지 확인한다
create or replace function public.check_rule(
  p_what text, p_mode text, p_a int, p_b int, p_lo int, p_hi int)
returns void
language plpgsql
immutable
as $$
begin
  if p_mode in ('NONE', 'ALL') then
    return;
  end if;
  if p_a is null or p_a < p_lo or p_a > p_hi then
    raise exception '% 값은 %~% 사이로 정해 주세요.', p_what, p_lo, p_hi;
  end if;
  if p_mode = 'MINUS' and p_a <= p_lo and p_what = '나이' then
    raise exception '나이 - 값은 1 이상으로 정해 주세요.';
  end if;
  if p_mode = 'RANGE' then
    if p_b is null or p_b < p_lo or p_b > p_hi then
      raise exception '% 값은 %~% 사이로 정해 주세요.', p_what, p_lo, p_hi;
    end if;
    if p_a > p_b then
      raise exception '% 범위의 시작이 끝보다 클 수 없습니다.', p_what;
    end if;
  end if;
end;
$$;

-- ------------------------------------------------------------
-- 2. 방 만들기 — 설정을 함께 받는다 (0001 과 나머지는 같다)
-- ------------------------------------------------------------

drop function if exists public.create_room(text);

create or replace function public.create_room(
  p_nickname   text,
  p_public     boolean default true,
  p_age_mode   text    default 'NONE',
  p_age_a      int     default null,
  p_age_b      int     default null,
  p_level_mode text    default 'NONE',
  p_level_a    int     default null,
  p_level_b    int     default null)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_code  text;
  v_id    uuid;
  v_age   text := upper(coalesce(p_age_mode, 'NONE'));
  v_level text := upper(coalesce(p_level_mode, 'NONE'));
begin
  if v_uid is null then
    raise exception '로그인이 필요합니다.';
  end if;
  if char_length(btrim(coalesce(p_nickname, ''))) = 0 then
    raise exception '닉네임을 입력해 주세요.';
  end if;
  if p_public is null then
    raise exception '공개 / 비공개를 골라 주세요.';
  end if;
  if v_age not in ('NONE', 'ALL', 'PLUS', 'MINUS', 'RANGE') then
    raise exception '나이 설정이 올바르지 않습니다.';
  end if;
  if v_level not in ('NONE', 'PLUS', 'MINUS', 'RANGE') then
    raise exception '레벨 설정이 올바르지 않습니다.';
  end if;

  perform public.check_rule('나이', v_age, p_age_a, p_age_b, 0, 25);
  perform public.check_rule('레벨', v_level, p_level_a, p_level_b, 5, 50);

  v_code := public.gen_room_code();

  insert into public.rooms (code, host_uid, is_public,
                            age_mode, age_a, age_b, level_mode, level_a, level_b)
  values (v_code, v_uid, p_public,
          v_age,
          case when v_age in ('PLUS', 'MINUS', 'RANGE') then p_age_a end,
          case when v_age = 'RANGE' then p_age_b end,
          v_level,
          case when v_level in ('PLUS', 'MINUS', 'RANGE') then p_level_a end,
          case when v_level = 'RANGE' then p_level_b end)
  returning id into v_id;

  insert into public.players (room_id, uid, nickname, is_host, is_ready)
  values (v_id, v_uid, btrim(p_nickname), true, true);

  return json_build_object('room_id', v_id, 'room_code', v_code);
end;
$$;

grant execute on function public.create_room(text, boolean, text, int, int, text, int, int)
  to anon, authenticated;

-- ------------------------------------------------------------
-- 3. 코드로 입장 — 조건 검사를 더한다 (0024 와 나머지는 같다)
--    비공개 방도 코드로는 들어올 수 있다
-- ------------------------------------------------------------

create or replace function public.join_room(p_code text, p_nickname text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_room  public.rooms%rowtype;
  v_count int;
  v_nick  text := btrim(coalesce(p_nickname, ''));
begin
  if v_uid is null then
    raise exception '로그인이 필요합니다.';
  end if;
  if char_length(v_nick) = 0 then
    raise exception '닉네임을 입력해 주세요.';
  end if;

  select * into v_room from public.rooms r
   where r.code = upper(btrim(p_code))
   for update;
  if not found then
    raise exception '존재하지 않는 방 코드입니다.';
  end if;

  -- 이미 참가한 방이면 그대로 재입장시킨다 (새로고침·재접속 대응)
  if exists (
    select 1 from public.players p
     where p.room_id = v_room.id and p.uid = v_uid
  ) then
    return json_build_object('room_id', v_room.id, 'room_code', v_room.code);
  end if;

  if v_room.phase <> 'LOBBY' then
    raise exception '이미 시작된 게임에는 입장할 수 없습니다.';
  end if;

  if not public.room_allows(v_room.id, v_uid) then
    raise exception '방 설정 때문에 들어가실 수 없습니다.';
  end if;

  select count(*) into v_count from public.players p where p.room_id = v_room.id;
  if v_count >= 15 then
    raise exception '정원이 가득 찼습니다. (최대 15명)';
  end if;

  if exists (
    select 1 from public.players p
     where p.room_id = v_room.id and p.nickname = v_nick
  ) then
    raise exception '이미 사용 중인 닉네임입니다.';
  end if;

  insert into public.players (room_id, uid, nickname)
  values (v_room.id, v_uid, v_nick);

  return json_build_object('room_id', v_room.id, 'room_code', v_room.code);
end;
$$;

grant execute on function public.join_room(text, text) to anon, authenticated;

-- ------------------------------------------------------------
-- 4. 빠른 시작 — 공개 방 중 조건에 맞는 방만 고른다 (0025 와 나머지는 같다)
-- ------------------------------------------------------------

create or replace function public.quick_join(p_nickname text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_nick  text := btrim(coalesce(p_nickname, ''));
  v_id    uuid;
  v_room  public.rooms%rowtype;
  v_count int;
begin
  if v_uid is null then
    raise exception '로그인이 필요합니다.';
  end if;
  if char_length(v_nick) = 0 then
    raise exception '닉네임을 입력해 주세요.';
  end if;

  -- 브라우저를 닫고 떠난 사람이 있는 대기실을 정리한다
  for v_id in
    select distinct r.id
      from public.rooms r
      join public.players pl on pl.room_id = r.id
      left join public.presence ps on ps.room_id = pl.room_id and ps.uid = pl.uid
     where r.phase = 'LOBBY'
       and coalesce(ps.last_seen, pl.joined_at) < now() - interval '60 seconds'
  loop
    perform public.purge_stale(v_id);
  end loop;
  v_id := null;

  select r.id into v_id
    from public.rooms r
    join public.players p on p.room_id = r.id
   where r.phase = 'LOBBY'
     and r.is_public
     and public.room_allows(r.id, v_uid)
   group by r.id, r.created_at
  having count(*) < 15
     and bool_and(p.uid <> v_uid)
     and bool_and(p.nickname <> v_nick)
   order by count(*) desc, r.created_at desc
   limit 1;

  if v_id is null then
    raise exception '입장할 수 있는 방이 없습니다. 방을 만들어 주세요.';
  end if;

  -- 고른 방을 잠그고 다시 확인한다. 기다리는 동안 상태가 바뀌었을 수 있다.
  select * into v_room from public.rooms r where r.id = v_id for update;
  if not found or v_room.phase <> 'LOBBY' then
    raise exception '그 방은 자리가 없습니다.';
  end if;

  select count(*) into v_count from public.players p where p.room_id = v_id;
  if v_count >= 15 then
    raise exception '그 방은 자리가 없습니다.';
  end if;

  if exists (
    select 1 from public.players p
     where p.room_id = v_id and p.nickname = v_nick
  ) then
    raise exception '이미 사용 중인 닉네임입니다.';
  end if;

  insert into public.players (room_id, uid, nickname)
  values (v_id, v_uid, v_nick);

  return json_build_object('room_id', v_room.id, 'room_code', v_room.code);
end;
$$;

grant execute on function public.quick_join(text) to anon, authenticated;

-- ------------------------------------------------------------
-- 5. 방 찾기 — 공개 방만 보여주고, 제한 설정을 함께 준다 (0036 과 나머지는 같다)
-- ------------------------------------------------------------

create or replace function public.list_rooms(p_exclude uuid[] default '{}')
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id   uuid;
  v_list json;
begin
  if auth.uid() is null then
    raise exception '로그인이 필요합니다.';
  end if;

  -- 브라우저를 닫고 떠난 사람이 있는 대기실을 정리한다 (quick_join 과 같다)
  for v_id in
    select distinct r.id
      from public.rooms r
      join public.players pl on pl.room_id = r.id
      left join public.presence ps on ps.room_id = pl.room_id and ps.uid = pl.uid
     where r.phase = 'LOBBY'
       and coalesce(ps.last_seen, pl.joined_at) < now() - interval '60 seconds'
  loop
    perform public.purge_stale(v_id);
  end loop;

  select coalesce(json_agg(json_build_object(
           'id',        t.id,
           'code',      t.code,
           'host',      t.host,
           'players',   t.cnt,
           'createdAt', t.created_at,
           'ageMode',   t.age_mode,
           'ageA',      t.age_a,
           'ageB',      t.age_b,
           'levelMode', t.level_mode,
           'levelA',    t.level_a,
           'levelB',    t.level_b)
           order by t.created_at desc, t.id), '[]'::json)
    into v_list
    from (
      select r.id, r.code, r.created_at,
             r.age_mode, r.age_a, r.age_b, r.level_mode, r.level_a, r.level_b,
             count(p.uid) as cnt,
             max(p.nickname) filter (where p.uid = r.host_uid) as host
        from public.rooms r
        join public.players p on p.room_id = r.id
       where r.phase = 'LOBBY'
         and r.is_public
         and not (r.id = any (coalesce(p_exclude, '{}')))
       group by r.id
      having count(p.uid) < 15
       order by r.created_at desc, r.id
       limit 10
    ) t;

  return v_list;
end;
$$;

grant execute on function public.list_rooms(uuid[]) to anon, authenticated;
