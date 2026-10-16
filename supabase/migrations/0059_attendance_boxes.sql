-- ============================================================
-- 마피아 게임 · 출석 상자
-- ============================================================
-- 출석(0052·0056)과 연속 출석(0053)에서 보상이 비어 있던 5 · 10 · 15 · 20 · 25일에 상자를 넣는다.
-- 연속 출석은 출석 보상표(attendance_rewards)를 그대로 쓰므로 함께 바뀐다.
--
--   날짜               평소       할로윈 기간 (is_halloween, 0054)
--   5 · 15 · 25일      보물상자   호박상자
--   10 · 20일          보물상자   보물상자
--
-- 상자에서 나오는 것은 일일보상 상자(0058 roll_box)와 같다.
-- 출석(또는 연속 출석)하는 순간 상자가 열리고, 나온 것을 돌려줘 화면이 보여준다.
-- 이미 가진 프로필이 나오면 상점 가격의 반을 재화로 준다 (0058 과 같다).
-- ============================================================

-- ------------------------------------------------------------
-- 1. 규칙 (내부용)
-- ------------------------------------------------------------

-- 그날 받는 보상 [[재화, 개수], ["BOX", 1, 상자 종류], ...]. 없으면 빈 배열
-- 할로윈 기간에 따라 바뀌므로 immutable 이 아니다
create or replace function public.attendance_rewards(p_day int)
returns jsonb
language sql
stable
as $$
  select case
    when p_day between 1 and 25 then
      case (p_day - 1) % 5
        when 0 then '[["COIN",5]]'::jsonb
        when 1 then '[["COIN",10]]'::jsonb
        when 2 then '[["STAR",3]]'::jsonb
        when 3 then '[["STAR",5]]'::jsonb
        else jsonb_build_array(jsonb_build_array('BOX', 1,
               case when public.is_halloween() and p_day % 10 = 5 then 'PUMPKIN' else 'TREASURE' end))
      end
    when p_day = 26 then '[["STAR",10]]'::jsonb
    when p_day = 27 then '[["STAR",15]]'::jsonb
    when p_day = 28 then '[["STAR",20]]'::jsonb
    when p_day = 29 then '[["GEM",2]]'::jsonb
    when p_day = 30 then '[["GEM",3]]'::jsonb
    else '[]'::jsonb
  end;
$$;

create or replace function public.streak_rewards(p_streak int)
returns jsonb
language sql
stable
as $$
  select public.attendance_rewards((p_streak - 1) % 30 + 1);
$$;

-- 화면에 줄 보상 [{ type, amount, box }]
create or replace function public.rewards_json(p_rewards jsonb)
returns jsonb
language sql
immutable
as $$
  select coalesce(jsonb_agg(jsonb_build_object('type', r ->> 0, 'amount', (r ->> 1)::int, 'box', r ->> 2)),
                  '[]'::jsonb)
    from jsonb_array_elements(p_rewards) r;
$$;

-- 상자를 열어 지급한다. 나온 것 { box, type, amount, item, dup }
create or replace function public.open_box(p_uid uuid, p_box text)
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
    perform public.give_currency(p_uid, v_type, v_amt);
  end if;

  return jsonb_build_object('box', p_box, 'type', v_type, 'amount', v_amt, 'item', v_item, 'dup', v_dup);
end;
$$;

-- 보상을 모두 지급한다. 재화는 더하고 상자는 연다. 연 상자에서 나온 것들을 돌려준다
create or replace function public.give_rewards(p_uid uuid, p_rewards jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_r     jsonb;
  v_boxes jsonb := '[]'::jsonb;
begin
  for v_r in select * from jsonb_array_elements(p_rewards) loop
    if v_r ->> 0 = 'BOX' then
      v_boxes := v_boxes || jsonb_build_array(public.open_box(p_uid, v_r ->> 2));
    else
      perform public.give_currency(p_uid, v_r ->> 0, (v_r ->> 1)::int);
    end if;
  end loop;
  return v_boxes;
end;
$$;

revoke all on function public.open_box(uuid, text)       from public, anon, authenticated;
revoke all on function public.give_rewards(uuid, jsonb)  from public, anon, authenticated;

-- ------------------------------------------------------------
-- 2. 일일보상 상자 열기도 open_box 를 쓴다 (0058 과 결과는 같다)
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
   where d.uid = v_uid and d.day = p_day and d.idx = p_idx and d.type = 'BOX'
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

-- ------------------------------------------------------------
-- 3. RPC — 출석 (0056 과 같고, 보상에 상자가 있다)
-- ------------------------------------------------------------
create or replace function public.my_attendance()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_count   int;
  v_checked boolean;
  v_done    int;
begin
  if public.attendance_begin(v_uid) is null then
    raise exception '로그인이 필요합니다.';
  end if;

  select pf.attendance_count, coalesce(pf.attendance_last = (now() at time zone 'Asia/Seoul')::date, false)
    into v_count, v_checked
    from public.profiles pf where pf.uid = v_uid;

  -- 이번 바퀴에 받은 칸 수. 30일째를 받은 다음 날은 새 바퀴라 0 이다
  v_done := case when v_checked then (v_count - 1) % 30 + 1 else v_count % 30 end;

  return json_build_object(
    'day',     case when v_checked then v_done else v_done + 1 end,
    'checked', v_checked,
    'next',    public.attendance_next(),
    'days', (
      select json_agg(json_build_object(
               'day',     d,
               'rewards', public.rewards_json(public.attendance_rewards(d)),
               'claimed', d <= v_done)
             order by d)
        from generate_series(1, 30) d)
  );
end;
$$;

-- { day, boxes: 연 상자에서 나온 것 [{ box, type, amount, item, dup }] }
create or replace function public.claim_attendance()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_count int;
  v_last  date;
  v_day   int;
  v_boxes jsonb;
begin
  if public.attendance_begin(v_uid) is null then
    raise exception '로그인이 필요합니다.';
  end if;

  -- 같은 사람의 요청이 겹쳐도 한 번만 세도록 프로필을 잠근다
  select pf.attendance_count, pf.attendance_last into v_count, v_last
    from public.profiles pf where pf.uid = v_uid for update;

  if v_last = v_today then
    raise exception '오늘은 이미 출석했습니다.';
  end if;

  v_day := v_count % 30 + 1;

  update public.profiles pf
     set attendance_count = v_count + 1,
         attendance_last  = v_today
   where pf.uid = v_uid;

  v_boxes := public.give_rewards(v_uid, public.attendance_rewards(v_day));

  return json_build_object('day', v_day, 'boxes', v_boxes);
end;
$$;

-- ------------------------------------------------------------
-- 4. RPC — 연속 출석 (0055 와 같고, 보상에 상자가 있다)
-- ------------------------------------------------------------
create or replace function public.my_streak()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_start  timestamptz;
  v_n      int;
  v_count  int;
  v_slot   int;
  v_streak int;
  v_done   int;
begin
  v_start := public.attendance_begin(v_uid);
  if v_start is null then
    raise exception '로그인이 필요합니다.';
  end if;

  v_n := public.attendance_slot(v_start);
  select pf.streak_count, pf.streak_slot into v_count, v_slot
    from public.profiles pf where pf.uid = v_uid;

  -- 오늘이나 어제 출석했으면 이어지고 있다. 그보다 오래됐으면 끊겼다
  v_streak := case when v_slot is not null and v_slot >= v_n - 1 then v_count else 0 end;

  -- 30일 표에서 이번 바퀴에 출석한 칸 수. 30일째를 채운 다음 날은 새 바퀴라 0 이다
  v_done := case
    when v_streak = 0   then 0
    when v_slot = v_n   then (v_streak - 1) % 30 + 1
    else v_streak % 30
  end;

  return json_build_object(
    'streak',  v_streak,
    'checked', coalesce(v_slot = v_n, false),
    'next',    public.attendance_next(),
    'day',     case when v_slot = v_n then v_done else v_done + 1 end,
    'days', (
      select json_agg(json_build_object(
               'day',     d,
               'rewards', public.rewards_json(public.streak_rewards(d)),
               'claimed', d <= v_done)
             order by d)
        from generate_series(1, 30) d)
  );
end;
$$;

-- { streak, boxes: 연 상자에서 나온 것 [{ box, type, amount, item, dup }] }
create or replace function public.claim_streak()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_start timestamptz;
  v_n     int;
  v_count int;
  v_slot  int;
  v_boxes jsonb;
begin
  v_start := public.attendance_begin(v_uid);
  if v_start is null then
    raise exception '로그인이 필요합니다.';
  end if;

  -- 같은 사람의 요청이 겹쳐도 한 번만 세도록 프로필을 잠근다
  select pf.streak_count, pf.streak_slot into v_count, v_slot
    from public.profiles pf where pf.uid = v_uid for update;

  v_n := public.attendance_slot(v_start);
  if v_slot = v_n then
    raise exception '오늘은 이미 출석했습니다.';
  end if;

  -- 어제 출석했으면 이어 가고, 아니면 1일부터 다시 센다
  v_count := case when v_slot = v_n - 1 then v_count + 1 else 1 end;

  update public.profiles pf
     set streak_count = v_count,
         streak_slot  = v_n
   where pf.uid = v_uid;

  v_boxes := public.give_rewards(v_uid, public.streak_rewards(v_count));

  return json_build_object('streak', v_count, 'boxes', v_boxes);
end;
$$;
