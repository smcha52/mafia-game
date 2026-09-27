-- 0027_kick.sql
-- 방장이 대기실에서 참가자를 추방한다.
-- (0026_host_transfer.sql 의 remove_player 를 쓴다)
--
--   · 방장만, 대기실(LOBBY)에서만 할 수 있다. 게임 중에는 막는다.
--   · 자기 자신은 추방할 수 없다 (나가기를 쓴다).
--   · 추방은 나가기와 같다. 다시 들어오는 것은 막지 않는다.
--   · 추방당한 사람에게 안내를 띄우려고 kicks 에 기록을 남긴다.
--     브라우저 종료로 자동 퇴장된 경우와 구별하기 위해서다.
--     방이 없어져도 안내할 수 있도록 rooms 를 참조하지 않는다.

create table if not exists public.kicks (
  room_id   uuid not null,
  uid       uuid not null,
  kicked_at timestamptz not null default now(),
  primary key (room_id, uid)
);

-- 직접 읽기·쓰기는 막고 RPC 로만 다룬다
alter table public.kicks enable row level security;
revoke all on public.kicks from anon, authenticated;

create or replace function public.kick_player(p_room_id uuid, p_target_uid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room public.rooms%rowtype;
begin
  -- 동시에 나가기·입장이 들어와도 한 번에 하나씩 처리되도록 방을 잠근다
  select * into v_room from public.rooms r where r.id = p_room_id for update;
  if not found then
    raise exception '존재하지 않는 방입니다.';
  end if;
  if v_room.host_uid <> auth.uid() then
    raise exception '방장만 추방할 수 있습니다.';
  end if;
  if v_room.phase <> 'LOBBY' then
    raise exception '대기실에서만 추방할 수 있습니다.';
  end if;
  if p_target_uid = auth.uid() then
    raise exception '자신은 추방할 수 없습니다.';
  end if;
  if not exists (
    select 1 from public.players pl
     where pl.room_id = p_room_id and pl.uid = p_target_uid
  ) then
    raise exception '이 방의 참가자가 아닙니다.';
  end if;

  perform public.remove_player(p_room_id, p_target_uid);

  insert into public.kicks (room_id, uid, kicked_at)
  values (p_room_id, p_target_uid, now())
  on conflict (room_id, uid) do update set kicked_at = excluded.kicked_at;
end;
$$;

grant execute on function public.kick_player(uuid, uuid) to anon, authenticated;

-- 방에서 빠진 사람이 "추방당했는지" 확인한다. 한 번 확인하면 기록을 지운다.
-- 오래된 기록(다시 들어왔다 나간 경우 등)은 추방으로 보지 않는다.
create or replace function public.take_kick_notice(p_room_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_at timestamptz;
begin
  delete from public.kicks k
   where k.room_id = p_room_id and k.uid = auth.uid()
  returning k.kicked_at into v_at;

  return v_at is not null and v_at > now() - interval '10 minutes';
end;
$$;

grant execute on function public.take_kick_notice(uuid) to anon, authenticated;
