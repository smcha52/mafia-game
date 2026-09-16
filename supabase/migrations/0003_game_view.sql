-- ============================================================
-- 마피아 게임 · 진행 화면용 조회 RPC
-- ============================================================
-- 클라이언트는 night_actions / day_votes 를 직접 읽을 수 없으므로
-- "내가 이미 제출했는지" 를 알 방법이 없다. 본인 몫만 골라서 돌려준다.
--
-- 이 함수는 호출자 본인의 정보만 담는다. 남의 직업이나 남의 행동 대상은
-- 절대 포함하지 않는다. (§6.1)
-- ============================================================

create or replace function public.my_game_view(p_room_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_room      public.rooms%rowtype;
  v_role      text;
  v_team      text;
  v_alive     boolean;
  v_mates     json := null;
  v_night     uuid := null;
  v_day       uuid := null;
  v_n_sub     int  := null;
  v_n_exp     int  := null;
  v_d_sub     int;
  v_d_exp     int;
begin
  select * into v_room from public.rooms r where r.id = p_room_id;
  if not found then
    raise exception '존재하지 않는 방입니다.';
  end if;

  select pr.role, pr.team into v_role, v_team
    from public.private_roles pr
   where pr.room_id = p_room_id and pr.uid = v_uid;
  if not found then
    raise exception '아직 직업이 배정되지 않았습니다.';
  end if;

  select pl.alive into v_alive
    from public.players pl
   where pl.room_id = p_room_id and pl.uid = v_uid;

  -- 마피아와 스파이만 서로를 안다 (§2.2, §2.9)
  if v_role in ('MAFIA', 'SPY') then
    select json_agg(json_build_object(
             'uid', pl.uid, 'nickname', pl.nickname, 'role', pr.role, 'alive', pl.alive)
             order by pl.joined_at)
      into v_mates
      from public.private_roles pr
      join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
     where pr.room_id = p_room_id and pr.team = 'MAFIA';
  end if;

  -- 내가 이 밤에 제출한 대상 (내 것만)
  select n.target_uid into v_night
    from public.night_actions n
   where n.room_id = p_room_id
     and n.day_number = v_room.day_number
     and n.actor_uid = v_uid;

  -- 마피아에게는 동료들의 제출 진행 상황을 숫자로만 알려준다
  if v_role = 'MAFIA' then
    select count(*) into v_n_exp
      from public.private_roles pr
      join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
     where pr.room_id = p_room_id and pr.role = 'MAFIA' and pl.alive = true;

    select count(*) into v_n_sub
      from public.night_actions n
     where n.room_id = p_room_id and n.day_number = v_room.day_number
       and n.action = 'MAFIA_VOTE';
  end if;

  select d.target_uid into v_day
    from public.day_votes d
   where d.room_id = p_room_id
     and d.day_number = v_room.day_number
     and d.voter_uid = v_uid;

  select count(*) into v_d_exp
    from public.players pl
   where pl.room_id = p_room_id and pl.alive = true;

  select count(*) into v_d_sub
    from public.day_votes d
   where d.room_id = p_room_id and d.day_number = v_room.day_number;

  return json_build_object(
    'role',          v_role,
    'team',          v_team,
    'alive',         v_alive,
    'mafiaMembers',  v_mates,
    'nightSubmitted', v_night,
    'daySubmitted',   v_day,
    'nightProgress', case when v_role = 'MAFIA'
                       then json_build_object('submitted', v_n_sub, 'expected', v_n_exp)
                       else null end,
    'dayProgress',   json_build_object('submitted', v_d_sub, 'expected', v_d_exp)
  );
end;
$$;

grant execute on function public.my_game_view(uuid) to anon, authenticated;
