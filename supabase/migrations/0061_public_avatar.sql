-- ============================================================
-- 마피아 게임 · 장착한 프로필을 다른 사람에게도 보이기
-- ============================================================
-- 장착한 프로필은 profiles.avatar 에 있다(0051). profiles 는 본인만 읽을 수 있어서(0037)
-- 같은 방 사람에게는 보이지 않았다. 레벨(0039)처럼 같은 방 참가자가 읽을 수 있는
-- players 에 avatar 를 둔다.
--
-- · 방에 들어올 때 장착한 프로필을 채운다 (트리거)
-- · 방에 있는 동안 장착을 바꾸면 그 방의 프로필도 바로 바꾼다 (트리거)
-- 익명 사용자(테스트)는 프로필이 없어 기본(null)이다.
-- ============================================================

alter table public.players add column if not exists avatar text;

-- 방에 들어올 때 장착한 프로필을 채운다
create or replace function public.fill_player_avatar()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.avatar := (select pf.avatar from public.profiles pf where pf.uid = new.uid);
  return new;
end;
$$;

drop trigger if exists players_fill_avatar on public.players;
create trigger players_fill_avatar
  before insert on public.players
  for each row execute function public.fill_player_avatar();

-- 장착을 바꾸면 참가 중인 방의 프로필도 바꾼다
create or replace function public.sync_player_avatar()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.players pl
     set avatar = new.avatar
   where pl.uid = new.uid
     and pl.avatar is distinct from new.avatar;
  return new;
end;
$$;

drop trigger if exists profiles_sync_avatar on public.profiles;
create trigger profiles_sync_avatar
  after update of avatar on public.profiles
  for each row execute function public.sync_player_avatar();

-- 지금 방에 있는 사람들의 프로필을 채운다
update public.players pl
   set avatar = pf.avatar
  from public.profiles pf
 where pf.uid = pl.uid
   and pl.avatar is distinct from pf.avatar;

revoke all on function public.fill_player_avatar() from public, anon, authenticated;
revoke all on function public.sync_player_avatar() from public, anon, authenticated;
