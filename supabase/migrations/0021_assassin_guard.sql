-- 0021_assassin_guard.sql
-- 암살 가능 판정을 고친다.
--
-- 문제: can_assassinate 는 "나 말고 살아있는 사람 중 시민이 아닌 사람"만 찾았다.
-- 암살자는 mafiaMembers 로 같은 편을 전부 알고 있으므로, 팀원 한 명만 살아 있으면
-- 조건이 통과된다. 실제 지목 대상이 전원 시민이어도 "시민"이라고만 찍으면
-- 100% 성공하는 무위험 저격이 된다. (YUX83H 판에서 확인)
--
-- 수정: 판정 대상에서 내 진영을 뺀다. 남은 상대가 전부 시민이면 막는다.
-- 즉 경찰·의사·경호원·탐정·기자·영매(시민팀) 또는 광대(중립)가
-- 한 명이라도 살아 있어야 저격할 수 있다.
--
-- 시그니처가 같으므로 create or replace 로 충분하다 (PGRST203 위험 없음).
-- can_assassinate 는 submit_assassination(0019) 과 my_game_view(0020) 가
-- 함께 쓰는 단일 지점이라, 이 함수만 고치면 제출과 화면이 모두 따라온다.

create or replace function public.can_assassinate(p_room_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
      from public.private_roles pr
      join public.players pl
        on pl.room_id = pr.room_id and pl.uid = pr.uid
     where pr.room_id = p_room_id
       and pl.alive = true
       and pr.uid <> auth.uid()
       and pr.role <> 'CITIZEN'
       -- 같은 편은 누군지 이미 아니까 판정에서 뺀다
       and public.team_of(pr.role) is distinct from (
             select public.team_of(me.role)
               from public.private_roles me
              where me.room_id = p_room_id and me.uid = auth.uid()
           )
  );
$$;

grant execute on function public.can_assassinate(uuid) to anon, authenticated;


-- 안내 문구도 맞춘다. 본문은 0019 에서 그대로 옮기고 메시지만 바꿨다.
create or replace function public.submit_assassination(
  p_room_id uuid, p_target_uid uuid, p_guess text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_room    public.rooms%rowtype;
  v_role    text;
  v_alive   boolean;
  v_dead    uuid;
  v_winner  text;
  v_d_sub   int;
  v_d_exp   int;
begin
  select * into v_room from public.rooms r where r.id = p_room_id for update;
  if not found then
    raise exception '존재하지 않는 방입니다.';
  end if;
  if v_room.phase not in ('NIGHT', 'DAY') then
    raise exception '지금은 저격할 수 없습니다.';
  end if;

  select pr.role into v_role
    from public.private_roles pr
   where pr.room_id = p_room_id and pr.uid = v_uid;
  if not found then
    raise exception '이 방의 참가자가 아닙니다.';
  end if;
  if v_role <> 'ASSASSIN' then
    raise exception '암살자만 사용할 수 있습니다.';
  end if;

  select pl.alive into v_alive
    from public.players pl
   where pl.room_id = p_room_id and pl.uid = v_uid;
  if not v_alive then
    raise exception '사망한 참가자는 능력을 사용할 수 없습니다.';
  end if;

  if exists (
    select 1 from public.assassinations a
     where a.room_id = p_room_id and a.day_number = v_room.day_number
       and a.phase = v_room.phase and a.actor_uid = v_uid
  ) then
    raise exception '이번 %에는 이미 저격했습니다.',
      case when v_room.phase = 'NIGHT' then '밤' else '낮' end;
  end if;

  if not public.can_assassinate(p_room_id) then
    raise exception '상대가 모두 시민이면 저격할 수 없습니다.';
  end if;

  if p_target_uid = v_uid then
    raise exception '자신을 지목할 수 없습니다.';
  end if;
  if not exists (
    select 1 from public.players pl
     where pl.room_id = p_room_id and pl.uid = p_target_uid and pl.alive = true
  ) then
    raise exception '살아 있는 참가자만 지목할 수 있습니다.';
  end if;

  if p_guess is null or p_guess not in
     ('CITIZEN','MAFIA','POLICE','DOCTOR','BODYGUARD',
      'DETECTIVE','REPORTER','MEDIUM','SPY','JESTER','ASSASSIN') then
    raise exception '직업을 선택해 주세요.';
  end if;

  insert into public.assassinations
    (room_id, day_number, phase, actor_uid, target_uid, guess_role)
  values
    (p_room_id, v_room.day_number, v_room.phase, v_uid, p_target_uid, p_guess);

  -- 밤이면 밤 처리 때 함께 계산한다
  if v_room.phase = 'NIGHT' then
    return json_build_object('resolved', false, 'phase', 'NIGHT');
  end if;

  -- 낮이면 즉시 처리한다
  v_dead := public.apply_assassination(p_room_id, v_room.day_number, 'DAY', v_uid);

  -- 낮 사망자를 공개 결과에 남긴다. executed 는 낮 처리에서 합쳐진다.
  if v_dead is not null then
    insert into public.public_results (room_id, day_number, kind, payload)
    values (p_room_id, v_room.day_number, 'DAY',
            jsonb_build_object('dayDeaths', jsonb_build_array(v_dead)))
    on conflict (room_id, day_number, kind) do update
      set payload = public.public_results.payload
                    || jsonb_build_object('dayDeaths',
                         coalesce(public.public_results.payload -> 'dayDeaths', '[]'::jsonb)
                         || jsonb_build_array(v_dead));
  end if;

  v_winner := public.check_winner(p_room_id);
  if v_winner is not null then
    perform public.end_game(p_room_id, v_winner);
    return json_build_object('resolved', true, 'phase', 'DAY', 'ended', true);
  end if;

  -- 사망으로 투표 인원이 줄어 낮이 이미 끝났을 수 있다
  select count(*) into v_d_exp
    from public.players pl where pl.room_id = p_room_id and pl.alive = true;
  select count(*) into v_d_sub
    from public.day_votes d
   where d.room_id = p_room_id and d.day_number = v_room.day_number;

  if v_d_sub >= v_d_exp then
    perform public.resolve_day(p_room_id);
  end if;

  return json_build_object('resolved', true, 'phase', 'DAY');
end;
$$;

grant execute on function public.submit_assassination(uuid, uuid, text) to authenticated;
