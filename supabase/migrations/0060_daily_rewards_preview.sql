-- ============================================================
-- 마피아 게임 · 일일보상을 미리 보여준다
-- ============================================================
-- 0057·0058 에서는 이길 때 보상을 뽑아서, 받기 전까지 칸이 비어(?) 있었다.
-- 이제 그날 처음 볼 때(또는 처음 이길 때) 5칸의 보상을 미리 뽑아 두고 칸에 보여준다.
-- 이길 때마다 앞 칸부터 차례로 받는다. 확률과 상자는 0058 과 같다.
-- 상자 종류(보물·호박)는 미리 뽑을 때의 할로윈 기간으로 정한다.
--
-- daily_rewards.won_at = 이겨서 받은 시각. 비어 있으면 아직 받지 않은(미리 보여주는) 칸이다.
-- 이 마이그레이션 전에 받은 줄은 받은 것으로 채운다.
-- ============================================================

alter table public.daily_rewards add column if not exists won_at timestamptz;

update public.daily_rewards d set won_at = d.created_at where d.won_at is null and d.room_id is not null;

-- ------------------------------------------------------------
-- 1. 그날 5칸을 채운다 (내부용)
-- ------------------------------------------------------------
create or replace function public.ensure_daily_rewards(p_uid uuid, p_day date)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_idx int;
  v_r   jsonb;
begin
  for v_idx in
    select i from generate_series(1, public.daily_reward_limit()) i
     where not exists (select 1 from public.daily_rewards d
                        where d.uid = p_uid and d.day = p_day and d.idx = i)
  loop
    v_r := public.roll_daily_reward();
    insert into public.daily_rewards (uid, day, idx, type, amount, tier, box)
    values (p_uid, p_day, v_idx, v_r ->> 'type', (v_r ->> 'amount')::int, v_r ->> 'tier', v_r ->> 'box')
    on conflict (uid, day, idx) do nothing;
  end loop;
end;
$$;

revoke all on function public.ensure_daily_rewards(uuid, date) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 2. 이기면 다음 칸을 받는다 (game_records 트리거, 0058 을 바꾼다)
-- ------------------------------------------------------------
create or replace function public.give_daily_reward()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_row   public.daily_rewards;
begin
  -- 같은 사람의 지급이 겹쳐도 한 칸씩만 받도록 프로필을 잠근다. 프로필이 없으면 건너뛴다
  perform 1 from public.profiles pf where pf.uid = new.uid for update;
  if not found then
    return new;
  end if;

  perform public.ensure_daily_rewards(new.uid, v_today);

  select * into v_row from public.daily_rewards d
   where d.uid = new.uid and d.day = v_today and d.won_at is null
   order by d.idx limit 1;
  -- 5칸을 다 받았으면 없다
  if not found then
    return new;
  end if;

  update public.daily_rewards d
     set won_at = now(), room_id = new.room_id
   where d.uid = new.uid and d.day = v_today and d.idx = v_row.idx;

  if v_row.type <> 'BOX' then
    perform public.give_currency(new.uid, v_row.type, v_row.amount);
  end if;

  return new;
end;
$$;

-- ------------------------------------------------------------
-- 3. RPC — 오늘 일일보상
-- ------------------------------------------------------------
-- { limit, next,
--   items: [{ day, idx, type, amount, tier, box, won, opened, open }]  오늘 5칸 (won = 받았는지),
--   boxes: [...]  지난날에 받고 아직 열지 않은 상자 }
create or replace function public.daily_reward_json(d public.daily_rewards)
returns json
language sql
stable
as $$
  select json_build_object(
    'day', d.day, 'idx', d.idx, 'type', d.type, 'amount', d.amount, 'tier', d.tier, 'box', d.box,
    'won', d.won_at is not null,
    'opened', d.opened_at is not null,
    'open', case when d.opened_at is not null then json_build_object(
              'type', d.open_type, 'amount', d.open_amount, 'item', d.open_item, 'dup', d.open_dup) end);
$$;

create or replace function public.my_daily_rewards()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_today date := (now() at time zone 'Asia/Seoul')::date;
begin
  if not exists (select 1 from public.profiles pf where pf.uid = v_uid) then
    raise exception '로그인이 필요합니다.';
  end if;

  perform public.ensure_daily_rewards(v_uid, v_today);

  return json_build_object(
    'limit', public.daily_reward_limit(),
    'next',  public.attendance_next(),
    'items', coalesce((
      select json_agg(public.daily_reward_json(d) order by d.idx)
        from public.daily_rewards d
       where d.uid = v_uid and d.day = v_today), '[]'::json),
    'boxes', coalesce((
      select json_agg(public.daily_reward_json(d) order by d.day, d.idx)
        from public.daily_rewards d
       where d.uid = v_uid and d.day < v_today and d.type = 'BOX'
         and d.won_at is not null and d.opened_at is null), '[]'::json)
  );
end;
$$;

-- ------------------------------------------------------------
-- 4. RPC — 상자 열기 (0059 와 같고, 받은 상자만 연다)
-- ------------------------------------------------------------
create or replace function public.open_daily_box(p_day date, p_idx int)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.daily_rewards;
  v_r   jsonb;
begin
  -- 같은 상자를 두 번 열지 못하도록 잠근다
  select * into v_row from public.daily_rewards d
   where d.uid = v_uid and d.day = p_day and d.idx = p_idx and d.type = 'BOX' and d.won_at is not null
   for update;
  if not found then
    raise exception '상자가 없습니다.';
  end if;
  if v_row.opened_at is not null then
    raise exception '이미 연 상자입니다.';
  end if;

  v_r := public.open_box(v_uid, v_row.box);

  update public.daily_rewards d
     set opened_at = now(), open_type = v_r ->> 'type', open_amount = (v_r ->> 'amount')::int,
         open_item = v_r ->> 'item', open_dup = (v_r ->> 'dup')::boolean
   where d.uid = v_uid and d.day = p_day and d.idx = p_idx;

  return json_build_object('type', v_r ->> 'type', 'amount', (v_r ->> 'amount')::int,
                           'item', v_r ->> 'item', 'dup', (v_r ->> 'dup')::boolean);
end;
$$;
