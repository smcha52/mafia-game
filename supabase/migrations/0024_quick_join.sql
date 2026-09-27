-- 0024_quick_join.sql
-- 빠른 시작: 15명이 안 된 대기실 방을 골라 바로 입장한다.
--
-- 방 고르기
--   · 대기실(LOBBY) 이고 15명 미만
--   · 같은 닉네임이 없고, 내가 이미 참가한 방이 아님
--   · 사람이 많은 방부터, 같으면 최근에 만든 방부터 (빨리 시작할 수 있는 방)
--
-- 들어가는 중에 방이 차는 경우
--   고른 방을 FOR UPDATE 로 잠근 뒤 인원을 다시 센다. 그 사이 다른 사람이 먼저
--   들어와 15명이 됐으면 '그 방은 자리가 없습니다.' 를 돌려준다.
--   join_room 도 같은 잠금을 걸어야 코드 입장과 빠른 시작이 동시에 들어와도
--   16명이 되지 않는다. 그래서 join_room 을 잠금만 추가해 다시 정의한다.

-- ------------------------------------------------------------
-- 1. 빠른 시작
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

-- ------------------------------------------------------------
-- 2. 코드 입장에도 같은 잠금을 건다 (0001 본문 + FOR UPDATE)
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
