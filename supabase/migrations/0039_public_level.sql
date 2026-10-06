-- ============================================================
-- 마피아 게임 · 다른 사람에게 레벨만 보이기
-- ============================================================
-- profiles(누적 XP)는 본인만 읽을 수 있다(0037). 다른 사람에게는 XP 없이
-- 레벨만 보이도록, 같은 방 참가자가 읽을 수 있는 players 에 level 을 둔다.
--
-- · 방에 들어올 때 계정 XP 로 레벨을 채운다 (트리거)
-- · 게임이 끝나 XP 가 늘면 참가 중인 방의 레벨도 바로 바꾼다 (트리거)
-- · 이번 판 XP(final_roles 의 xpBase/xpGained)는 본인 것만 준다
-- 익명 사용자(테스트)는 프로필이 없어 1레벨이다.
-- ============================================================

-- 누적 XP -> 레벨. 레벨 L 이 되는 누적 XP = 5·L·(L-1), 최대 50 (0038, src/lib/level.js)
create or replace function public.level_of(p_xp int)
returns int
language sql
immutable
as $$
  select least(50, floor((5 + sqrt(25 + 20.0 * greatest(coalesce(p_xp, 0), 0))) / 10)::int);
$$;

alter table public.players add column if not exists level int not null default 1;

-- 방에 들어올 때 레벨을 채운다
create or replace function public.fill_player_level()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.level := coalesce(
    (select public.level_of(pf.xp) from public.profiles pf where pf.uid = new.uid), 1);
  return new;
end;
$$;

drop trigger if exists players_fill_level on public.players;
create trigger players_fill_level
  before insert on public.players
  for each row execute function public.fill_player_level();

-- XP 가 바뀌면 참가 중인 방의 레벨도 바꾼다
create or replace function public.sync_player_level()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.players pl
     set level = public.level_of(new.xp)
   where pl.uid = new.uid
     and pl.level <> public.level_of(new.xp);
  return new;
end;
$$;

drop trigger if exists profiles_sync_level on public.profiles;
create trigger profiles_sync_level
  after update of xp on public.profiles
  for each row execute function public.sync_player_level();

-- 지금 방에 있는 사람들의 레벨을 채운다
update public.players pl
   set level = public.level_of(pf.xp)
  from public.profiles pf
 where pf.uid = pl.uid;

-- ------------------------------------------------------------
-- final_roles: 레벨을 함께 주고, 이번 판 XP 는 본인 것만 준다 (0038 과 나머지는 같다)
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
             'level', pl.level,
             'xpBase',   case when pl.uid = auth.uid() then pl.xp_base end,
             'xpGained', case when pl.uid = auth.uid() then pl.xp_gained end)
           order by pl.joined_at)
      from public.private_roles pr
      join public.players pl on pl.room_id = pr.room_id and pl.uid = pr.uid
     where pr.room_id = p_room_id
  );
end;
$$;

revoke all on function public.fill_player_level() from public, anon, authenticated;
revoke all on function public.sync_player_level() from public, anon, authenticated;
