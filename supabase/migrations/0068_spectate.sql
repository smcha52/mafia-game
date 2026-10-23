-- ============================================================
-- 마피아 게임 · 게임 중간에 들어와 관전하기
-- ============================================================
-- 이미 시작된 방에 코드로 들어오면 막지 않고 관전자로 들어온다.
-- 화면에는 '이미 게임이 시작되어서 관전 중 입니다' 가 뜬다.
--
-- 관전자는 players 가 아니라 spectators 에 둔다. players 에 넣으면 투표 인원,
-- 승리 판정, 영매의 사망자 목록 등 게임 규칙이 모두 관전자를 참가자로 센다.
--
-- 관전자가 할 수 있는 것
--   방 · 참가자 · 공개 결과 · 공개 채팅 읽기 (is_room_member 에 관전자를 더한다)
--   비공개 방에서는 사망자와 똑같이 모든 참가자의 직업 보기 (dead_roles)
-- 할 수 없는 것
--   채팅 · 투표 · 능력 (send_chat 등은 players 만 받으므로 그대로 막힌다)
--
-- 방장이 다시하기를 눌러 대기실로 돌아가면 관전자는 참가자가 된다.
-- 그래서 참가자 + 관전자를 합쳐 15명까지만 받는다.
-- 참가자가 모두 나가 방이 지워지면 관전자도 함께 지워진다.
-- ============================================================

create table if not exists public.spectators (
  room_id   uuid not null references public.rooms(id) on delete cascade,
  uid       uuid not null,
  nickname  text not null,
  joined_at timestamptz not null default now(),
  primary key (room_id, uid)
);

create index if not exists spectators_uid_idx on public.spectators (uid);

-- 본인 것만 읽는다. 쓰기는 RPC 로만 한다
alter table public.spectators enable row level security;

drop policy if exists "내 관전 기록만 조회" on public.spectators;
create policy "내 관전 기록만 조회"
  on public.spectators for select
  using (spectators.uid = auth.uid());

grant select on public.spectators to authenticated;
revoke insert, update, delete on public.spectators from anon, authenticated;

-- ------------------------------------------------------------
-- 1. 방 읽기 권한 — 관전자도 방 사람으로 본다 (0001 과 나머지는 같다)
--    rooms · players · public_results · chat_messages 정책과 final_roles · tick_phase 가
--    모두 이 함수를 쓴다. 마피아 채팅은 is_mafia_member 가 따로 막는다.
-- ------------------------------------------------------------

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
  ) or exists (
    select 1 from public.spectators
     where room_id = p_room_id
       and uid = auth.uid()
  );
$$;

grant execute on function public.is_room_member(uuid) to anon, authenticated;

-- ------------------------------------------------------------
-- 2. 코드로 입장 — 시작된 방이면 관전자로 들인다 (0044 와 나머지는 같다)
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
    return json_build_object('room_id', v_room.id, 'room_code', v_room.code,
                             'phase', v_room.phase, 'spectating', false);
  end if;
  if exists (
    select 1 from public.spectators s
     where s.room_id = v_room.id and s.uid = v_uid
  ) then
    return json_build_object('room_id', v_room.id, 'room_code', v_room.code,
                             'phase', v_room.phase, 'spectating', true);
  end if;

  if not public.room_allows(v_room.id, v_uid) then
    raise exception '방 설정 때문에 들어가실 수 없습니다.';
  end if;

  -- 관전자는 다시하기 때 참가자가 되므로 함께 센다
  select (select count(*) from public.players p where p.room_id = v_room.id)
       + (select count(*) from public.spectators s where s.room_id = v_room.id)
    into v_count;
  if v_count >= 15 then
    raise exception '정원이 가득 찼습니다. (최대 15명)';
  end if;

  if exists (
    select 1 from public.players p
     where p.room_id = v_room.id and p.nickname = v_nick
  ) or exists (
    select 1 from public.spectators s
     where s.room_id = v_room.id and s.nickname = v_nick
  ) then
    raise exception '이미 사용 중인 닉네임입니다.';
  end if;

  if v_room.phase <> 'LOBBY' then
    insert into public.spectators (room_id, uid, nickname)
    values (v_room.id, v_uid, v_nick);

    return json_build_object('room_id', v_room.id, 'room_code', v_room.code,
                             'phase', v_room.phase, 'spectating', true);
  end if;

  insert into public.players (room_id, uid, nickname)
  values (v_room.id, v_uid, v_nick);

  return json_build_object('room_id', v_room.id, 'room_code', v_room.code,
                           'phase', v_room.phase, 'spectating', false);
end;
$$;

grant execute on function public.join_room(text, text) to anon, authenticated;

-- ------------------------------------------------------------
-- 3. 재접속 — 관전 중인 방도 찾는다 (0001 과 나머지는 같다)
-- ------------------------------------------------------------

create or replace function public.my_active_room()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row record;
begin
  select r.id, r.code, r.phase into v_row
    from public.rooms r
   where r.phase <> 'ENDED'
     and (exists (select 1 from public.players p
                   where p.room_id = r.id and p.uid = auth.uid())
       or exists (select 1 from public.spectators s
                   where s.room_id = r.id and s.uid = auth.uid()))
   order by r.created_at desc
   limit 1;

  if not found then
    return null;
  end if;

  return json_build_object('room_id', v_row.id, 'room_code', v_row.code, 'phase', v_row.phase);
end;
$$;

grant execute on function public.my_active_room() to anon, authenticated;

-- ------------------------------------------------------------
-- 4. heartbeat — 관전자도 받는다 (0025 와 나머지는 같다)
--    관전자의 접속 기록은 다시하기로 참가자가 된 뒤 자리 유지에 쓰인다
-- ------------------------------------------------------------

create or replace function public.heartbeat(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if not exists (
    select 1 from public.players pl
     where pl.room_id = p_room_id and pl.uid = v_uid
  ) and not exists (
    select 1 from public.spectators s
     where s.room_id = p_room_id and s.uid = v_uid
  ) then
    raise exception '이 방의 참가자가 아닙니다.';
  end if;

  insert into public.presence (room_id, uid, last_seen)
  values (p_room_id, v_uid, now())
  on conflict (room_id, uid) do update set last_seen = excluded.last_seen;

  perform public.purge_stale(p_room_id);
end;
$$;

grant execute on function public.heartbeat(uuid) to anon, authenticated;

-- ------------------------------------------------------------
-- 5. 나가기 — 관전자는 관전 기록만 지운다 (0026 과 나머지는 같다)
-- ------------------------------------------------------------

create or replace function public.leave_room(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.spectators s
   where s.room_id = p_room_id and s.uid = auth.uid();
  if found then
    delete from public.presence ps
     where ps.room_id = p_room_id and ps.uid = auth.uid();
    return;
  end if;

  -- 동시에 여러 명이 나가도 방장이 한 명만 정해지도록 방을 잠근다
  perform 1 from public.rooms r where r.id = p_room_id for update;
  perform public.remove_player(p_room_id, auth.uid());
end;
$$;

grant execute on function public.leave_room(uuid) to anon, authenticated;

-- ------------------------------------------------------------
-- 6. 다시하기로 대기실이 되면 관전자를 참가자로 옮긴다
--    restart_game 본문은 그대로 두고 방 상태 변경에 붙인다
-- ------------------------------------------------------------

create or replace function public.spectators_to_players()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.players (room_id, uid, nickname)
  select s.room_id, s.uid, s.nickname
    from public.spectators s
   where s.room_id = new.id
   order by s.joined_at
  on conflict do nothing;

  delete from public.spectators s where s.room_id = new.id;
  return null;
end;
$$;

revoke all on function public.spectators_to_players() from public, anon, authenticated;

drop trigger if exists rooms_spectators_to_players on public.rooms;
create trigger rooms_spectators_to_players
  after update of phase on public.rooms
  for each row
  when (old.phase <> 'LOBBY' and new.phase = 'LOBBY')
  execute function public.spectators_to_players();

-- ------------------------------------------------------------
-- 7. 비공개 방 직업 보기 — 관전자도 사망자처럼 본다 (0050 과 나머지는 같다)
-- ------------------------------------------------------------

create or replace function public.dead_roles(p_room_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_phase  text;
  v_public boolean;
  v_alive  boolean;
begin
  select pl.alive into v_alive
    from public.players pl where pl.room_id = p_room_id and pl.uid = v_uid;
  if not found then
    -- 관전자는 죽은 사람과 같다
    if exists (
      select 1 from public.spectators s
       where s.room_id = p_room_id and s.uid = v_uid
    ) then
      v_alive := false;
    else
      raise exception '이 방의 참가자가 아닙니다.';
    end if;
  end if;

  select r.phase, r.is_public into v_phase, v_public from public.rooms r where r.id = p_room_id;
  if v_phase = 'LOBBY' then
    raise exception '게임이 시작된 뒤에만 볼 수 있습니다.';
  end if;
  if v_public then
    raise exception '비공개 방에서만 볼 수 있습니다.';
  end if;
  if v_alive then
    raise exception '사망한 뒤에만 볼 수 있습니다.';
  end if;

  return (
    select json_agg(json_build_object(
             'uid', pl.uid, 'nickname', pl.nickname,
             'role', pr.role, 'team', pr.team, 'alive', pl.alive)
           order by pl.joined_at)
      from public.private_roles pr
      join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
     where pr.room_id = p_room_id
  );
end;
$$;

revoke all on function public.dead_roles(uuid) from public, anon;
grant execute on function public.dead_roles(uuid) to authenticated;
