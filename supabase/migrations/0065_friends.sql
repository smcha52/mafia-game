-- ============================================================
-- 마피아 게임 · 친구
-- ============================================================
-- 닉네임으로 플레이어를 찾아 친구 추가를 요청하고, 상대가 받아 주면 친구가 된다.
-- 친구는 접속 여부와, 방에 들어가 있으면 그 방 코드를 볼 수 있다. 비공개 방은 코드를 숨긴다.
-- 친구는 어느 쪽에서든 삭제할 수 있다.
--
--   friendships   요청한 사람 → 받은 사람 한 줄. status PENDING(요청 중) · ACCEPTED(친구)
--                 두 사람 사이에는 한 줄만 있다 (방향과 상관없이)
--   profiles.last_online  화면이 1분마다 남기는 접속 시각. 2분 안이면 접속 중으로 본다
--
-- 상대가 이미 나에게 요청했는데 내가 요청하면 바로 친구가 된다.
-- 거절하면 요청 줄을 지운다 (다시 요청할 수 있다).
-- 익명 사용자(테스트)는 프로필이 없어 친구 기능을 쓸 수 없다.
-- ============================================================

alter table public.profiles add column if not exists last_online timestamptz;

create table if not exists public.friendships (
  requester   uuid not null references public.profiles (uid) on delete cascade,
  addressee   uuid not null references public.profiles (uid) on delete cascade,
  status      text not null default 'PENDING' check (status in ('PENDING', 'ACCEPTED')),
  created_at  timestamptz not null default now(),
  accepted_at timestamptz,
  primary key (requester, addressee),
  check (requester <> addressee)
);
-- 방향과 상관없이 두 사람 사이에 한 줄만
create unique index if not exists friendships_pair_key
  on public.friendships (least(requester, addressee), greatest(requester, addressee));
create index if not exists friendships_addressee_idx on public.friendships (addressee);

-- 직접 읽기·쓰기는 막고 RPC 로만 다룬다
alter table public.friendships enable row level security;
revoke all on public.friendships from anon, authenticated;

-- 접속 중으로 보는 시간
create or replace function public.online_window()
returns interval
language sql
immutable
as $$ select interval '2 minutes' $$;

-- 친구 목록·검색 결과 한 사람 (닉네임 · 프로필 그림 · 레벨)
create or replace function public.friend_card(p_uid uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object('uid', pf.uid, 'nickname', pf.nickname, 'avatar', pf.avatar,
                            'level', public.level_of(pf.xp))
    from public.profiles pf where pf.uid = p_uid;
$$;

-- 나와 그 사람의 관계. ME · NONE · SENT(내가 요청) · RECEIVED(받은 요청) · FRIEND
create or replace function public.friend_status(p_me uuid, p_other uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when p_me = p_other then 'ME'
    else coalesce((
      select case
               when f.status = 'ACCEPTED' then 'FRIEND'
               when f.requester = p_me then 'SENT'
               else 'RECEIVED'
             end
        from public.friendships f
       where (f.requester = p_me and f.addressee = p_other)
          or (f.requester = p_other and f.addressee = p_me)), 'NONE')
  end;
$$;

-- ------------------------------------------------------------
-- RPC — 접속 표시. 로그인해 있는 동안 화면이 1분마다 부른다
-- ------------------------------------------------------------
create or replace function public.touch_online()
returns void
language sql
security definer
set search_path = public
as $$
  update public.profiles pf set last_online = now() where pf.uid = auth.uid();
$$;

-- ------------------------------------------------------------
-- RPC — 닉네임으로 찾기 (대소문자 무시, 정확히 같은 닉네임). 없으면 null
-- ------------------------------------------------------------
create or replace function public.search_player(p_nickname text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_other uuid;
begin
  if not exists (select 1 from public.profiles pf where pf.uid = v_uid) then
    raise exception '로그인이 필요합니다.';
  end if;
  if coalesce(trim(p_nickname), '') = '' then
    raise exception '닉네임을 입력해 주세요.';
  end if;

  select pf.uid into v_other from public.profiles pf
   where lower(pf.nickname) = lower(trim(p_nickname));
  if not found then
    return null;
  end if;

  return (public.friend_card(v_other)
          || jsonb_build_object('status', public.friend_status(v_uid, v_other)))::json;
end;
$$;

-- ------------------------------------------------------------
-- RPC — 친구 추가 요청. 상대가 이미 나에게 요청했으면 바로 친구가 된다
-- ------------------------------------------------------------
create or replace function public.send_friend_request(p_uid uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if not exists (select 1 from public.profiles pf where pf.uid = v_uid) then
    raise exception '로그인이 필요합니다.';
  end if;
  if not exists (select 1 from public.profiles pf where pf.uid = p_uid) then
    raise exception '없는 플레이어입니다.';
  end if;

  case public.friend_status(v_uid, p_uid)
    when 'ME' then
      raise exception '자신은 친구로 추가할 수 없습니다.';
    when 'FRIEND' then
      raise exception '이미 친구입니다.';
    when 'SENT' then
      raise exception '이미 친구 추가를 요청했습니다.';
    when 'RECEIVED' then
      update public.friendships f
         set status = 'ACCEPTED', accepted_at = now()
       where f.requester = p_uid and f.addressee = v_uid;
      return 'FRIEND';
    else
      insert into public.friendships (requester, addressee) values (v_uid, p_uid);
      return 'SENT';
  end case;
end;
$$;

-- ------------------------------------------------------------
-- RPC — 받은 요청 받아 주기 / 거절하기
-- ------------------------------------------------------------
create or replace function public.accept_friend_request(p_uid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.friendships f
     set status = 'ACCEPTED', accepted_at = now()
   where f.requester = p_uid and f.addressee = auth.uid() and f.status = 'PENDING';
  if not found then
    raise exception '받은 친구 요청이 없습니다.';
  end if;
end;
$$;

create or replace function public.decline_friend_request(p_uid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.friendships f
   where f.requester = p_uid and f.addressee = auth.uid() and f.status = 'PENDING';
  if not found then
    raise exception '받은 친구 요청이 없습니다.';
  end if;
end;
$$;

-- ------------------------------------------------------------
-- RPC — 내 친구와 받은 요청
-- { requests: [카드], sent: [카드],
--   friends: [카드 + online, room: { code, phase } | null] }
-- 방은 끝나지 않은 방 중 가장 최근에 만든 방이다 (my_active_room 과 같다)
-- 비공개 방은 code 를 null 로 주고 private 를 켠다
-- ------------------------------------------------------------
create or replace function public.my_friends()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if not exists (select 1 from public.profiles pf where pf.uid = v_uid) then
    raise exception '로그인이 필요합니다.';
  end if;

  return json_build_object(
    'requests', coalesce((
      select json_agg(public.friend_card(f.requester) order by f.created_at desc)
        from public.friendships f
       where f.addressee = v_uid and f.status = 'PENDING'), '[]'::json),
    'sent', coalesce((
      select json_agg(public.friend_card(f.addressee) order by f.created_at desc)
        from public.friendships f
       where f.requester = v_uid and f.status = 'PENDING'), '[]'::json),
    'friends', coalesce((
      select json_agg(x.card order by x.online desc, x.nickname)
        from (
          select public.friend_card(o.uid)
                 || jsonb_build_object(
                      'online', coalesce(pf.last_online > now() - public.online_window(), false),
                      'room', (select jsonb_build_object(
                                        'code', case when r.is_public then r.code end,
                                        'phase', r.phase,
                                        'private', not r.is_public)
                                 from public.rooms r
                                 join public.players p on p.room_id = r.id
                                where p.uid = o.uid and r.phase <> 'ENDED'
                                order by r.created_at desc
                                limit 1)) as card,
                 coalesce(pf.last_online > now() - public.online_window(), false) as online,
                 pf.nickname
            from (
              select case when f.requester = v_uid then f.addressee else f.requester end as uid
                from public.friendships f
               where f.status = 'ACCEPTED' and (f.requester = v_uid or f.addressee = v_uid)
            ) o
            join public.profiles pf on pf.uid = o.uid
        ) x), '[]'::json)
  );
end;
$$;

-- ------------------------------------------------------------
-- RPC — 친구 삭제. 어느 쪽에서든 지울 수 있고, 상대 목록에서도 사라진다
-- ------------------------------------------------------------
create or replace function public.remove_friend(p_uid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  delete from public.friendships f
   where f.status = 'ACCEPTED'
     and ((f.requester = v_uid and f.addressee = p_uid)
       or (f.requester = p_uid and f.addressee = v_uid));
  if not found then
    raise exception '친구가 아닙니다.';
  end if;
end;
$$;

revoke all on function public.friend_card(uuid) from public, anon, authenticated;
revoke all on function public.friend_status(uuid, uuid) from public, anon, authenticated;
revoke all on function public.touch_online() from public, anon;
revoke all on function public.search_player(text) from public, anon;
revoke all on function public.send_friend_request(uuid) from public, anon;
revoke all on function public.accept_friend_request(uuid) from public, anon;
revoke all on function public.decline_friend_request(uuid) from public, anon;
revoke all on function public.my_friends() from public, anon;
revoke all on function public.remove_friend(uuid) from public, anon;
grant execute on function public.touch_online() to authenticated;
grant execute on function public.search_player(text) to authenticated;
grant execute on function public.send_friend_request(uuid) to authenticated;
grant execute on function public.accept_friend_request(uuid) to authenticated;
grant execute on function public.decline_friend_request(uuid) to authenticated;
grant execute on function public.my_friends() to authenticated;
grant execute on function public.remove_friend(uuid) to authenticated;
