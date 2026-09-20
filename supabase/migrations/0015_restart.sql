-- ============================================================
-- 마피아 게임 · 다시하기
-- ============================================================
-- 게임이 끝난 방을 대기실 상태로 되돌린다. 참가자는 그대로 남고
-- 직업은 다음 시작 때 새로 배정된다.
--
-- 지난 판 기록은 모두 지운다.
--   · private_roles   남겨두면 다음 판 배정과 충돌한다
--   · night_actions / day_votes / private_results / public_results
--   · chat_messages   대기실로 돌아가면 마피아 대화가 다시 숨겨져
--                     혼란스럽고, 지난 판 정보가 새 판에 남는다
--
-- 방장만 누를 수 있고, 종료된 방에서만 동작한다.
-- ============================================================

create or replace function public.restart_game(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room public.rooms%rowtype;
begin
  select * into v_room from public.rooms r where r.id = p_room_id for update;
  if not found then
    raise exception '존재하지 않는 방입니다.';
  end if;
  if v_room.host_uid <> auth.uid() then
    raise exception '방장만 다시 시작할 수 있습니다.';
  end if;
  if v_room.phase <> 'ENDED' then
    raise exception '게임이 끝난 뒤에만 다시 시작할 수 있습니다.';
  end if;

  -- 지난 판 기록 삭제
  delete from public.private_results where room_id = p_room_id;
  delete from public.public_results  where room_id = p_room_id;
  delete from public.night_actions   where room_id = p_room_id;
  delete from public.day_votes       where room_id = p_room_id;
  delete from public.private_roles   where room_id = p_room_id;
  delete from public.chat_messages   where room_id = p_room_id;

  -- 참가자 초기화. 방장은 준비 상태를 유지한다 (§ 대기실 규칙과 동일)
  update public.players pl
     set alive          = true,
         ability_used   = false,
         last_target_id = null,
         team           = null,
         is_ready       = pl.is_host
   where pl.room_id = p_room_id;

  -- 방을 대기실로. 제한시간 설정(night_seconds 등)은 그대로 둔다
  update public.rooms r
     set phase          = 'LOBBY',
         day_number     = 0,
         winner         = null,
         jester_uid     = null,
         started_at     = null,
         phase_deadline = null
   where r.id = p_room_id;
end;
$$;

grant execute on function public.restart_game(uuid) to anon, authenticated;
