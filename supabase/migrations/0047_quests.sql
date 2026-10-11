-- ============================================================
-- 마피아 게임 · 퀘스트
-- ============================================================
-- 종류마다 정해진 간격으로 퀘스트가 하나씩 생긴다. 기준은 가입 시각(profiles.created_at).
--
--   종류     간격    나오는 미션 (무작위 하나)                       보상 (무작위 하나)
--   MAIN     2일    5승 · 3연승 · 7킬 · 총 15일 생존                 별 5 / 코인 20
--   DAILY    1일    1승 · 2승 · 3승                                  별 3 / 코인 12
--   WEEKLY   7일    5승 · 7승 · 4연승                                별 20 / 코인 80
--   MONTHLY  30일   25승 · 10연승 · 50판                             별 75 / 보석 3 / 코인 320
--   YEARLY   365일  300승 · 20연승 · 500판 · 퀘스트 30개 깨기         별 800 / 보석 32 / 코인 3200
--   직업미션은 나중에 만든다. 미션 목록은 quest_pool 에 더하면 된다.
--
-- 퀘스트는 퀘스트 화면을 열 때(my_quests) 밀린 만큼 만든다. 종류마다 20개가 넘으면
-- 오래된 것부터 지운다. 오래 접속하지 않았으면 최근 20개만 만든다.
--
-- 진행도는 퀘스트가 생긴 시각 이후에 끝난 게임으로 센다 (game_records).
--   WIN      이긴 판 수 (승패는 XP 2배·코인과 같은 player_won)
--   STREAK   가장 긴 연승. 지거나 무승부면 끊긴다
--   KILL     내가 죽인 수 — 마피아·스파이는 공격 대상에 표를 냈고 그 밤에 죽으면,
--            자경단·살인자·보안관은 쏜 대상이 그 밤에 죽으면, 저격수는 저격 성공
--   SURVIVE  낮이 끝날 때 살아 있던 날 수의 합
--   PLAY     끝까지 한 판 수
--   CLEAR    보상을 받은 퀘스트 수 (quest_clears, 지워진 퀘스트도 센다)
-- 다 채우면 화면에서 보상을 받는다(claim_quest). 한 번만 받는다.
-- 튜토리얼은 서버를 쓰지 않으므로 기록에 남지 않는다.
-- ============================================================

-- ------------------------------------------------------------
-- 1. 테이블
-- ------------------------------------------------------------

-- 게임이 끝날 때 사람마다 한 줄
create table if not exists public.game_records (
  id       bigserial primary key,
  uid      uuid not null,
  room_id  uuid not null,
  ended_at timestamptz not null default now(),
  won      boolean not null,
  kills    int not null default 0,
  days     int not null default 0
);
create index if not exists game_records_uid_idx on public.game_records (uid, ended_at);

create table if not exists public.quests (
  id            bigserial primary key,
  uid           uuid not null references public.profiles (uid) on delete cascade,
  category      text not null check (category in ('MAIN', 'DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY')),
  slot          int  not null,
  kind          text not null check (kind in ('WIN', 'STREAK', 'KILL', 'SURVIVE', 'PLAY', 'CLEAR')),
  target        int  not null check (target > 0),
  reward_type   text not null check (reward_type in ('STAR', 'GEM', 'COIN')),
  reward_amount int  not null check (reward_amount > 0),
  created_at    timestamptz not null,
  claimed_at    timestamptz,
  unique (uid, category, slot)
);

-- 보상을 받은 기록. 퀘스트가 지워져도 "퀘스트 n개 깨기" 에 센다
create table if not exists public.quest_clears (
  id         bigserial primary key,
  uid        uuid not null,
  quest_id   bigint not null,
  claimed_at timestamptz not null default now()
);
create index if not exists quest_clears_uid_idx on public.quest_clears (uid, claimed_at);

-- 직접 읽기·쓰기는 막고 RPC 로만 다룬다
alter table public.game_records enable row level security;
alter table public.quests       enable row level security;
alter table public.quest_clears enable row level security;
revoke all on public.game_records from anon, authenticated;
revoke all on public.quests       from anon, authenticated;
revoke all on public.quest_clears from anon, authenticated;

-- ------------------------------------------------------------
-- 2. 게임 기록 (내부용)
-- ------------------------------------------------------------

-- 이 판에서 죽인 수
create or replace function public.kills_of(p_room_id uuid, p_uid uuid, p_role text)
returns int
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v int := 0;
begin
  if p_role in ('MAFIA', 'SPY') then
    select count(*) into v
      from public.night_actions n
     where n.room_id = p_room_id and n.actor_uid = p_uid
       and n.action = 'MAFIA_VOTE' and n.target_uid is not null
       and n.target_uid = public.mafia_target(p_room_id, n.day_number)
       and public.died_at_night(p_room_id, n.day_number, n.target_uid);
  elsif p_role in ('VIGILANTE', 'KILLER', 'SHERIFF') then
    select count(*) into v
      from public.night_actions n
     where n.room_id = p_room_id and n.actor_uid = p_uid
       and n.action = p_role and n.target_uid is not null
       and public.died_at_night(p_room_id, n.day_number, n.target_uid);
  elsif p_role = 'ASSASSIN' then
    select count(*) into v
      from public.assassinations a
     where a.room_id = p_room_id and a.actor_uid = p_uid
       and a.resolved = true and a.success;
  end if;
  return coalesce(v, 0);
end;
$$;

-- 낮이 끝날 때 살아 있던 날 수 (시민 XP 와 같은 계산)
create or replace function public.days_survived(p_room_id uuid, p_uid uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int
    from public.public_results r
   where r.room_id = p_room_id and r.kind = 'DAY'
     and (public.death_day(p_room_id, p_uid) is null
          or r.day_number < public.death_day(p_room_id, p_uid));
$$;

revoke all on function public.kills_of(uuid, uuid, text)  from public, anon, authenticated;
revoke all on function public.days_survived(uuid, uuid)   from public, anon, authenticated;

-- ------------------------------------------------------------
-- 3. award_xp: 게임 기록을 남긴다 (0046 과 나머지는 같다)
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
  insert into public.game_records (uid, room_id, won, kills, days)
  select pr.uid, p_room_id,
         public.player_won(p_room_id, p_winner, pr.uid, pr.role, pr.team, pl.alive),
         public.kills_of(p_room_id, pr.uid, pr.role),
         public.days_survived(p_room_id, pr.uid)
    from public.private_roles pr
    join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
   where pr.room_id = p_room_id;
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
  end;
$$;

-- 나올 수 있는 미션 [[종류, 목표], ...]
create or replace function public.quest_pool(p_category text)
returns jsonb
language sql
immutable
as $$
  select case p_category
    when 'MAIN'    then '[["WIN",5],["STREAK",3],["KILL",7],["SURVIVE",15]]'
    when 'DAILY'   then '[["WIN",1],["WIN",2],["WIN",3]]'
    when 'WEEKLY'  then '[["WIN",5],["WIN",7],["STREAK",4]]'
    when 'MONTHLY' then '[["WIN",25],["STREAK",10],["PLAY",50]]'
    when 'YEARLY'  then '[["WIN",300],["STREAK",20],["PLAY",500],["CLEAR",30]]'
  end::jsonb;
$$;

-- 받을 수 있는 보상 [[재화, 개수], ...]
create or replace function public.quest_rewards(p_category text)
returns jsonb
language sql
immutable
as $$
  select case p_category
    when 'MAIN'    then '[["STAR",5],["COIN",20]]'
    when 'DAILY'   then '[["STAR",3],["COIN",12]]'
    when 'WEEKLY'  then '[["STAR",20],["COIN",80]]'
    when 'MONTHLY' then '[["STAR",75],["GEM",3],["COIN",320]]'
    when 'YEARLY'  then '[["STAR",800],["GEM",32],["COIN",3200]]'
  end::jsonb;
$$;

-- 진행도. p_since 이후의 기록만 센다
create or replace function public.quest_progress(p_uid uuid, p_kind text, p_since timestamptz)
returns int
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v int;
begin
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

-- 밀린 퀘스트를 만들고, 종류마다 20개가 넘으면 오래된 것부터 지운다
create or replace function public.generate_quests(p_uid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_anchor timestamptz;
  v_cat    text;
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
      on conflict (uid, category, slot) do nothing;
    end loop;

    delete from public.quests q
     where q.uid = p_uid and q.category = v_cat
       and q.slot not in (
         select q2.slot from public.quests q2
          where q2.uid = p_uid and q2.category = v_cat
          order by q2.slot desc
          limit 20);
  end loop;
end;
$$;

revoke all on function public.quest_progress(uuid, text, timestamptz) from public, anon, authenticated;
revoke all on function public.generate_quests(uuid)                   from public, anon, authenticated;

-- ------------------------------------------------------------
-- 5. RPC — 내 퀘스트 목록
-- ------------------------------------------------------------
-- { quests: [...], next: { MAIN: 다음 퀘스트 시각, ... } }
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
               'kind',         q.kind,
               'target',       q.target,
               'progress',     least(q.target, public.quest_progress(v_uid, q.kind, q.created_at)),
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
        from unnest(array['MAIN', 'DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY']) c)
  );
end;
$$;

grant execute on function public.my_quests() to authenticated;

-- ------------------------------------------------------------
-- 6. RPC — 보상 받기
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
  if public.quest_progress(v_uid, v_q.kind, v_q.created_at) < v_q.target then
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
