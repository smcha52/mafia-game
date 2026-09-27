-- 0023_day_result_reveal.sql
-- 낮 투표 결과를 밤에 공개한다.
--
-- 이전에는 public_results(kind='DAY').payload 에 executed(uid 또는 null)만 남아
-- 밤이 되어도 누가 처형됐는지, 동점이었는지 알 수 없었다.
--
-- 추가 필드
--   tie            최다 득표자가 2명 이상이라 처형하지 않았으면 true (D-2)
--   executedTeam   처형된 사람의 진영. 시민/마피아 진영만 채운다
--   executedRole   처형된 사람이 중립 진영이면 진영 대신 직업을 그대로 공개한다
--
-- 광대는 처형되는 즉시 단독 승리한다(§4.1). 이는 check_winner 가 이미 처리하므로
-- 판정 순서는 바꾸지 않는다. 공개 필드는 게임 종료 전에 먼저 기록된다.
--
-- resolve_day 시그니처는 그대로이므로 create or replace 로 충분하다.
-- 본문은 0019 에서 그대로 옮기고 공개 결과 기록 부분만 바꿨다.

create or replace function public.resolve_day(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day      int;
  v_max      int;
  v_target   uuid;
  v_ties     int;
  v_executed uuid := null;
  v_team     text := null;
  v_role     text := null;
  v_winner   text;
begin
  select r.day_number, r.max_days into v_day, v_max
    from public.rooms r where r.id = p_room_id;

  with tally as (
    select d.target_uid as t_uid, count(*) as c
      from public.day_votes d
     where d.room_id = p_room_id and d.day_number = v_day
     group by d.target_uid
  ), mx as (
    select max(c) as m from tally
  )
  select count(*), (array_agg(tally.t_uid))[1]
    into v_ties, v_target
    from tally join mx on tally.c = mx.m;

  if coalesce(v_ties, 0) = 1 and v_target is not null then
    update public.players pl
       set alive = false
     where pl.room_id = p_room_id and pl.uid = v_target and pl.alive = true;
    if found then
      v_executed := v_target;
    end if;
  end if;

  if v_executed is not null then
    select pr.team, pr.role into v_team, v_role
      from public.private_roles pr
     where pr.room_id = p_room_id and pr.uid = v_executed;
  end if;

  insert into public.public_results (room_id, day_number, kind, payload)
  values (p_room_id, v_day, 'DAY', jsonb_build_object(
    'executed',     v_executed,
    'tie',          coalesce(v_ties, 0) > 1,
    'executedTeam', case when v_team = 'NEUTRAL' then null else v_team end,
    'executedRole', case when v_team = 'NEUTRAL' then v_role else null end))
  on conflict (room_id, day_number, kind) do update
    set payload = public.public_results.payload || excluded.payload;

  v_winner := public.check_winner(p_room_id, v_executed);
  if v_winner is not null then
    perform public.end_game(p_room_id, v_winner);
    return;
  end if;

  if v_day >= v_max then
    perform public.end_game(p_room_id, 'DRAW');
    return;
  end if;

  perform public.enter_phase(p_room_id, 'NIGHT', v_day + 1);
end;
$$;
revoke all on function public.resolve_day(uuid) from public, anon, authenticated;
