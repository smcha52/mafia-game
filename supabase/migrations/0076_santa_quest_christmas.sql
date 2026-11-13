-- ============================================================
-- 마피아 게임 · 겨울 퀘스트 "산타로 15승" 은 크리스마스 기간에만 나온다
-- ============================================================
-- 0075 에서는 겨울 내내(12월 1일 ~ 2월 15일) 3일마다 세 가지 중 하나를 골라
-- 산타가 없는 기간에도 SANTA_WIN 이 나올 수 있었다.
-- 이제 칸이 생기는 시각이 크리스마스 기간(12월 15일 ~ 12월 31일, is_christmas_at)일 때만
-- SANTA_WIN 을 후보에 넣는다. 그 밖의 칸은 50승·100킬 중에서 고른다.
-- 이미 만들어진 칸은 그대로 둔다. (0075 와 나머지는 같다)
-- ============================================================

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
  v_cand   jsonb;
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
    -- 산타로 15승(SANTA_WIN)은 크리스마스 기간에 생기는 칸에서만 고른다
    select jsonb_agg(e) into v_cand
      from jsonb_array_elements(v_pool) e
     where e ->> 0 <> 'SANTA_WIN' or public.is_christmas_at(v_start + v_period * k);
    v_pick := v_cand -> floor(random() * jsonb_array_length(v_cand))::int;
    insert into public.quests (uid, category, slot, kind, target,
                               reward_type, reward_amount, reward_item, created_at)
    values (p_uid, 'EVENT', v_base + k, v_pick ->> 0, (v_pick ->> 1)::int,
            v_pick ->> 2, (v_pick ->> 3)::int, v_pick ->> 4, v_start + v_period * k)
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
