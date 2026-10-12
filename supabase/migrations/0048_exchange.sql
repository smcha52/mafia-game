-- ============================================================
-- 마피아 게임 · 재화 교환소
-- ============================================================
-- 가진 재화를 다른 재화로 바꾼다. 네 가지가 있다.
--
--   종류           내는 것    받는 것
--   COIN_TO_STAR   코인 4     별 1
--   STAR_TO_GEM    별 25      보석 1
--   STAR_TO_COIN   별 1       코인 4
--   GEM_TO_STAR    보석 1     별 25
--
-- 한 번에 1·5·10·50배로 바꿀 수 있다. 배수만큼 내고 받는 양이 함께 늘어난다.
-- 비율이 서로 맞물려 있어 왔다 갔다 해도 재화가 늘지 않는다.
-- profiles 는 쓰기 정책이 없으므로(0046) 교환도 이 RPC 로만 한다.
-- ============================================================

-- 바뀐 뒤의 내 재화 { stars, gems, coins } 를 준다
create or replace function public.exchange_currency(p_kind text, p_times int)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_stars int;
  v_gems  int;
  v_coins int;
begin
  if p_times is null or p_times not in (1, 5, 10, 50) then
    raise exception '교환 배수가 올바르지 않습니다.';
  end if;

  -- 같은 사람의 요청이 겹쳐도 가진 것보다 많이 쓰지 못하도록 프로필을 잠근다
  select pf.stars, pf.gems, pf.coins into v_stars, v_gems, v_coins
    from public.profiles pf where pf.uid = v_uid for update;
  if not found then
    raise exception '로그인이 필요합니다.';
  end if;

  case p_kind
  when 'COIN_TO_STAR' then
    v_coins := v_coins - 4 * p_times;
    v_stars := v_stars + p_times;
  when 'STAR_TO_GEM' then
    v_stars := v_stars - 25 * p_times;
    v_gems  := v_gems + p_times;
  when 'STAR_TO_COIN' then
    v_stars := v_stars - p_times;
    v_coins := v_coins + 4 * p_times;
  when 'GEM_TO_STAR' then
    v_gems  := v_gems - p_times;
    v_stars := v_stars + 25 * p_times;
  else
    raise exception '없는 교환입니다.';
  end case;

  if v_stars < 0 or v_gems < 0 or v_coins < 0 then
    raise exception '재화가 부족합니다.';
  end if;

  update public.profiles pf
     set stars = v_stars, gems = v_gems, coins = v_coins
   where pf.uid = v_uid;

  return json_build_object('stars', v_stars, 'gems', v_gems, 'coins', v_coins);
end;
$$;

revoke all on function public.exchange_currency(text, int) from public, anon;
grant execute on function public.exchange_currency(text, int) to authenticated;
