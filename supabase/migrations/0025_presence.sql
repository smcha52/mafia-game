-- 0025_presence.sql
-- 브라우저를 닫으면 방에서 나가게 한다.
--
-- 브라우저는 "창을 닫았다" 를 서버에 확실히 알려주지 못하고, 새로고침과도
-- 구별할 수 없다. 그래서 열려 있는 동안 heartbeat 를 보내게 하고,
-- 60초 넘게 소식이 없는 참가자를 나간 것으로 본다. 새로고침은 60초 안에
-- 다시 접속하므로 자리가 유지된다.
--
-- 나간 사람 처리
--   대기실(LOBBY) · 종료(ENDED)  leave_room 과 같다. 참가자에서 지우고,
--                                방장이면 방을 없앤다.
--   진행 중(NIGHT · DAY)         참가자는 남기고 사망 처리한다. 직업·결과 기록이
--                                참가자에 묶여 있어 지울 수 없다. 이번 단계에 낸
--                                투표·능력은 취소하고 승리 조건을 다시 본다.
--                                밤에 죽은 것과 같으므로 광대는 승리하지 않는다.
--
-- 정리는 같은 방의 누군가가 heartbeat 를 보낼 때, 그리고 빠른 시작이 방을
-- 고르기 전에 한다. 아무도 남지 않은 방은 빠른 시작 대상에서도 빠진다.
--
-- heartbeat 를 players 에 기록하면 15초마다 모든 화면이 참가자 목록을 다시
-- 읽게 된다(Realtime). 그래서 Realtime 에 올리지 않는 별도 테이블에 둔다.

-- ------------------------------------------------------------
-- 1. 접속 기록
-- ------------------------------------------------------------

create table if not exists public.presence (
  room_id   uuid not null references public.rooms(id) on delete cascade,
  uid       uuid not null,
  last_seen timestamptz not null default now(),
  primary key (room_id, uid)
);

-- 직접 읽기·쓰기는 막고 RPC 로만 다룬다
alter table public.presence enable row level security;
revoke all on public.presence from anon, authenticated;

-- ------------------------------------------------------------
-- 2. 나간 사람 정리 (내부용)
-- ------------------------------------------------------------

create or replace function public.purge_stale(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room   public.rooms%rowtype;
  v_stale  uuid[];
  v_winner text;
begin
  -- 단계 처리(resolve_*)와 겹치지 않도록 방을 잠근다
  select * into v_room from public.rooms r where r.id = p_room_id for update;
  if not found then
    return;
  end if;

  -- heartbeat 를 한 번도 보내지 않은 사람은 입장 시각을 기준으로 본다
  select array_agg(pl.uid) into v_stale
    from public.players pl
    left join public.presence ps on ps.room_id = pl.room_id and ps.uid = pl.uid
   where pl.room_id = p_room_id
     and coalesce(ps.last_seen, pl.joined_at) < now() - interval '60 seconds';

  if v_stale is null then
    return;
  end if;

  if v_room.phase in ('LOBBY', 'ENDED') then
    if v_room.host_uid = any (v_stale) then
      delete from public.rooms r where r.id = p_room_id;
      return;
    end if;
    delete from public.players pl
     where pl.room_id = p_room_id and pl.uid = any (v_stale);
    delete from public.presence ps
     where ps.room_id = p_room_id and ps.uid = any (v_stale);
    return;
  end if;

  -- 진행 중: 살아 있는 사람만 사망 처리한다
  select array_agg(pl.uid) into v_stale
    from public.players pl
   where pl.room_id = p_room_id and pl.alive = true and pl.uid = any (v_stale);

  if v_stale is null then
    return;
  end if;

  update public.players pl
     set alive = false
   where pl.room_id = p_room_id and pl.uid = any (v_stale);

  delete from public.day_votes d
   where d.room_id = p_room_id and d.day_number = v_room.day_number
     and d.voter_uid = any (v_stale);
  delete from public.night_actions n
   where n.room_id = p_room_id and n.day_number = v_room.day_number
     and n.actor_uid = any (v_stale);

  v_winner := public.check_winner(p_room_id, null);
  if v_winner is not null then
    perform public.end_game(p_room_id, v_winner);
  end if;
end;
$$;

revoke all on function public.purge_stale(uuid) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 3. heartbeat — 화면이 열려 있는 동안 15초마다 보낸다
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
-- 4. 빠른 시작 — 방을 고르기 전에 비어 있는 대기실을 정리한다
-- ------------------------------------------------------------
-- 0024 본문에 정리 단계만 앞에 붙였다.

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
