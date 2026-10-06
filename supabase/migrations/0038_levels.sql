-- ============================================================
-- 마피아 게임 · 레벨 / XP
-- ============================================================
-- 레벨은 1~50. 레벨 n 에서 n+1 로 올라가려면 n×10 XP 가 필요하다.
--   (4→5 는 40 XP, 34→35 는 340 XP)
-- 레벨 L 이 되는 누적 XP = 5·L·(L-1). 50레벨 = 12250 XP 에서 더 쌓이지 않는다.
-- 레벨 계산은 화면(src/lib/level.js)이 profiles.xp 로 한다.
--
-- XP 는 게임이 끝날 때(end_game) 그 판의 기록으로 한 번에 계산한다.
-- 밤·낮 처리 함수는 바꾸지 않는다. 기록(night_actions, private_results,
-- public_results, assassinations)은 다시하기 전까지 남아 있다.
--
-- 직업별 XP (판 중 누적)
--   시민·생존자  낮이 끝날 때 살아 있으면 하루당 2
--   경찰        조사한 사람의 실제 진영 — 시민 1, 중립 3, 마피아 5
--   의사        공격받은 사람을 살리면 7
--   경호원      보호할 때마다 — 대신 죽어 막으면 5, 아니면 1
--   탐정        조사할 때마다 3
--   기자        보도 성공 시 실제 진영 — 마피아 5, 그 외 2
--   영매        사망자 조사마다 2, 자신이 죽으면 3 (한 번)
--   자경단      대상이 그 밤에 죽으면 3
--   보안관      마피아·중립을 쏘면 10, 시민을 쏘면 1
--   마피아      마피아 공격에 참여하고 대상이 그 밤에 죽으면 2
--   스파이      마피아와 같은 공격 2 + 투표로 직업을 알아낼 때마다 2
--   암살자      저격 성공 15, 실패 2
--   위조범      다른 사람을 위조할 때마다 5
--   광대        낮 투표에서 받은 1표당 2
--   살인자      대상이 그 밤에 죽으면 3
-- 게임이 끝나면 이긴 사람은 2배, 진 사람·무승부는 그대로 계정에 더한다.
-- 튜토리얼은 서버를 쓰지 않으므로 XP 가 없다.
-- ============================================================

alter table public.profiles add column if not exists xp int not null default 0;

-- 이번 판의 XP. 게임이 끝나기 전에는 null
alter table public.players add column if not exists xp_base   int;
alter table public.players add column if not exists xp_gained int;

-- ------------------------------------------------------------
-- 이긴 사람인지. 시민·마피아 승리는 진영, 광대·살인자·생존자는 직업으로 본다
-- ------------------------------------------------------------
create or replace function public.is_winner(p_winner text, p_role text, p_team text)
returns boolean
language sql
immutable
as $$
  select case
    when p_winner in ('CITIZEN', 'MAFIA') then p_team = p_winner
    when p_winner = 'DRAW' then false
    else p_role = p_winner
  end;
$$;

-- ------------------------------------------------------------
-- 그 밤 마피아 진영의 공격 대상. 동점이면 null (resolve_night 와 같은 규칙)
-- ------------------------------------------------------------
create or replace function public.mafia_target(p_room_id uuid, p_day int)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  with tally as (
    select n.target_uid as t_uid, count(*) as c
      from public.night_actions n
     where n.room_id = p_room_id and n.day_number = p_day
       and n.action = 'MAFIA_VOTE' and n.target_uid is not null
     group by n.target_uid
  ), top as (
    select t_uid from tally where c = (select max(c) from tally)
  )
  select case when (select count(*) from top) = 1 then (select t_uid from top) end;
$$;

-- 그 밤에 이 사람이 죽었는지
create or replace function public.died_at_night(p_room_id uuid, p_day int, p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.public_results r
     where r.room_id = p_room_id and r.day_number = p_day and r.kind = 'NIGHT'
       and r.payload -> 'nightDeaths' ? p_uid::text
  );
$$;

-- 이 사람이 죽은 날. 그날 밤 또는 그날 낮에 죽었다. 살아 있으면 null
create or replace function public.death_day(p_room_id uuid, p_uid uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select min(d) from (
    select r.day_number as d
      from public.public_results r
     where r.room_id = p_room_id and r.kind = 'NIGHT'
       and r.payload -> 'nightDeaths' ? p_uid::text
    union all
    select r.day_number
      from public.public_results r
     where r.room_id = p_room_id and r.kind = 'DAY'
       and r.payload ->> 'executed' = p_uid::text
    union all
    select a.day_number
      from public.assassinations a
     where a.room_id = p_room_id and a.phase = 'DAY' and a.resolved = true
       and ((a.success and a.target_uid = p_uid) or (not a.success and a.actor_uid = p_uid))
  ) x;
$$;

-- ------------------------------------------------------------
-- 이번 판에서 한 사람이 모은 XP (승패 배수 전)
-- ------------------------------------------------------------
create or replace function public.base_xp(p_room_id uuid, p_uid uuid, p_role text)
returns int
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_xp    int := 0;
  v_extra int := 0;
  v_death int;
begin
  case p_role
  when 'CITIZEN', 'SURVIVOR' then
    v_death := public.death_day(p_room_id, p_uid);
    select 2 * count(*) into v_xp
      from public.public_results r
     where r.room_id = p_room_id and r.kind = 'DAY'
       and (v_death is null or r.day_number < v_death);

  when 'POLICE' then
    select coalesce(sum(case tgt.team when 'MAFIA' then 5 when 'NEUTRAL' then 3 else 1 end), 0)
      into v_xp
      from public.private_results r
      join public.private_roles tgt
        on tgt.room_id = r.room_id and tgt.uid = (r.payload ->> 'targetUid')::uuid
     where r.room_id = p_room_id and r.uid = p_uid and r.kind = 'POLICE';

  when 'DOCTOR' then
    select 7 * count(*) into v_xp
      from public.private_results r
     where r.room_id = p_room_id and r.uid = p_uid and r.kind = 'DOCTOR';

  when 'BODYGUARD' then
    select coalesce(sum(case when coalesce((r.payload ->> 'sacrificed')::boolean, false)
                             then 5 else 1 end), 0)
      into v_xp
      from public.night_actions n
      left join public.private_results r
        on r.room_id = n.room_id and r.uid = n.actor_uid
       and r.day_number = n.day_number and r.kind = 'BODYGUARD'
     where n.room_id = p_room_id and n.actor_uid = p_uid
       and n.action = 'BODYGUARD' and n.target_uid is not null;

  when 'DETECTIVE' then
    select 3 * count(*) into v_xp
      from public.private_results r
     where r.room_id = p_room_id and r.uid = p_uid and r.kind = 'DETECTIVE';

  when 'REPORTER' then
    select coalesce(sum(case tgt.team when 'MAFIA' then 5 else 2 end), 0)
      into v_xp
      from public.private_results r
      join public.private_roles tgt
        on tgt.room_id = r.room_id and tgt.uid = (r.payload ->> 'targetUid')::uuid
     where r.room_id = p_room_id and r.uid = p_uid and r.kind = 'REPORTER'
       and coalesce((r.payload ->> 'success')::boolean, false);

  when 'MEDIUM' then
    select 2 * count(*) into v_xp
      from public.private_results r
     where r.room_id = p_room_id and r.uid = p_uid and r.kind = 'MEDIUM';
    if exists (select 1 from public.players pl
                where pl.room_id = p_room_id and pl.uid = p_uid and pl.alive = false) then
      v_xp := v_xp + 3;
    end if;

  when 'VIGILANTE', 'KILLER' then
    select 3 * count(*) into v_xp
      from public.night_actions n
     where n.room_id = p_room_id and n.actor_uid = p_uid
       and n.action = p_role and n.target_uid is not null
       and public.died_at_night(p_room_id, n.day_number, n.target_uid);

  when 'SHERIFF' then
    select coalesce(sum(case when tgt.team = 'CITIZEN' then 1 else 10 end), 0)
      into v_xp
      from public.night_actions n
      join public.private_roles tgt on tgt.room_id = n.room_id and tgt.uid = n.target_uid
     where n.room_id = p_room_id and n.actor_uid = p_uid
       and n.action = 'SHERIFF' and n.target_uid is not null;

  when 'MAFIA', 'SPY' then
    select 2 * count(*) into v_xp
      from public.night_actions n
     where n.room_id = p_room_id and n.actor_uid = p_uid
       and n.action = 'MAFIA_VOTE'
       and public.mafia_target(p_room_id, n.day_number) is not null
       and public.died_at_night(p_room_id, n.day_number,
                                public.mafia_target(p_room_id, n.day_number));
    if p_role = 'SPY' then
      select 2 * count(*) into v_extra
        from public.private_results r
       where r.room_id = p_room_id and r.uid = p_uid and r.kind = 'SPY';
      v_xp := v_xp + v_extra;
    end if;

  when 'ASSASSIN' then
    select coalesce(sum(case when a.success then 15 else 2 end), 0)
      into v_xp
      from public.assassinations a
     where a.room_id = p_room_id and a.actor_uid = p_uid and a.resolved = true;

  when 'FORGER' then
    select 5 * count(*) into v_xp
      from public.night_actions n
     where n.room_id = p_room_id and n.actor_uid = p_uid
       and n.action = 'FORGE' and n.target_uid is not null and n.target_uid <> p_uid;

  when 'JESTER' then
    select coalesce(2 * sum((v ->> 'count')::int), 0) into v_xp
      from public.public_results r,
           jsonb_array_elements(r.payload -> 'votes') v
     where r.room_id = p_room_id and r.kind = 'DAY'
       and v ->> 'uid' = p_uid::text;

  else
    v_xp := 0;
  end case;

  return coalesce(v_xp, 0);
end;
$$;

-- ------------------------------------------------------------
-- 판이 끝날 때 XP 를 계산해 참가자와 계정에 남긴다. 한 판에 한 번만
-- ------------------------------------------------------------
create or replace function public.award_xp(p_room_id uuid, p_winner text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (select 1 from public.players pl
              where pl.room_id = p_room_id and pl.xp_gained is not null) then
    return;
  end if;

  update public.players pl
     set xp_base   = b.base,
         xp_gained = b.base * case when b.win then 2 else 1 end
    from (
      select pr.uid,
             public.base_xp(p_room_id, pr.uid, pr.role) as base,
             public.is_winner(p_winner, pr.role, pr.team) as win
        from public.private_roles pr
       where pr.room_id = p_room_id
    ) b
   where pl.room_id = p_room_id and pl.uid = b.uid;

  -- 익명 사용자(테스트)는 프로필이 없어 건너뛴다. 50레벨(12250 XP)에서 멈춘다
  update public.profiles pf
     set xp = least(12250, pf.xp + pl.xp_gained)
    from public.players pl
   where pl.room_id = p_room_id and pl.uid = pf.uid and pl.xp_gained > 0;
end;
$$;

-- ------------------------------------------------------------
-- end_game: XP 지급을 더한다 (0004 와 나머지는 같다)
-- ------------------------------------------------------------
create or replace function public.end_game(p_room_id uuid, p_winner text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.players pl
     set team = pr.team
    from public.private_roles pr
   where pr.room_id = pl.room_id
     and pr.uid = pl.uid
     and pl.room_id = p_room_id;

  perform public.award_xp(p_room_id, p_winner);

  update public.rooms r
     set phase = 'ENDED', winner = p_winner, phase_deadline = null
   where r.id = p_room_id;
end;
$$;

-- ------------------------------------------------------------
-- restart_game: 이번 판 XP 를 비운다 (0019 와 나머지는 같다)
-- ------------------------------------------------------------
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

  delete from public.private_results where room_id = p_room_id;
  delete from public.public_results  where room_id = p_room_id;
  delete from public.night_actions   where room_id = p_room_id;
  delete from public.assassinations  where room_id = p_room_id;
  delete from public.day_votes       where room_id = p_room_id;
  delete from public.private_roles   where room_id = p_room_id;
  delete from public.chat_messages   where room_id = p_room_id;

  update public.players pl
     set alive          = true,
         ability_used   = false,
         last_target_id = null,
         team           = null,
         xp_base        = null,
         xp_gained      = null,
         is_ready       = pl.is_host
   where pl.room_id = p_room_id;

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

-- ------------------------------------------------------------
-- final_roles: 사람마다 이번 판 XP 를 함께 준다 (0002 와 나머지는 같다)
-- ------------------------------------------------------------
create or replace function public.final_roles(p_room_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phase text;
begin
  if not public.is_room_member(p_room_id) then
    raise exception '이 방의 참가자가 아닙니다.';
  end if;

  select r.phase into v_phase from public.rooms r where r.id = p_room_id;
  if v_phase <> 'ENDED' then
    raise exception '게임이 끝난 뒤에만 볼 수 있습니다.';
  end if;

  return (
    select json_agg(json_build_object(
             'uid', pl.uid, 'nickname', pl.nickname,
             'role', pr.role, 'team', pr.team, 'alive', pl.alive,
             'xpBase', pl.xp_base, 'xpGained', pl.xp_gained)
           order by pl.joined_at)
      from public.private_roles pr
      join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
     where pr.room_id = p_room_id
  );
end;
$$;

-- 내부용 함수는 화면에서 직접 부를 수 없게 한다
revoke all on function public.end_game(uuid, text)            from public, anon, authenticated;
revoke all on function public.award_xp(uuid, text)            from public, anon, authenticated;
revoke all on function public.base_xp(uuid, uuid, text)       from public, anon, authenticated;
revoke all on function public.death_day(uuid, uuid)           from public, anon, authenticated;
revoke all on function public.died_at_night(uuid, int, uuid)  from public, anon, authenticated;
revoke all on function public.mafia_target(uuid, int)         from public, anon, authenticated;
