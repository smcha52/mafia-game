-- ============================================================
-- 마피아 게임 · 방 찾기
-- ============================================================
-- 첫 화면의 "방 찾기"에서 들어갈 수 있는 방 목록을 10개씩 보여준다.
--
-- rooms·players 는 참가한 방만 읽을 수 있으므로(0001) 목록은 RPC 로 준다.
-- 들어갈 수 있는 방 = 대기실(LOBBY)이고 15명이 안 찬 방.
-- 입장은 기존 join_room(코드) 을 그대로 쓴다.
--
-- 새로고침하면 지금 보고 있는 방을 p_exclude 로 넘겨 다른 방 10개를 받는다.
-- ============================================================

create or replace function public.list_rooms(p_exclude uuid[] default '{}')
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id   uuid;
  v_list json;
begin
  if auth.uid() is null then
    raise exception '로그인이 필요합니다.';
  end if;

  -- 브라우저를 닫고 떠난 사람이 있는 대기실을 정리한다 (quick_join 과 같다)
  for v_id in
    select distinct r.id
      from public.rooms r
      join public.players pl on pl.room_id = r.id
      left join public.presence ps on ps.room_id = pl.room_id and ps.uid = pl.uid
     where r.phase = 'LOBBY'
       and coalesce(ps.last_seen, pl.joined_at) < now() - interval '60 seconds'
  loop
    perform public.purge_stale(v_id);
  end loop;

  select coalesce(json_agg(json_build_object(
           'id',        t.id,
           'code',      t.code,
           'host',      t.host,
           'players',   t.cnt,
           'createdAt', t.created_at)
           order by t.created_at desc, t.id), '[]'::json)
    into v_list
    from (
      select r.id, r.code, r.created_at,
             count(p.uid) as cnt,
             max(p.nickname) filter (where p.uid = r.host_uid) as host
        from public.rooms r
        join public.players p on p.room_id = r.id
       where r.phase = 'LOBBY'
         and not (r.id = any (coalesce(p_exclude, '{}')))
       group by r.id
      having count(p.uid) < 15
       order by r.created_at desc, r.id
       limit 10
    ) t;

  return v_list;
end;
$$;

grant execute on function public.list_rooms(uuid[]) to anon, authenticated;
