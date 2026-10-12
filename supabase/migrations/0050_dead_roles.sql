-- ============================================================
-- 마피아 게임 · 사망자의 직업 보기 (비공개 방만)
-- ============================================================
-- 비공개 방에서는 죽은 사람이 관전하면서 모든 참가자의 직업을 본다.
-- 공개 방은 모르는 사람끼리 하므로 게임이 끝날 때까지 공개하지 않는다 (final_roles).
--
-- 사망자는 게임 채팅을 쓸 수 없어(0013) 화면 안에서는 산 사람에게 알릴 수 없다.
-- 직업은 서버가 조건을 확인하고 내려 준다. 살아 있는 사람과 공개 방은 거절한다.
-- ============================================================

-- [{ uid, nickname, role, team, alive }, ...] — 입장한 순서
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
    raise exception '이 방의 참가자가 아닙니다.';
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
