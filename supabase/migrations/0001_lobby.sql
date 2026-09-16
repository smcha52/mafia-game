-- ============================================================
-- 마피아 게임 · 1단계 (온라인 방 / 대기실 / 준비 / 시작 / 재접속)
-- ============================================================
-- 보안 원칙 (요구사항 §6.2, §6.4)
--   · 모든 테이블 RLS 활성화, 기본 전면 거부
--   · 클라이언트의 직접 INSERT/UPDATE/DELETE 정책은 만들지 않는다
--   · 쓰기는 전부 SECURITY DEFINER RPC 를 통해서만 수행한다
-- ============================================================

-- ------------------------------------------------------------
-- 1. 테이블
-- ------------------------------------------------------------

create table if not exists public.rooms (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique,
  host_uid    uuid not null,
  -- LOBBY: 대기실 / NIGHT, DAY: 진행 중(2단계) / ENDED: 종료
  phase       text not null default 'LOBBY'
              check (phase in ('LOBBY', 'NIGHT', 'DAY', 'ENDED')),
  day_number  int  not null default 0,
  created_at  timestamptz not null default now(),
  started_at  timestamptz
);

create table if not exists public.players (
  id             uuid primary key default gen_random_uuid(),
  room_id        uuid not null references public.rooms(id) on delete cascade,
  uid            uuid not null,
  nickname       text not null check (char_length(btrim(nickname)) between 1 and 12),
  is_host        boolean not null default false,
  is_ready       boolean not null default false,
  -- 아래 3개는 2단계(직업)에서 사용. 요구사항 §7.1
  alive          boolean not null default true,
  ability_used   boolean not null default false,
  last_target_id uuid,
  joined_at      timestamptz not null default now(),

  unique (room_id, uid),
  unique (room_id, nickname)
);

create index if not exists players_room_idx on public.players (room_id);
create index if not exists players_uid_idx  on public.players (uid);

-- ------------------------------------------------------------
-- 2. RLS — 읽기만 허용, 쓰기 정책 없음(전면 거부)
-- ------------------------------------------------------------

alter table public.rooms   enable row level security;
alter table public.players enable row level security;

-- 정책 안에서 players 를 직접 조회하면 그 조회에 다시 players 정책이 걸려
-- 무한 재귀(42P17)가 발생한다. SECURITY DEFINER 함수로 RLS 를 우회해서 확인한다.
create or replace function public.is_room_member(p_room_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.players
     where room_id = p_room_id
       and uid = auth.uid()
  );
$$;

grant execute on function public.is_room_member(uuid) to anon, authenticated;

-- 내가 참가한 방의 정보만 읽을 수 있다.
-- (입장 전 코드 조회는 join_room RPC 가 처리하므로 별도 정책이 필요 없다)
drop policy if exists "참가한 방만 조회" on public.rooms;
create policy "참가한 방만 조회"
  on public.rooms for select
  using (public.is_room_member(rooms.id));

-- 같은 방 참가자 목록만 읽을 수 있다.
drop policy if exists "같은 방 참가자만 조회" on public.players;
create policy "같은 방 참가자만 조회"
  on public.players for select
  using (public.is_room_member(players.room_id));

-- ------------------------------------------------------------
-- 3. 내부 헬퍼
-- ------------------------------------------------------------

-- 혼동하기 쉬운 문자(0,O,1,I)를 뺀 6자리 입장 코드
create or replace function public.gen_room_code()
returns text
language plpgsql
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  candidate text;
  i int;
begin
  loop
    candidate := '';
    for i in 1..6 loop
      candidate := candidate || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.rooms where code = candidate);
  end loop;
  return candidate;
end;
$$;

-- ------------------------------------------------------------
-- 4. RPC — 방 만들기
-- ------------------------------------------------------------

create or replace function public.create_room(p_nickname text)
returns table (room_id uuid, room_code text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_code text;
  v_id   uuid;
begin
  if v_uid is null then
    raise exception '로그인이 필요합니다.';
  end if;
  if char_length(btrim(coalesce(p_nickname, ''))) = 0 then
    raise exception '닉네임을 입력해 주세요.';
  end if;

  v_code := public.gen_room_code();

  insert into public.rooms (code, host_uid)
  values (v_code, v_uid)
  returning id into v_id;

  insert into public.players (room_id, uid, nickname, is_host, is_ready)
  values (v_id, v_uid, btrim(p_nickname), true, true);

  return query select v_id, v_code;
end;
$$;

-- ------------------------------------------------------------
-- 5. RPC — 방 입장 (재입장 포함)
-- ------------------------------------------------------------

create or replace function public.join_room(p_code text, p_nickname text)
returns table (room_id uuid, room_code text)
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

  select * into v_room from public.rooms where code = upper(btrim(p_code));
  if not found then
    raise exception '존재하지 않는 방 코드입니다.';
  end if;

  -- 이미 참가한 방이면 그대로 재입장시킨다 (새로고침·재접속 대응)
  if exists (select 1 from public.players where room_id = v_room.id and uid = v_uid) then
    return query select v_room.id, v_room.code;
    return;
  end if;

  if v_room.phase <> 'LOBBY' then
    raise exception '이미 시작된 게임에는 입장할 수 없습니다.';
  end if;

  select count(*) into v_count from public.players where room_id = v_room.id;
  if v_count >= 15 then
    raise exception '정원이 가득 찼습니다. (최대 15명)';
  end if;

  if exists (select 1 from public.players where room_id = v_room.id and nickname = v_nick) then
    raise exception '이미 사용 중인 닉네임입니다.';
  end if;

  insert into public.players (room_id, uid, nickname)
  values (v_room.id, v_uid, v_nick);

  return query select v_room.id, v_room.code;
end;
$$;

-- ------------------------------------------------------------
-- 6. RPC — 준비 상태 토글
-- ------------------------------------------------------------

create or replace function public.set_ready(p_room_id uuid, p_ready boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_phase text;
begin
  select phase into v_phase from public.rooms where id = p_room_id;
  if not found then
    raise exception '존재하지 않는 방입니다.';
  end if;
  if v_phase <> 'LOBBY' then
    raise exception '대기실에서만 준비 상태를 바꿀 수 있습니다.';
  end if;

  if not exists (
    select 1 from public.players where room_id = p_room_id and uid = v_uid
  ) then
    raise exception '이 방의 참가자가 아닙니다.';
  end if;

  if exists (
    select 1 from public.players
     where room_id = p_room_id and uid = v_uid and is_host = true
  ) then
    raise exception '방장은 준비 상태를 바꿀 수 없습니다.';
  end if;

  update public.players
     set is_ready = p_ready
   where room_id = p_room_id
     and uid = v_uid;
end;
$$;

-- ------------------------------------------------------------
-- 7. RPC — 방 나가기
-- ------------------------------------------------------------

create or replace function public.leave_room(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_is_host boolean;
begin
  select is_host into v_is_host
    from public.players
   where room_id = p_room_id and uid = v_uid;

  if not found then
    return; -- 이미 나간 상태
  end if;

  delete from public.players where room_id = p_room_id and uid = v_uid;

  if v_is_host then
    -- 방장이 나가면 방을 삭제한다 (players 는 on delete cascade)
    delete from public.rooms where id = p_room_id;
  end if;
end;
$$;

-- ------------------------------------------------------------
-- 8. RPC — 게임 시작 (방장 전용)
-- ------------------------------------------------------------

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
  select * into v_room from public.rooms where id = p_room_id for update;
  if not found then
    raise exception '존재하지 않는 방입니다.';
  end if;
  if v_room.host_uid <> v_uid then
    raise exception '방장만 게임을 시작할 수 있습니다.';
  end if;
  if v_room.phase <> 'LOBBY' then
    raise exception '이미 시작된 게임입니다.';
  end if;

  select count(*) into v_total from public.players where room_id = p_room_id;

  -- 요구사항 §5.1 — 구성표에 없는 인원수는 시작을 차단한다
  if v_total < 5 then
    raise exception '최소 5명이 필요합니다. (현재 %명)', v_total;
  end if;
  if v_total > 15 then
    raise exception '최대 15명까지 가능합니다. (현재 %명)', v_total;
  end if;

  select count(*) into v_not_ready
    from public.players
   where room_id = p_room_id and is_ready = false;

  if v_not_ready > 0 then
    raise exception '아직 준비하지 않은 참가자가 %명 있습니다.', v_not_ready;
  end if;

  -- 2단계에서 이 지점에 직업 배정이 들어간다
  update public.rooms
     set phase = 'NIGHT',
         day_number = 1,
         started_at = now()
   where id = p_room_id;
end;
$$;

-- ------------------------------------------------------------
-- 9. RPC — 재접속: 내가 참가 중인 방 찾기
-- ------------------------------------------------------------

create or replace function public.my_active_room()
returns table (room_id uuid, room_code text, phase text)
language sql
security definer
set search_path = public
as $$
  select r.id, r.code, r.phase
    from public.rooms r
    join public.players p on p.room_id = r.id
   where p.uid = auth.uid()
     and r.phase <> 'ENDED'
   order by r.created_at desc
   limit 1;
$$;

-- ------------------------------------------------------------
-- 10. 권한
-- ------------------------------------------------------------
-- 프로젝트 설정에서 "Automatically expose new tables" 를 꺼도 동작하도록
-- 필요한 권한만 명시적으로 부여한다.
--
-- SELECT 만 주고 INSERT/UPDATE/DELETE 는 주지 않는다.
-- RLS 정책과 별개인 2중 방어 — 실수로 쓰기 정책을 추가하더라도
-- 권한 자체가 없어 클라이언트 직접 쓰기가 차단된다.

grant select on public.rooms   to anon, authenticated;
grant select on public.players to anon, authenticated;

revoke insert, update, delete on public.rooms   from anon, authenticated;
revoke insert, update, delete on public.players from anon, authenticated;

-- 내부 헬퍼는 직접 호출을 막는다
revoke all on function public.gen_room_code() from public, anon, authenticated;

grant execute on function public.create_room(text)          to anon, authenticated;
grant execute on function public.join_room(text, text)      to anon, authenticated;
grant execute on function public.set_ready(uuid, boolean)   to anon, authenticated;
grant execute on function public.leave_room(uuid)           to anon, authenticated;
grant execute on function public.start_game(uuid)           to anon, authenticated;
grant execute on function public.my_active_room()           to anon, authenticated;

-- ------------------------------------------------------------
-- 11. Realtime 구독 대상 등록
-- ------------------------------------------------------------

-- 이미 등록되어 있으면 건너뛴다 (재실행 가능하게)
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'rooms'
  ) then
    alter publication supabase_realtime add table public.rooms;
  end if;

  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'players'
  ) then
    alter publication supabase_realtime add table public.players;
  end if;
end $$;
