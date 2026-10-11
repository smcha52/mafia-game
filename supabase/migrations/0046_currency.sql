-- ============================================================
-- 마피아 게임 · 재화 (별 · 보석 · 코인)
-- ============================================================
-- 계정(profiles)에 재화 세 가지를 둔다. 모두 0 에서 시작한다.
--
--   별   얻는 방법은 나중에 정한다
--   보석 얻는 방법은 나중에 정한다
--   코인 게임에서 이기면 10개, 지거나 무승부면 0개
--
-- 코인은 게임이 끝날 때 XP 와 함께 award_xp 에서 지급한다. award_xp 는 한 판에
-- 한 번만 지급하므로(xp_gained 가 이미 있으면 건너뜀) 코인도 한 번만 들어온다.
-- 승패는 XP 2배와 같은 player_won 으로 본다 (0041).
-- profiles 는 본인만 읽고, 쓰기 정책이 없어 화면에서 재화를 바꿀 수 없다.
-- 익명 사용자(테스트)는 프로필이 없어 받지 않는다.
-- ============================================================

alter table public.profiles add column if not exists stars int not null default 0 check (stars >= 0);
alter table public.profiles add column if not exists gems  int not null default 0 check (gems  >= 0);
alter table public.profiles add column if not exists coins int not null default 0 check (coins >= 0);

-- 이긴 사람이 받는 코인
create or replace function public.win_coins()
returns int
language sql
immutable
as $$ select 10 $$;

-- ------------------------------------------------------------
-- award_xp: 이긴 사람에게 코인을 더한다 (0041 과 나머지는 같다)
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
end;
$$;

revoke all on function public.award_xp(uuid, text) from public, anon, authenticated;
