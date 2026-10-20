-- ============================================================
-- 마피아 게임 · 연승 보너스를 상자에도, 연승은 0부터 새로
-- ============================================================
-- 1. 일일보상 상자에도 연승 보너스를 붙인다.
--    이길 때 그 판의 보너스(%)를 상자 칸(daily_rewards.bonus)에 남기고,
--    상자를 열 때 나온 재화(코인·별·보석, 가진 프로필을 바꿔 주는 재화 포함)에 붙인다.
--    프로필은 그대로다. 출석·연속 출석 상자는 이겨서 받는 것이 아니라 붙지 않는다.
-- 2. 연승을 0부터 다시 센다.
--    이 마이그레이션을 실행한 시점까지의 게임 기록은 연승에 넣지 않는다.
--    퀘스트의 연승(STREAK) 진행도는 그대로다.
-- ============================================================

-- 양에 보너스(%)를 붙인다 (반올림)
create or replace function public.with_bonus(p_amount int, p_bonus int)
returns int
language sql
immutable
as $$
  select round(p_amount * (100 + coalesce(p_bonus, 0)) / 100.0)::int;
$$;

create or replace function public.with_streak(p_amount int, p_streak int)
returns int
language sql
immutable
as $$
  select public.with_bonus(p_amount, public.streak_bonus(p_streak));
$$;

-- ------------------------------------------------------------
-- 1. 상자: 연 재화에 보너스를 붙인다. p_bonus 가 없으면 0 (출석 상자)
-- ------------------------------------------------------------
drop function if exists public.open_box(uuid, text);

create or replace function public.open_box(p_uid uuid, p_box text, p_bonus int default 0)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_r    jsonb := public.roll_box(p_box);
  v_type text  := v_r ->> 'type';
  v_amt  int   := (v_r ->> 'amount')::int;
  v_item text  := v_r ->> 'item';
  v_dup  boolean := false;
begin
  if v_item is not null then
    insert into public.owned_items (uid, item_id) values (p_uid, v_item)
    on conflict (uid, item_id) do nothing;
    -- 이미 가졌으면 상점 가격의 반을 재화로 바꿔 준다
    if not found then
      v_dup := true;
      select s.price_type, s.price / 2 into v_type, v_amt from public.shop_items s where s.id = v_item;
    end if;
  end if;

  if v_type is not null then
    v_amt := public.with_bonus(v_amt, p_bonus);
    perform public.give_currency(p_uid, v_type, v_amt);
  end if;

  return jsonb_build_object('box', p_box, 'type', v_type, 'amount', v_amt, 'item', v_item, 'dup', v_dup);
end;
$$;

revoke all on function public.open_box(uuid, text, int) from public, anon, authenticated;

-- 이길 때 상자 칸에도 그 판의 보너스를 남긴다 (0062 와 나머지는 같다)
create or replace function public.give_daily_reward()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today  date := (now() at time zone 'Asia/Seoul')::date;
  v_row    public.daily_rewards;
  v_amount int;
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

  if v_row.type <> 'BOX' then
    v_amount := public.with_streak(v_row.amount, new.streak);
    update public.daily_rewards d
       set won_at = now(), room_id = new.room_id,
           amount = v_amount, bonus = public.streak_bonus(new.streak)
     where d.uid = new.uid and d.day = v_today and d.idx = v_row.idx;
    perform public.give_currency(new.uid, v_row.type, v_amount);
  else
    -- 상자는 열 때 이 보너스를 붙인다
    update public.daily_rewards d
       set won_at = now(), room_id = new.room_id, bonus = public.streak_bonus(new.streak)
     where d.uid = new.uid and d.day = v_today and d.idx = v_row.idx;
  end if;

  return new;
end;
$$;

revoke all on function public.give_daily_reward() from public, anon, authenticated;

-- 일일보상 상자를 열 때 칸에 남긴 보너스를 붙인다 (0060 과 나머지는 같다)
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

  v_r := public.open_box(v_uid, v_row.box, v_row.bonus);

  update public.daily_rewards d
     set opened_at = now(), open_type = v_r ->> 'type', open_amount = (v_r ->> 'amount')::int,
         open_item = v_r ->> 'item', open_dup = (v_r ->> 'dup')::boolean
   where d.uid = v_uid and d.day = p_day and d.idx = p_idx;

  return json_build_object('type', v_r ->> 'type', 'amount', (v_r ->> 'amount')::int,
                           'item', v_r ->> 'item', 'dup', (v_r ->> 'dup')::boolean,
                           'bonus', v_row.bonus);
end;
$$;

revoke all on function public.open_daily_box(date, int) from public, anon;
grant execute on function public.open_daily_box(date, int) to authenticated;

-- ------------------------------------------------------------
-- 2. 연승을 0부터: 지금까지의 마지막 기록 번호를 기준점으로 박아 두고, 그 뒤 기록만 센다
-- ------------------------------------------------------------
do $$
begin
  execute format($f$
    create or replace function public.streak_start_id()
    returns bigint
    language sql
    immutable
    as 'select %s::bigint'
  $f$, (select coalesce(max(id), 0) from public.game_records));
end;
$$;

create or replace function public.current_streak(p_uid uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int from public.game_records g
   where g.uid = p_uid and g.won
     and g.id > greatest(public.streak_start_id(), coalesce(
       (select max(l.id) from public.game_records l where l.uid = p_uid and not l.won), 0));
$$;

revoke all on function public.current_streak(uuid) from public, anon, authenticated;
revoke all on function public.with_bonus(int, int) from public, anon;
