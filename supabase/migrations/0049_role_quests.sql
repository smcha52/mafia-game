-- ============================================================
-- 마피아 게임 · 직업 퀘스트
-- ============================================================
-- 퀘스트 화면의 직업미션 탭. 직업마다 7일에 하나씩 퀘스트가 생기고, 직업마다 10개가
-- 넘으면 오래된 것부터 지운다. 기준은 다른 퀘스트와 같이 가입 시각이다.
--
-- 퀘스트는 그 직업의 미션 6개(쉬움·보통·어려움 × 2) 중 무작위 하나다.
-- 보상은 난이도로 정해지고 둘 중 무작위 하나다.
--   쉬움   코인 8  / 별 2
--   보통   코인 20 / 별 5
--   어려움 코인 60 / 별 15
--
--   직업     쉬움                    보통                    어려움
--   시민     5일 생존 · 3승          10일 생존 · 7승         25일 생존 · 15승
--   경찰     마피아 조사 3 · 3승     마피아 조사 5 · 6승     마피아 조사 10 · 10승
--   의사     치료 2 · 3승            치료 4 · 5승            치료 6 · 10승
--   경호원   보호 2 · 3승            보호 4 · 5승            보호 5 · 7승
--   탐정     조사 6 · 3승            조사 10 · 5승           조사 20 · 마피아 조사 6
--   기자     보도 5 · 마피아 보도 2  보도 8 · 마피아 보도 3  보도 12 · 마피아 보도 5
--   영매     직업 확인 3 · 죽음 5    직업 확인 5 · 죽음 8    직업 확인 10 · 죽음 12
--   자경단   3킬 · 3승               5킬 · 5승               8킬 · 7승
--   보안관   마피아 2킬 · 중립 2킬   마피아 4킬 · 중립 4킬   마피아 7킬 · 중립 6킬
--   마피아   5킬 · 3승               7킬 · 5승               10킬 · 8승
--   스파이   5킬 · 직업 확인 3       7킬 · 직업 확인 5       10킬 · 직업 확인 8
--   저격수   저격 2킬 · 3승          저격 4킬 · 5승          저격 6킬 · 7승
--   위조범   위조 4 · 조사당함 1     위조 8 · 조사당함 3     위조 15 · 조사당함 5
--   광대     5표 받기 · 죽기 1       10표 받기 · 죽기 3      20표 받기 · 죽기 5
--   살인자   5킬 · 1대1 3            8킬 · 1대1 5            10킬 · 1대1 8
--   생존자   5일 생존 · 3승          10일 생존 · 5승         15일 생존 · 8승
--
-- 진행도는 퀘스트가 생긴 뒤에 "그 직업으로" 끝낸 게임만 센다. 게임 기록에 직업과
-- 직업별 횟수를 남기므로, 이 파일을 적용하기 전에 끝난 게임은 세지 않는다.
--   WIN·KILL·SURVIVE  0047 과 같다 (그 직업으로 한 판만)
--   FIND_MAFIA    경찰·탐정이 조사한 사람이 실제로 마피아 진영 (XP 와 같이 위조와 무관)
--   INVESTIGATE   탐정이 조사한 횟수
--   HEAL          의사가 공격받은 사람을 치료해 살린 횟수
--   GUARD         경호원이 보호한 사람이 그 밤에 공격받은 횟수
--   REPORT        기자가 취재한 횟수 (성공·실패 모두)
--   REPORT_MAFIA  보도에 성공해 마피아 진영을 밝힌 횟수
--   SEANCE        영매가 사망자 직업을 확인한 횟수
--   DIE           게임이 끝났을 때 죽어 있던 판 수
--   KILL_MAFIA · KILL_NEUTRAL  보안관이 쏜 대상이 그 밤에 죽었고 마피아 진영 · 중립
--   IDENTIFY      스파이가 투표로 직업을 알아낸 횟수
--   FORGE         위조한 횟수
--   FORGE_HIT     위조한 사람이 그 밤에 경찰·탐정·기자·영매에게 조사당한 횟수
--   VOTES         광대가 낮 투표에서 받은 표의 합
--   DUEL          살인자로 이긴 판 수 (1대1 이 되면 살인자가 이긴다)
-- ============================================================

-- ------------------------------------------------------------
-- 1. 테이블
-- ------------------------------------------------------------

alter table public.game_records add column if not exists role  text;
alter table public.game_records add column if not exists stats jsonb not null default '{}'::jsonb;

alter table public.quests add column if not exists role       text;
alter table public.quests add column if not exists difficulty text
  check (difficulty in ('EASY', 'NORMAL', 'HARD'));

alter table public.quests drop constraint if exists quests_category_check;
alter table public.quests add constraint quests_category_check
  check (category in ('MAIN', 'DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY', 'ROLE'));

alter table public.quests drop constraint if exists quests_kind_check;
alter table public.quests add constraint quests_kind_check
  check (kind in ('WIN', 'STREAK', 'KILL', 'SURVIVE', 'PLAY', 'CLEAR',
                  'FIND_MAFIA', 'INVESTIGATE', 'HEAL', 'GUARD', 'REPORT', 'REPORT_MAFIA',
                  'SEANCE', 'DIE', 'KILL_MAFIA', 'KILL_NEUTRAL', 'IDENTIFY',
                  'FORGE', 'FORGE_HIT', 'VOTES', 'DUEL'));

-- 직업 퀘스트는 직업마다 순번이 따로 돈다
alter table public.quests drop constraint if exists quests_uid_category_slot_key;
create unique index if not exists quests_slot_key
  on public.quests (uid, category, coalesce(role, ''), slot);

-- ------------------------------------------------------------
-- 2. 게임 기록 — 직업별 횟수 (내부용)
-- ------------------------------------------------------------
create or replace function public.role_stats(p_room_id uuid, p_uid uuid, p_role text, p_won boolean)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v jsonb := '{}'::jsonb;
  a int;
  b int;
begin
  if exists (select 1 from public.players pl
              where pl.room_id = p_room_id and pl.uid = p_uid and pl.alive = false) then
    v := v || jsonb_build_object('DIE', 1);
  end if;

  case p_role
  when 'POLICE', 'DETECTIVE' then
    select count(*), count(*) filter (where tgt.team = 'MAFIA') into a, b
      from public.private_results r
      left join public.private_roles tgt
        on tgt.room_id = r.room_id and tgt.uid = (r.payload ->> 'targetUid')::uuid
     where r.room_id = p_room_id and r.uid = p_uid and r.kind = p_role;
    v := v || jsonb_build_object('INVESTIGATE', a, 'FIND_MAFIA', b);

  when 'DOCTOR' then
    select count(*) into a
      from public.private_results r
     where r.room_id = p_room_id and r.uid = p_uid and r.kind = 'DOCTOR';
    v := v || jsonb_build_object('HEAL', a);

  when 'BODYGUARD' then
    select count(*) into a
      from public.private_results r
     where r.room_id = p_room_id and r.uid = p_uid and r.kind = 'BODYGUARD';
    v := v || jsonb_build_object('GUARD', a);

  when 'REPORTER' then
    select count(*),
           count(*) filter (where tgt.team = 'MAFIA'
                              and coalesce((r.payload ->> 'success')::boolean, false))
      into a, b
      from public.private_results r
      left join public.private_roles tgt
        on tgt.room_id = r.room_id and tgt.uid = (r.payload ->> 'targetUid')::uuid
     where r.room_id = p_room_id and r.uid = p_uid and r.kind = 'REPORTER';
    v := v || jsonb_build_object('REPORT', a, 'REPORT_MAFIA', b);

  when 'MEDIUM' then
    select count(*) into a
      from public.private_results r
     where r.room_id = p_room_id and r.uid = p_uid and r.kind = 'MEDIUM';
    v := v || jsonb_build_object('SEANCE', a);

  when 'SHERIFF' then
    select count(*) filter (where tgt.team = 'MAFIA'),
           count(*) filter (where tgt.team = 'NEUTRAL')
      into a, b
      from public.night_actions n
      join public.private_roles tgt on tgt.room_id = n.room_id and tgt.uid = n.target_uid
     where n.room_id = p_room_id and n.actor_uid = p_uid
       and n.action = 'SHERIFF' and n.target_uid is not null
       and public.died_at_night(p_room_id, n.day_number, n.target_uid);
    v := v || jsonb_build_object('KILL_MAFIA', a, 'KILL_NEUTRAL', b);

  when 'SPY' then
    select count(*) into a
      from public.private_results r
     where r.room_id = p_room_id and r.uid = p_uid and r.kind = 'SPY';
    v := v || jsonb_build_object('IDENTIFY', a);

  when 'FORGER' then
    select count(*),
           count(*) filter (where exists (
             select 1 from public.night_actions o
              where o.room_id = n.room_id and o.day_number = n.day_number
                and o.action in ('POLICE', 'DETECTIVE', 'REPORTER', 'MEDIUM')
                and o.target_uid = n.target_uid))
      into a, b
      from public.night_actions n
     where n.room_id = p_room_id and n.actor_uid = p_uid
       and n.action = 'FORGE' and n.target_uid is not null;
    v := v || jsonb_build_object('FORGE', a, 'FORGE_HIT', b);

  when 'JESTER' then
    select coalesce(sum((x ->> 'count')::int), 0) into a
      from public.public_results r,
           jsonb_array_elements(r.payload -> 'votes') x
     where r.room_id = p_room_id and r.kind = 'DAY'
       and x ->> 'uid' = p_uid::text;
    v := v || jsonb_build_object('VOTES', a);

  when 'KILLER' then
    v := v || jsonb_build_object('DUEL', case when p_won then 1 else 0 end);

  else
    null;
  end case;

  return v;
end;
$$;

revoke all on function public.role_stats(uuid, uuid, text, boolean) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 3. award_xp: 게임 기록에 직업과 직업별 횟수를 남긴다 (0047 과 나머지는 같다)
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
             public.player_won(p_room_id, p_winner, pr.uid, pr.role, pr.team, pl.alive) as win
        from public.private_roles pr
        join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
       where pr.room_id = p_room_id
    ) b
   where pl.room_id = p_room_id and pl.uid = b.uid;

  -- 익명 사용자(테스트)는 프로필이 없어 건너뛴다. 50레벨(12250 XP)에서 멈춘다
  update public.profiles pf
     set xp = least(12250, pf.xp + pl.xp_gained)
    from public.players pl
   where pl.room_id = p_room_id and pl.uid = pf.uid and pl.xp_gained > 0;

  -- 이긴 사람만 코인을 받는다
  update public.profiles pf
     set coins = pf.coins + public.win_coins()
    from public.private_roles pr
    join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
   where pr.room_id = p_room_id and pf.uid = pr.uid
     and public.player_won(p_room_id, p_winner, pr.uid, pr.role, pr.team, pl.alive);

  -- 퀘스트용 게임 기록
  insert into public.game_records (uid, room_id, won, kills, days, role, stats)
  select w.uid, p_room_id, w.won,
         public.kills_of(p_room_id, w.uid, w.role),
         public.days_survived(p_room_id, w.uid),
         w.role,
         public.role_stats(p_room_id, w.uid, w.role, w.won)
    from (
      select pr.uid, pr.role,
             public.player_won(p_room_id, p_winner, pr.uid, pr.role, pr.team, pl.alive) as won
        from public.private_roles pr
        join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
       where pr.room_id = p_room_id
    ) w;
end;
$$;

revoke all on function public.award_xp(uuid, text) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 4. 퀘스트 규칙 (내부용)
-- ------------------------------------------------------------

create or replace function public.quest_period(p_category text)
returns interval
language sql
immutable
as $$
  select case p_category
    when 'MAIN'    then interval '2 days'
    when 'DAILY'   then interval '1 day'
    when 'WEEKLY'  then interval '7 days'
    when 'MONTHLY' then interval '30 days'
    when 'YEARLY'  then interval '365 days'
    when 'ROLE'    then interval '7 days'
  end;
$$;

-- 직업 퀘스트가 있는 직업
create or replace function public.quest_roles()
returns text[]
language sql
immutable
as $$
  select array['CITIZEN', 'POLICE', 'DOCTOR', 'BODYGUARD', 'DETECTIVE', 'REPORTER', 'MEDIUM',
               'VIGILANTE', 'SHERIFF', 'MAFIA', 'SPY', 'ASSASSIN', 'FORGER',
               'JESTER', 'KILLER', 'SURVIVOR'];
$$;

-- 직업마다 나올 수 있는 미션 [[난이도, 종류, 목표], ...]
create or replace function public.role_quest_pool(p_role text)
returns jsonb
language sql
immutable
as $$
  select case p_role
    when 'CITIZEN'   then '[["EASY","SURVIVE",5],["EASY","WIN",3],["NORMAL","SURVIVE",10],["NORMAL","WIN",7],["HARD","SURVIVE",25],["HARD","WIN",15]]'
    when 'POLICE'    then '[["EASY","FIND_MAFIA",3],["EASY","WIN",3],["NORMAL","FIND_MAFIA",5],["NORMAL","WIN",6],["HARD","FIND_MAFIA",10],["HARD","WIN",10]]'
    when 'DOCTOR'    then '[["EASY","HEAL",2],["EASY","WIN",3],["NORMAL","HEAL",4],["NORMAL","WIN",5],["HARD","HEAL",6],["HARD","WIN",10]]'
    when 'BODYGUARD' then '[["EASY","GUARD",2],["EASY","WIN",3],["NORMAL","GUARD",4],["NORMAL","WIN",5],["HARD","GUARD",5],["HARD","WIN",7]]'
    when 'DETECTIVE' then '[["EASY","INVESTIGATE",6],["EASY","WIN",3],["NORMAL","INVESTIGATE",10],["NORMAL","WIN",5],["HARD","INVESTIGATE",20],["HARD","FIND_MAFIA",6]]'
    when 'REPORTER'  then '[["EASY","REPORT",5],["EASY","REPORT_MAFIA",2],["NORMAL","REPORT",8],["NORMAL","REPORT_MAFIA",3],["HARD","REPORT",12],["HARD","REPORT_MAFIA",5]]'
    when 'MEDIUM'    then '[["EASY","SEANCE",3],["EASY","DIE",5],["NORMAL","SEANCE",5],["NORMAL","DIE",8],["HARD","SEANCE",10],["HARD","DIE",12]]'
    when 'VIGILANTE' then '[["EASY","KILL",3],["EASY","WIN",3],["NORMAL","KILL",5],["NORMAL","WIN",5],["HARD","KILL",8],["HARD","WIN",7]]'
    when 'SHERIFF'   then '[["EASY","KILL_MAFIA",2],["EASY","KILL_NEUTRAL",2],["NORMAL","KILL_MAFIA",4],["NORMAL","KILL_NEUTRAL",4],["HARD","KILL_MAFIA",7],["HARD","KILL_NEUTRAL",6]]'
    when 'MAFIA'     then '[["EASY","KILL",5],["EASY","WIN",3],["NORMAL","KILL",7],["NORMAL","WIN",5],["HARD","KILL",10],["HARD","WIN",8]]'
    when 'SPY'       then '[["EASY","KILL",5],["EASY","IDENTIFY",3],["NORMAL","KILL",7],["NORMAL","IDENTIFY",5],["HARD","KILL",10],["HARD","IDENTIFY",8]]'
    when 'ASSASSIN'  then '[["EASY","KILL",2],["EASY","WIN",3],["NORMAL","KILL",4],["NORMAL","WIN",5],["HARD","KILL",6],["HARD","WIN",7]]'
    when 'FORGER'    then '[["EASY","FORGE",4],["EASY","FORGE_HIT",1],["NORMAL","FORGE",8],["NORMAL","FORGE_HIT",3],["HARD","FORGE",15],["HARD","FORGE_HIT",5]]'
    when 'JESTER'    then '[["EASY","VOTES",5],["EASY","DIE",1],["NORMAL","VOTES",10],["NORMAL","DIE",3],["HARD","VOTES",20],["HARD","DIE",5]]'
    when 'KILLER'    then '[["EASY","KILL",5],["EASY","DUEL",3],["NORMAL","KILL",8],["NORMAL","DUEL",5],["HARD","KILL",10],["HARD","DUEL",8]]'
    when 'SURVIVOR'  then '[["EASY","SURVIVE",5],["EASY","WIN",3],["NORMAL","SURVIVE",10],["NORMAL","WIN",5],["HARD","SURVIVE",15],["HARD","WIN",8]]'
  end::jsonb;
$$;

-- 난이도마다 받을 수 있는 보상 [[재화, 개수], ...]
create or replace function public.role_quest_rewards(p_difficulty text)
returns jsonb
language sql
immutable
as $$
  select case p_difficulty
    when 'EASY'   then '[["COIN",8],["STAR",2]]'
    when 'NORMAL' then '[["COIN",20],["STAR",5]]'
    when 'HARD'   then '[["COIN",60],["STAR",15]]'
  end::jsonb;
$$;

-- 진행도. p_since 이후의 기록만 센다. p_role 이 있으면 그 직업으로 한 판만 센다
drop function if exists public.quest_progress(uuid, text, timestamptz);
create or replace function public.quest_progress(p_uid uuid, p_kind text, p_since timestamptz, p_role text)
returns int
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v int;
begin
  if p_role is not null then
    select case p_kind
             when 'WIN'     then count(*) filter (where g.won)
             when 'KILL'    then sum(g.kills)
             when 'SURVIVE' then sum(g.days)
             else sum(coalesce((g.stats ->> p_kind)::int, 0))
           end
      into v
      from public.game_records g
     where g.uid = p_uid and g.ended_at >= p_since and g.role = p_role;
    return coalesce(v, 0);
  end if;

  case p_kind
  when 'WIN' then
    select count(*) into v from public.game_records g
     where g.uid = p_uid and g.ended_at >= p_since and g.won;
  when 'PLAY' then
    select count(*) into v from public.game_records g
     where g.uid = p_uid and g.ended_at >= p_since;
  when 'KILL' then
    select sum(g.kills) into v from public.game_records g
     where g.uid = p_uid and g.ended_at >= p_since;
  when 'SURVIVE' then
    select sum(g.days) into v from public.game_records g
     where g.uid = p_uid and g.ended_at >= p_since;
  when 'STREAK' then
    -- 진 판이 나올 때마다 묶음 번호가 바뀐다. 묶음 안의 승리 수가 연승
    select max(c) into v from (
      select count(*) as c from (
        select g.won,
               sum(case when g.won then 0 else 1 end) over (order by g.ended_at, g.id) as grp
          from public.game_records g
         where g.uid = p_uid and g.ended_at >= p_since
      ) s
       where s.won
       group by s.grp
    ) x;
  when 'CLEAR' then
    select count(*) into v from public.quest_clears c
     where c.uid = p_uid and c.claimed_at >= p_since;
  else
    v := 0;
  end case;
  return coalesce(v, 0);
end;
$$;

-- 밀린 퀘스트를 만들고, 넘치면 오래된 것부터 지운다 (종류마다 20개, 직업마다 10개)
create or replace function public.generate_quests(p_uid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_anchor timestamptz;
  v_cat    text;
  v_role   text;
  v_period interval;
  v_due    int;
  v_last   int;
  v_pool   jsonb;
  v_reward jsonb;
  v_pick   jsonb;
  v_prize  jsonb;
begin
  -- 같은 사람의 요청이 겹쳐도 한 번만 만들도록 프로필을 잠근다
  select pf.created_at into v_anchor from public.profiles pf where pf.uid = p_uid for update;
  if not found then
    return;
  end if;

  foreach v_cat in array array['MAIN', 'DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'] loop
    v_period := public.quest_period(v_cat);
    -- 가입 시각부터 0번, 간격마다 1번, 2번 …
    v_due := floor(extract(epoch from now() - v_anchor) / extract(epoch from v_period))::int;
    select coalesce(max(q.slot), -1) into v_last
      from public.quests q where q.uid = p_uid and q.category = v_cat;

    v_pool   := public.quest_pool(v_cat);
    v_reward := public.quest_rewards(v_cat);

    for k in greatest(v_last + 1, v_due - 19) .. v_due loop
      v_pick  := v_pool   -> floor(random() * jsonb_array_length(v_pool))::int;
      v_prize := v_reward -> floor(random() * jsonb_array_length(v_reward))::int;
      insert into public.quests (uid, category, slot, kind, target,
                                 reward_type, reward_amount, created_at)
      values (p_uid, v_cat, k, v_pick ->> 0, (v_pick ->> 1)::int,
              v_prize ->> 0, (v_prize ->> 1)::int, v_anchor + v_period * k)
      on conflict do nothing;
    end loop;

    delete from public.quests q
     where q.uid = p_uid and q.category = v_cat
       and q.slot not in (
         select q2.slot from public.quests q2
          where q2.uid = p_uid and q2.category = v_cat
          order by q2.slot desc
          limit 20);
  end loop;

  -- 직업 퀘스트: 직업마다 7일에 하나, 10개까지
  v_period := public.quest_period('ROLE');
  v_due := floor(extract(epoch from now() - v_anchor) / extract(epoch from v_period))::int;

  foreach v_role in array public.quest_roles() loop
    select coalesce(max(q.slot), -1) into v_last
      from public.quests q
     where q.uid = p_uid and q.category = 'ROLE' and q.role = v_role;

    v_pool := public.role_quest_pool(v_role);

    for k in greatest(v_last + 1, v_due - 9) .. v_due loop
      -- 미션 [난이도, 종류, 목표] 를 고르고, 그 난이도의 보상 중 하나를 고른다
      v_pick   := v_pool -> floor(random() * jsonb_array_length(v_pool))::int;
      v_reward := public.role_quest_rewards(v_pick ->> 0);
      v_prize  := v_reward -> floor(random() * jsonb_array_length(v_reward))::int;
      insert into public.quests (uid, category, role, difficulty, slot, kind, target,
                                 reward_type, reward_amount, created_at)
      values (p_uid, 'ROLE', v_role, v_pick ->> 0, k, v_pick ->> 1, (v_pick ->> 2)::int,
              v_prize ->> 0, (v_prize ->> 1)::int, v_anchor + v_period * k)
      on conflict do nothing;
    end loop;

    delete from public.quests q
     where q.uid = p_uid and q.category = 'ROLE' and q.role = v_role
       and q.slot not in (
         select q2.slot from public.quests q2
          where q2.uid = p_uid and q2.category = 'ROLE' and q2.role = v_role
          order by q2.slot desc
          limit 10);
  end loop;
end;
$$;

revoke all on function public.quest_progress(uuid, text, timestamptz, text) from public, anon, authenticated;
revoke all on function public.generate_quests(uuid)                         from public, anon, authenticated;

-- ------------------------------------------------------------
-- 5. RPC — 내 퀘스트 목록 (직업 퀘스트는 role · difficulty 가 함께 온다)
-- ------------------------------------------------------------
-- { quests: [...], next: { MAIN: 다음 퀘스트 시각, ..., ROLE: ... } }
create or replace function public.my_quests()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_anchor timestamptz;
begin
  select pf.created_at into v_anchor from public.profiles pf where pf.uid = v_uid;
  if not found then
    raise exception '로그인이 필요합니다.';
  end if;

  perform public.generate_quests(v_uid);

  return json_build_object(
    'quests', coalesce((
      select json_agg(json_build_object(
               'id',           q.id,
               'category',     q.category,
               'role',         q.role,
               'difficulty',   q.difficulty,
               'kind',         q.kind,
               'target',       q.target,
               'progress',     least(q.target,
                                     public.quest_progress(v_uid, q.kind, q.created_at, q.role)),
               'rewardType',   q.reward_type,
               'rewardAmount', q.reward_amount,
               'createdAt',    q.created_at,
               'claimed',      q.claimed_at is not null)
             order by q.slot desc)
        from public.quests q
       where q.uid = v_uid), '[]'::json),
    'next', (
      select json_object_agg(c, v_anchor + public.quest_period(c) * (
               floor(extract(epoch from now() - v_anchor)
                     / extract(epoch from public.quest_period(c)))::int + 1))
        from unnest(array['MAIN', 'DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY', 'ROLE']) c)
  );
end;
$$;

grant execute on function public.my_quests() to authenticated;

-- ------------------------------------------------------------
-- 6. RPC — 보상 받기 (진행도를 직업까지 넣어 다시 확인한다. 나머지는 0047 과 같다)
-- ------------------------------------------------------------
create or replace function public.claim_quest(p_quest_id bigint)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_q   public.quests%rowtype;
begin
  select * into v_q from public.quests q
   where q.id = p_quest_id and q.uid = v_uid
   for update;
  if not found then
    raise exception '없는 퀘스트입니다.';
  end if;
  if v_q.claimed_at is not null then
    raise exception '이미 보상을 받았습니다.';
  end if;
  if public.quest_progress(v_uid, v_q.kind, v_q.created_at, v_q.role) < v_q.target then
    raise exception '아직 퀘스트를 깨지 못했습니다.';
  end if;

  update public.quests q set claimed_at = now() where q.id = v_q.id;
  insert into public.quest_clears (uid, quest_id) values (v_uid, v_q.id);

  update public.profiles pf
     set stars = pf.stars + case when v_q.reward_type = 'STAR' then v_q.reward_amount else 0 end,
         gems  = pf.gems  + case when v_q.reward_type = 'GEM'  then v_q.reward_amount else 0 end,
         coins = pf.coins + case when v_q.reward_type = 'COIN' then v_q.reward_amount else 0 end
   where pf.uid = v_uid;

  return json_build_object('rewardType', v_q.reward_type, 'rewardAmount', v_q.reward_amount);
end;
$$;

grant execute on function public.claim_quest(bigint) to authenticated;
