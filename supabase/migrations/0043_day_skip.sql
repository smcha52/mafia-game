-- ============================================================
-- 마피아 게임 · 낮 투표 건너뛰기
-- ============================================================
-- 낮 투표에 "아무도 죽지 않음: 건너뛰기" 를 고를 수 있다.
-- 건너뛰기 표는 day_votes.target_uid 에 빈 uuid(00000000-...) 로 남긴다.
--
--   · 건너뛰기가 생존자 과반수면 아무도 처형되지 않는다.
--   · 과반수가 아니어도 건너뛰기를 후보 하나처럼 센다.
--     건너뛰기가 최다 득표자보다 많거나 같으면 아무도 처형되지 않는다.
--   · 그 밖에는 기존 규칙 그대로. 최다 득표자가 1명일 때만 처형한다.
--
-- 결과에 skipVotes(건너뛰기 표 수)와 skipped(건너뛰기로 넘어갔는지)를 더한다.
-- votes(사람별 득표 수)에는 건너뛰기를 넣지 않는다.
-- ============================================================

create or replace function public.skip_vote_uid()
returns uuid
language sql
immutable
as $$ select '00000000-0000-0000-0000-000000000000'::uuid $$;

-- ------------------------------------------------------------
-- 1. 낮 투표 제출 — 0011 본문에 건너뛰기를 더했다
-- ------------------------------------------------------------

create or replace function public.submit_day_vote(p_room_id uuid, p_target_uid uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_room      public.rooms%rowtype;
  v_role      text;
  v_alive     boolean;
  v_t_role    text;
  v_t_nick    text;
  v_expected  int;
  v_submitted int;
begin
  select * into v_room from public.rooms r where r.id = p_room_id;
  if not found then
    raise exception '존재하지 않는 방입니다.';
  end if;
  if v_room.phase <> 'DAY' then
    raise exception '낮에만 투표할 수 있습니다.';
  end if;

  select pl.alive into v_alive
    from public.players pl
   where pl.room_id = p_room_id and pl.uid = v_uid;
  if not found then
    raise exception '이 방의 참가자가 아닙니다.';
  end if;
  if not v_alive then
    raise exception '사망한 참가자는 투표할 수 없습니다.';
  end if;

  if p_target_uid is distinct from public.skip_vote_uid() and not exists (
    select 1 from public.players pl
     where pl.room_id = p_room_id and pl.uid = p_target_uid and pl.alive = true
  ) then
    raise exception '살아 있는 참가자만 지목할 수 있습니다.';
  end if;

  -- 제출한 뒤에는 바꿀 수 없다 (§2.9 를 전원에게 적용)
  if exists (
    select 1 from public.day_votes d
     where d.room_id = p_room_id and d.day_number = v_room.day_number
       and d.voter_uid = v_uid
  ) then
    raise exception '이미 투표했습니다. 변경할 수 없습니다.';
  end if;

  insert into public.day_votes (room_id, day_number, voter_uid, target_uid)
  values (p_room_id, v_room.day_number, v_uid, p_target_uid);

  -- 스파이는 투표를 확정하는 순간 대상의 정확한 직업을 확인한다.
  -- 확률이 아니라 항상 확인된다. 투표가 하루 한 번이므로
  -- "하루에 한 번만" 제한은 자동으로 지켜진다.
  select pr.role into v_role
    from public.private_roles pr
   where pr.room_id = p_room_id and pr.uid = v_uid;

  -- 건너뛰기를 고른 스파이는 확인할 대상이 없다
  if v_role = 'SPY' and p_target_uid <> public.skip_vote_uid() then
    select pr.role, pl.nickname into v_t_role, v_t_nick
      from public.private_roles pr
      join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
     where pr.room_id = p_room_id and pr.uid = p_target_uid;

    insert into public.private_results (room_id, uid, day_number, kind, payload)
    values (p_room_id, v_uid, v_room.day_number, 'SPY',
            jsonb_build_object('targetUid', p_target_uid,
                               'targetNickname', v_t_nick,
                               'role', v_t_role))
    on conflict (room_id, uid, day_number, kind) do update set payload = excluded.payload;
  end if;

  select count(*) into v_expected
    from public.players pl
   where pl.room_id = p_room_id and pl.alive = true;

  select count(*) into v_submitted
    from public.day_votes d
   where d.room_id = p_room_id and d.day_number = v_room.day_number;

  if v_submitted >= v_expected then
    perform public.resolve_day(p_room_id);
    return json_build_object('resolved', true);
  end if;

  return json_build_object('resolved', false,
                           'submitted', v_submitted, 'expected', v_expected);
end;
$$;

grant execute on function public.submit_day_vote(uuid, uuid) to anon, authenticated;

-- ------------------------------------------------------------
-- 2. 낮 처리 — 0035 본문에 건너뛰기를 더했다
-- ------------------------------------------------------------

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
  v_top      int;
  v_votes    jsonb;
  v_skip     int;
  v_skipped  boolean;
  v_executed uuid := null;
  v_team     text := null;
  v_role     text := null;
  v_winner   text;
begin
  select r.day_number, r.max_days into v_day, v_max
    from public.rooms r where r.id = p_room_id;

  -- 건너뛰기 표 수
  select count(*) into v_skip
    from public.day_votes d
   where d.room_id = p_room_id and d.day_number = v_day
     and d.target_uid = public.skip_vote_uid();

  with tally as (
    select d.target_uid as t_uid, count(*) as c
      from public.day_votes d
     where d.room_id = p_room_id and d.day_number = v_day
       and d.target_uid <> public.skip_vote_uid()
     group by d.target_uid
  ), mx as (
    select max(c) as m from tally
  )
  select count(*), (array_agg(tally.t_uid))[1], max(mx.m)
    into v_ties, v_target, v_top
    from tally join mx on tally.c = mx.m;

  -- 사람별 득표 수 (많은 순)
  select coalesce(jsonb_agg(jsonb_build_object('uid', t.t_uid, 'count', t.c)
                            order by t.c desc), '[]'::jsonb)
    into v_votes
    from (
      select d.target_uid as t_uid, count(*) as c
        from public.day_votes d
       where d.room_id = p_room_id and d.day_number = v_day
         and d.target_uid <> public.skip_vote_uid()
       group by d.target_uid
    ) t;

  -- 건너뛰기를 후보 하나처럼 센다. 최다 득표자보다 많거나 같으면 아무도 처형하지 않는다.
  -- 건너뛰기가 생존자 과반수면 누구도 그보다 많을 수 없으므로 여기에 포함된다.
  v_skipped := v_skip > 0 and v_skip >= coalesce(v_top, 0);

  if not v_skipped and coalesce(v_ties, 0) = 1 and v_target is not null then
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
    'executed',      v_executed,
    'executedVotes', case when v_executed is not null then v_top else null end,
    'votes',         v_votes,
    'tie',           not v_skipped and coalesce(v_ties, 0) > 1,
    'skipVotes',     v_skip,
    'skipped',       v_skipped,
    'executedTeam',  case when v_team = 'NEUTRAL' then null else v_team end,
    'executedRole',  case when v_team = 'NEUTRAL' then v_role else null end))
  on conflict (room_id, day_number, kind) do update
    set payload = public.public_results.payload || excluded.payload;

  v_winner := public.check_winner(p_room_id, v_executed);
  if v_winner is not null then
    perform public.end_game(p_room_id, v_winner);
    return;
  end if;

  -- 생존자: 목표 날의 낮이 끝날 때 살아 있으면 단독 승리 (§4.1-3)
  if v_day >= coalesce(public.survivor_target(v_max), v_max + 1) and exists (
    select 1
      from public.private_roles pr
      join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
     where pr.room_id = p_room_id and pr.role = 'SURVIVOR' and pl.alive = true
  ) then
    perform public.end_game(p_room_id, 'SURVIVOR');
    return;
  end if;

  if v_day >= v_max then
    perform public.end_game(p_room_id, 'DRAW');
    return;
  end if;

  -- 밤은 결과 시간이 끝난 뒤 tick_phase 가 연다
  perform public.enter_phase(p_room_id, 'DAY_RESULT', v_day);
end;
$$;
revoke all on function public.resolve_day(uuid) from public, anon, authenticated;
