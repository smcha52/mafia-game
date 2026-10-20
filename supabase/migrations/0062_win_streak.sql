-- ============================================================
-- 마피아 게임 · 연승 보너스
-- ============================================================
-- 2연승 이상이면 그 판에 받는 XP 와 재화를 늘린다.
--   2연승 +10%, 3연승 +20%, … 11연승 +100%(2배). 그 뒤로는 계속 +100%.
--
-- 연승은 game_records 에서 마지막으로 지거나 비긴 판 뒤의 승리 수다.
-- 이번 판을 이기면 (이전 연승 + 1), 지거나 비기면 0 이다.
--
-- 늘어나는 것 (이긴 판에만)
--   · XP          players.xp_gained (승리 2배를 한 뒤에 보너스)
--   · 승리 코인   win_coins()
--   · 일일보상    그 판에 받는 칸의 코인·별·보석. 상자는 늘지 않는다 (여는 것은 나중이다)
-- 계산은 반올림이다. 예) 코인 10개 · 2연승 → 11개, 별 5개 · 2연승 → 6개(5.5)
-- ============================================================

alter table public.players add column if not exists win_streak int not null default 0;
alter table public.game_records add column if not exists streak int not null default 0;
alter table public.daily_rewards add column if not exists bonus int not null default 0;

-- 연승 -> 보너스(%)
create or replace function public.streak_bonus(p_streak int)
returns int
language sql
immutable
as $$
  select case when p_streak >= 2 then least(100, (p_streak - 1) * 10) else 0 end;
$$;

-- 양에 연승 보너스를 붙인다 (반올림)
create or replace function public.with_streak(p_amount int, p_streak int)
returns int
language sql
immutable
as $$
  select round(p_amount * (100 + public.streak_bonus(p_streak)) / 100.0)::int;
$$;

-- 지금까지의 연승 (마지막으로 지거나 비긴 판 뒤의 승리 수)
create or replace function public.current_streak(p_uid uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int from public.game_records g
   where g.uid = p_uid and g.won
     and g.id > coalesce(
       (select max(l.id) from public.game_records l where l.uid = p_uid and not l.won), 0);
$$;

-- ------------------------------------------------------------
-- award_xp: 연승을 정하고 XP·코인에 보너스를 붙인다 (0049 와 나머지는 같다)
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
     set win_streak = case when b.win then public.current_streak(b.uid) + 1 else 0 end,
         xp_base    = b.base,
         xp_gained  = public.with_streak(
                        b.base * case when b.win then 2 else 1 end,
                        case when b.win then public.current_streak(b.uid) + 1 else 0 end)
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

  -- 이긴 사람만 코인을 받는다. 연승 보너스를 붙인다
  update public.profiles pf
     set coins = pf.coins + public.with_streak(public.win_coins(), pl.win_streak)
    from public.private_roles pr
    join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
   where pr.room_id = p_room_id and pf.uid = pr.uid
     and public.player_won(p_room_id, p_winner, pr.uid, pr.role, pr.team, pl.alive);

  -- 퀘스트용 게임 기록. streak 는 일일보상 트리거가 쓴다
  insert into public.game_records (uid, room_id, won, kills, days, role, stats, streak)
  select w.uid, p_room_id, w.won,
         public.kills_of(p_room_id, w.uid, w.role),
         public.days_survived(p_room_id, w.uid),
         w.role,
         public.role_stats(p_room_id, w.uid, w.role, w.won),
         w.win_streak
    from (
      select pr.uid, pr.role, pl.win_streak,
             public.player_won(p_room_id, p_winner, pr.uid, pr.role, pr.team, pl.alive) as won
        from public.private_roles pr
        join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
       where pr.room_id = p_room_id
    ) w;
end;
$$;

revoke all on function public.award_xp(uuid, text) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 일일보상: 그 판의 연승 보너스를 붙여 지급하고, 받은 양과 보너스를 칸에 남긴다 (0060 과 나머지는 같다)
-- ------------------------------------------------------------
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
    update public.daily_rewards d
       set won_at = now(), room_id = new.room_id
     where d.uid = new.uid and d.day = v_today and d.idx = v_row.idx;
  end if;

  return new;
end;
$$;

revoke all on function public.give_daily_reward() from public, anon, authenticated;

-- 칸 정보에 연승 보너스(%)를 함께 준다 (0060 과 나머지는 같다)
create or replace function public.daily_reward_json(d public.daily_rewards)
returns json
language sql
stable
as $$
  select json_build_object(
    'day', d.day, 'idx', d.idx, 'type', d.type, 'amount', d.amount, 'tier', d.tier, 'box', d.box,
    'won', d.won_at is not null,
    'bonus', d.bonus,
    'opened', d.opened_at is not null,
    'open', case when d.opened_at is not null then json_build_object(
              'type', d.open_type, 'amount', d.open_amount, 'item', d.open_item, 'dup', d.open_dup) end);
$$;

-- ------------------------------------------------------------
-- final_roles: 내 연승을 함께 준다 (0041 과 나머지는 같다)
-- ------------------------------------------------------------
create or replace function public.final_roles(p_room_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phase  text;
  v_winner text;
begin
  if not public.is_room_member(p_room_id) then
    raise exception '이 방의 참가자가 아닙니다.';
  end if;

  select r.phase, r.winner into v_phase, v_winner from public.rooms r where r.id = p_room_id;
  if v_phase <> 'ENDED' then
    raise exception '게임이 끝난 뒤에만 볼 수 있습니다.';
  end if;

  return (
    select json_agg(json_build_object(
             'uid', pl.uid, 'nickname', pl.nickname,
             'role', pr.role, 'team', pr.team, 'alive', pl.alive,
             'level', pl.level,
             'won', public.player_won(p_room_id, v_winner, pl.uid, pr.role, pr.team, pl.alive),
             'xpBase',   case when pl.uid = auth.uid() then pl.xp_base end,
             'xpGained', case when pl.uid = auth.uid() then pl.xp_gained end,
             'streak',   case when pl.uid = auth.uid() then pl.win_streak end)
           order by pl.joined_at)
      from public.private_roles pr
      join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
     where pr.room_id = p_room_id
  );
end;
$$;

revoke all on function public.streak_bonus(int) from public, anon;
revoke all on function public.with_streak(int, int) from public, anon;
revoke all on function public.current_streak(uuid) from public, anon, authenticated;
