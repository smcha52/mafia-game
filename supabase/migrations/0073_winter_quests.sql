-- ============================================================
-- 마피아 게임 · 겨울 이벤트 퀘스트
-- ============================================================
-- 이벤트 퀘스트 탭(quests.category = 'EVENT', 0071)에 겨울 퀘스트를 더한다.
--   겨울 기간(한국 시간 12월 1일 ~ 2월 15일, 0072 상점·화면 theme.js 와 같다)에만
--   3일마다 하나씩 무작위로 생긴다. 기준은 그해 겨울 시작(12월 1일 0시, 한국 시간).
--     WINTER_WIN   겨울 기간에 50승 하기    별 100
--     WINTER_KILL  겨울 기간에 100킬 하기   별 90
--   진행도는 퀘스트가 생긴 뒤, 겨울 기간에 끝난 게임만 센다.
--   겨울이 끝나면 보이지 않고 보상도 받을 수 없다 (할로윈과 같다).
--   세 번째 겨울 퀘스트(별 150)는 나중에 winter_quest_pool 에 더한다.
-- ============================================================

-- ------------------------------------------------------------
-- 1. 겨울 기간 도우미
-- ------------------------------------------------------------

-- 그 시각이 겨울 기간인지 (한국 시간 12월 1일 ~ 2월 15일이 끝날 때까지)
create or replace function public.is_winter_at(p_ts timestamptz)
returns boolean
language sql
stable
as $$
  select p_ts >= timestamptz '2026-12-01 00:00:00+09'
     and (extract(month from p_ts at time zone 'Asia/Seoul') in (12, 1)
       or (extract(month from p_ts at time zone 'Asia/Seoul') = 2
           and extract(day from p_ts at time zone 'Asia/Seoul') <= 15));
$$;

-- 지금이 겨울 기간인지. 겨울에만 여는 이벤트·보상은 이 함수로 기간을 본다
create or replace function public.is_winter()
returns boolean
language sql
stable
as $$
  select public.is_winter_at(now());
$$;

-- 지금 속한 겨울의 시작 (12월 1일 0시, 한국 시간). 1·2월이면 지난해 12월 1일
create or replace function public.winter_start()
returns timestamptz
language sql
stable
as $$
  select timestamptz '2026-12-01 00:00:00+09'
         + public.shop_shift(timestamptz '2026-12-01 00:00:00+09', true);
$$;

-- 겨울 이벤트 퀘스트 [종류, 목표, 보상 재화, 보상 개수]
create or replace function public.winter_quest_pool()
returns jsonb
language sql
immutable
as $$
  select '[["WINTER_WIN",50,"STAR",100],["WINTER_KILL",100,"STAR",90]]'::jsonb;
$$;

-- ------------------------------------------------------------
-- 2. 이벤트 퀘스트 (0071 에 겨울을 더했다)
-- ------------------------------------------------------------

-- 진행도. 겨울 이벤트 종류를 더했다 (0071 과 나머지는 같다)
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
  when 'PUMPKIN_BOX' then
    select count(*) into v from public.box_opens b
     where b.uid = p_uid and b.box = 'PUMPKIN' and b.opened_at >= p_since;
  when 'WITCH_WIN' then
    select count(*) into v from public.game_records g
     where g.uid = p_uid and g.ended_at >= p_since and g.won and g.role = 'WITCH';
  when 'HALLOWEEN_WIN' then
    select count(*) into v from public.game_records g
     where g.uid = p_uid and g.ended_at >= p_since and g.won
       and public.is_halloween_at(g.ended_at);
  when 'WINTER_WIN' then
    select count(*) into v from public.game_records g
     where g.uid = p_uid and g.ended_at >= p_since and g.won
       and public.is_winter_at(g.ended_at);
  when 'WINTER_KILL' then
    select sum(g.kills) into v from public.game_records g
     where g.uid = p_uid and g.ended_at >= p_since
       and public.is_winter_at(g.ended_at);
  else
    v := 0;
  end case;
  return coalesce(v, 0);
end;
$$;

revoke all on function public.quest_progress(uuid, text, timestamptz, text) from public, anon, authenticated;

-- 이벤트 퀘스트를 만든다. 할로윈·겨울 기간에만, 그 이벤트 시작부터 3일마다 (0071 에 겨울을 더했다).
-- 칸 번호는 할로윈 해 * 100 + 순번, 겨울 해 * 100 + 50 + 순번이다 (겨울 순번은 25까지).
-- 이벤트를 연 시각 전의 칸은 만들지 않는다. 겨울 한 번에 25개쯤 생기므로 최근 30개를 남긴다
create or replace function public.generate_event_quests(p_uid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_start  timestamptz;
  v_period interval := public.quest_period('EVENT');
  v_base   int;
  v_due    int;
  v_first  int;
  v_last   int;
  v_pool   jsonb;
  v_pick   jsonb;
begin
  if public.is_halloween() then
    v_start := public.halloween_start();
    v_base  := extract(year from v_start at time zone 'Asia/Seoul')::int * 100;
    v_pool  := public.event_quest_pool();
  elsif public.is_winter() then
    v_start := public.winter_start();
    v_base  := extract(year from v_start at time zone 'Asia/Seoul')::int * 100 + 50;
    v_pool  := public.winter_quest_pool();
  else
    return;
  end if;

  v_due   := floor(extract(epoch from now() - v_start) / extract(epoch from v_period))::int;
  v_first := case when public.event_launch() <= v_start then 0
                  else floor(extract(epoch from public.event_launch() - v_start)
                             / extract(epoch from v_period))::int end;

  select coalesce(max(q.slot), v_base - 1) into v_last
    from public.quests q
   where q.uid = p_uid and q.category = 'EVENT' and q.slot >= v_base and q.slot < v_base + 50;

  for k in greatest(v_last - v_base + 1, v_first, v_due - 29) .. v_due loop
    v_pick := v_pool -> floor(random() * jsonb_array_length(v_pool))::int;
    insert into public.quests (uid, category, slot, kind, target,
                               reward_type, reward_amount, created_at)
    values (p_uid, 'EVENT', v_base + k, v_pick ->> 0, (v_pick ->> 1)::int,
            v_pick ->> 2, (v_pick ->> 3)::int, v_start + v_period * k)
    on conflict do nothing;
  end loop;

  delete from public.quests q
   where q.uid = p_uid and q.category = 'EVENT'
     and q.slot not in (
       select q2.slot from public.quests q2
        where q2.uid = p_uid and q2.category = 'EVENT'
        order by q2.slot desc
        limit 30);
end;
$$;

revoke all on function public.generate_event_quests(uuid) from public, anon, authenticated;

-- 내 퀘스트 목록 — 겨울 이벤트를 더했다 (0071 과 나머지는 같다)
--   이벤트 퀘스트는 지금 진행 중인 이벤트(이번 할로윈 / 이번 겨울) 것만 준다.
--   next.EVENT 는 다음 이벤트 퀘스트 시각 (이벤트 기간이 아니거나 이번 이벤트에 더 없으면 null).
--   halloween · winter 는 지금이 그 기간인지
create or replace function public.my_quests()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_anchor timestamptz;
  v_hw     boolean := public.is_halloween();
  v_winter boolean := public.is_winter();
  v_start  timestamptz := case when public.is_winter() then public.winter_start()
                                else public.halloween_start() end;
  v_enext  timestamptz := null;
begin
  select pf.created_at into v_anchor from public.profiles pf where pf.uid = v_uid;
  if not found then
    raise exception '로그인이 필요합니다.';
  end if;

  perform public.generate_quests(v_uid);
  perform public.generate_event_quests(v_uid);

  if v_hw or v_winter then
    v_enext := v_start + public.quest_period('EVENT') * (
                 floor(extract(epoch from now() - v_start)
                       / extract(epoch from public.quest_period('EVENT')))::int + 1);
    if not (case when v_winter then public.is_winter_at(v_enext)
                 else public.is_halloween_at(v_enext) end) then
      v_enext := null;
    end if;
  end if;

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
       where q.uid = v_uid
         and (q.category <> 'EVENT' or ((v_hw or v_winter) and q.created_at >= v_start))), '[]'::json),
    'next', (
      select json_object_agg(c, v_anchor + public.quest_period(c) * (
               floor(extract(epoch from now() - v_anchor)
                     / extract(epoch from public.quest_period(c)))::int + 1))
        from unnest(array['MAIN', 'DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY', 'ROLE']) c
    )::jsonb || jsonb_build_object('EVENT', v_enext),
    'halloween', v_hw,
    'winter', v_winter
  );
end;
$$;

grant execute on function public.my_quests() to authenticated;

-- 보상 받기 — 이벤트 퀘스트는 그 기간에만 받는다. 겨울을 더했다 (0071 과 나머지는 같다)
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
  if v_q.category = 'EVENT'
     and not ((public.is_halloween() and v_q.created_at >= public.halloween_start())
              or (public.is_winter() and v_q.created_at >= public.winter_start())) then
    raise exception '이벤트 기간이 끝났습니다.';
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
