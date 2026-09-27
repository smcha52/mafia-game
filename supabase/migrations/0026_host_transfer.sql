-- 0026_host_transfer.sql
-- 방장이 나가면 그다음으로 들어온 사람에게 방장을 넘긴다.
-- (0025_presence.sql 을 먼저 실행해야 한다)
--
-- 이전에는 방장이 나가면 방을 통째로 지웠다(0001 leave_room).
-- 이제는 남은 사람 중 가장 먼저 들어온 사람(joined_at 순)이 방장이 되고,
-- 아무도 남지 않았을 때만 방을 지운다.
--
-- 나가기 버튼(leave_room)과 브라우저 종료(purge_stale) 모두 remove_player 를 거친다.
-- 새 방장은 준비 상태를 바꿀 수 없으므로(set_ready) 준비 완료로 둔다.

-- ------------------------------------------------------------
-- 1. 참가자 한 명을 내보낸다 (내부용)
-- ------------------------------------------------------------

create or replace function public.remove_player(p_room_id uuid, p_uid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_host boolean;
  v_next    uuid;
begin
  delete from public.players pl
   where pl.room_id = p_room_id and pl.uid = p_uid
  returning pl.is_host into v_is_host;

  if not found then
    return; -- 이미 나간 상태
  end if;

  delete from public.presence ps
   where ps.room_id = p_room_id and ps.uid = p_uid;

  if not v_is_host then
    return;
  end if;

  select pl.uid into v_next
    from public.players pl
   where pl.room_id = p_room_id
   order by pl.joined_at, pl.id
   limit 1;

  if v_next is null then
    delete from public.rooms r where r.id = p_room_id;
    return;
  end if;

  update public.players pl
     set is_host = true, is_ready = true
   where pl.room_id = p_room_id and pl.uid = v_next;

  update public.rooms r
     set host_uid = v_next
   where r.id = p_room_id;
end;
$$;

revoke all on function public.remove_player(uuid, uuid) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 2. 나가기 버튼
-- ------------------------------------------------------------

create or replace function public.leave_room(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- 동시에 여러 명이 나가도 방장이 한 명만 정해지도록 방을 잠근다
  perform 1 from public.rooms r where r.id = p_room_id for update;
  perform public.remove_player(p_room_id, auth.uid());
end;
$$;

grant execute on function public.leave_room(uuid) to anon, authenticated;

-- ------------------------------------------------------------
-- 3. 브라우저 종료 — 0025 본문에서 대기실·종료 처리만 remove_player 로 바꿨다
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
  v_uid    uuid;
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
    -- 방장은 마지막에 내보낸다. 그래야 함께 떠난 사람이 아니라
    -- 남아 있는 사람에게 방장이 넘어간다.
    for v_uid in
      select pl.uid from public.players pl
       where pl.room_id = p_room_id and pl.uid = any (v_stale)
       order by pl.is_host
    loop
      perform public.remove_player(p_room_id, v_uid);
    end loop;
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
