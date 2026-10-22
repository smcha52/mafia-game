-- ============================================================
-- 마피아 게임 · 클럽 계급 · 나가기 · 추방 · 클럽 소식
-- ============================================================
-- 계급: LEADER(대장) · VICE(부대장) · MEMBER(멤버). 들어오면 멤버, 만든 사람은 대장.
--   대장   — 승급(멤버 → 부대장 → 대장) · 강등(대장 → 부대장 → 멤버) · 멤버 추방
--   부대장 — 멤버 추방
-- 추방당하면 그 클럽에 7일 동안 들어갈 수 없다.
-- 처음 만든 사람(clubs.owner)은 강등·추방당하지 않는다. 처음 만든 사람이 나가면
-- 그다음으로 먼저 들어온 사람이 처음 만든 사람과 똑같이 된다(owner, 대장).
-- 아무도 없는 클럽에 처음 들어온 사람도 처음 만든 사람과 똑같이 된다.
--
-- 클럽 소식은 club_messages 에 kind 로 남긴다 (채팅과 함께 보인다)
--   CHAT 채팅 · CREATE 만듦 · JOIN 들어옴 · LEAVE 나감 · PROMOTE 승급 · DEMOTE 강등
--   KICK 추방(sender = 추방한 사람, target = 추방당한 사람) · OWNER 처음 만든 사람을 이어받음
--
-- 이미 있던 클럽도 적용한다: 만든 사람은 대장, 나머지는 멤버.
-- 만든 사람이 다른 클럽으로 옮겨 가 있으면 먼저 들어온 사람이 이어받는다.
-- ============================================================

alter table public.club_members add column if not exists rank text not null default 'MEMBER';
alter table public.club_members drop constraint if exists club_members_rank_check;
alter table public.club_members add constraint club_members_rank_check
  check (rank in ('LEADER', 'VICE', 'MEMBER'));

-- 추방당한 사람은 until 까지 그 클럽에 들어갈 수 없다
create table if not exists public.club_bans (
  club_id  bigint not null references public.clubs (id) on delete cascade,
  uid      uuid   not null references public.profiles (uid) on delete cascade,
  until    timestamptz not null,
  primary key (club_id, uid)
);
alter table public.club_bans enable row level security;
revoke all on public.club_bans from anon, authenticated;

alter table public.club_messages add column if not exists kind text not null default 'CHAT';
alter table public.club_messages add column if not exists target_nickname text;
alter table public.club_messages add column if not exists from_rank text;
alter table public.club_messages add column if not exists to_rank text;
alter table public.club_messages drop constraint if exists club_messages_kind_check;
alter table public.club_messages add constraint club_messages_kind_check
  check (kind in ('CHAT', 'CREATE', 'JOIN', 'LEAVE', 'PROMOTE', 'DEMOTE', 'KICK', 'OWNER'));
-- 소식은 내용이 없다
alter table public.club_messages drop constraint if exists club_messages_body_check;
alter table public.club_messages add constraint club_messages_body_check
  check (kind <> 'CHAT' or char_length(btrim(body)) between 1 and 300);

-- 이미 있던 클럽 — 만든 사람이 회원이면 대장
update public.club_members m set rank = 'LEADER'
  from public.clubs c
 where c.id = m.club_id and c.owner = m.uid;

-- 만든 사람이 없는 클럽은 먼저 들어온 사람이 이어받는다
with heir as (
  select distinct on (m.club_id) m.club_id, m.uid
    from public.club_members m
    join public.clubs c on c.id = m.club_id
   where not exists (select 1 from public.club_members o where o.uid = c.owner and o.club_id = c.id)
   order by m.club_id, m.joined_at, m.uid
)
update public.clubs c set owner = h.uid from heir h where c.id = h.club_id;
update public.club_members m set rank = 'LEADER'
  from public.clubs c
 where c.id = m.club_id and c.owner = m.uid;

-- 추방 기간
create or replace function public.club_ban_days()
returns interval
language sql
immutable
as $$ select interval '7 days' $$;

-- 클럽 소식 남기기
create or replace function public.club_event(
  p_club_id bigint, p_uid uuid, p_kind text,
  p_target text default null, p_from text default null, p_to text default null)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.club_messages (club_id, sender_uid, sender_nickname, body, kind, target_nickname, from_rank, to_rank)
  select p_club_id, p_uid, pf.nickname, '', p_kind, p_target, p_from, p_to
    from public.profiles pf where pf.uid = p_uid;
$$;

-- 그 사람을 지금 클럽에서 내보낸다 (나가기 · 다른 클럽으로 옮기기).
-- 처음 만든 사람이 나가면 먼저 들어온 사람이 이어받는다
create or replace function public.club_leave(p_uid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_club bigint;
  v_heir uuid;
begin
  select m.club_id into v_club from public.club_members m where m.uid = p_uid;
  if not found then
    return;
  end if;
  perform 1 from public.clubs c where c.id = v_club for update;

  delete from public.club_members m where m.uid = p_uid;
  perform public.club_event(v_club, p_uid, 'LEAVE');

  if exists (select 1 from public.clubs c where c.id = v_club and c.owner = p_uid) then
    select m.uid into v_heir from public.club_members m
     where m.club_id = v_club order by m.joined_at, m.uid limit 1;
    if found then
      update public.clubs c set owner = v_heir where c.id = v_club;
      update public.club_members m set rank = 'LEADER' where m.uid = v_heir;
      perform public.club_event(v_club, v_heir, 'OWNER');
    end if;
  end if;
end;
$$;

-- 계급 순서. 숫자가 작을수록 높다
create or replace function public.club_rank_order(p_rank text)
returns int
language sql
immutable
as $$ select case p_rank when 'LEADER' then 1 when 'VICE' then 2 else 3 end $$;

-- ------------------------------------------------------------
-- RPC — 클럽 만들기 (0066 과 같고, 다른 클럽에서 나가는 소식과 대장 계급이 더해졌다)
-- ------------------------------------------------------------
create or replace function public.create_club(p_name text, p_level_mode text, p_level int)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_name  text := btrim(coalesce(p_name, ''));
  v_stars int;
  v_id    bigint;
begin
  select pf.stars into v_stars from public.profiles pf where pf.uid = v_uid for update;
  if not found then
    raise exception '로그인이 필요합니다.';
  end if;

  if char_length(v_name) < 2 or char_length(v_name) > 12 then
    raise exception '클럽 이름은 2~12자로 입력해 주세요.';
  end if;
  if p_level_mode is null or p_level_mode not in ('GTE', 'LTE') then
    raise exception '입장 조건을 이상 또는 이하로 골라 주세요.';
  end if;
  if p_level is null or p_level < 1 or p_level > 50 then
    raise exception '입장 조건 레벨은 1~50 사이로 골라 주세요.';
  end if;
  if exists (select 1 from public.clubs c where lower(c.name) = lower(v_name)) then
    raise exception '이미 있는 클럽 이름입니다.';
  end if;
  if v_stars < public.club_price() then
    raise exception '별이 부족합니다.';
  end if;

  update public.profiles pf set stars = stars - public.club_price() where pf.uid = v_uid;
  insert into public.clubs (name, level_mode, level, owner)
  values (v_name, p_level_mode, p_level, v_uid)
  returning id into v_id;

  perform public.club_leave(v_uid);
  insert into public.club_members (uid, club_id, rank) values (v_uid, v_id, 'LEADER');
  perform public.club_event(v_id, v_uid, 'CREATE');

  return json_build_object('id', v_id, 'stars', v_stars - public.club_price());
end;
$$;

-- ------------------------------------------------------------
-- RPC — 클럽 찾기. 0066 에 bannedUntil(추방당해 못 들어가는 때까지)이 더해졌다
-- ------------------------------------------------------------
create or replace function public.list_clubs()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_level int;
begin
  select public.level_of(pf.xp) into v_level from public.profiles pf where pf.uid = v_uid;
  if not found then
    raise exception '로그인이 필요합니다.';
  end if;

  return coalesce((
    select json_agg(x.card order by x.members desc, x.created_at desc)
      from (
        select public.club_card(c.id)
               || jsonb_build_object(
                    'mine', exists (select 1 from public.club_members m
                                     where m.uid = v_uid and m.club_id = c.id),
                    'bannedUntil', b.until,
                    'canJoin', case c.level_mode
                                 when 'GTE' then v_level >= c.level
                                 else v_level <= c.level
                               end
                               and b.until is null
                               and (select count(*) from public.club_members m where m.club_id = c.id)
                                   < public.club_max_members()) as card,
               (select count(*) from public.club_members m where m.club_id = c.id) as members,
               c.created_at
          from public.clubs c
          left join public.club_bans b
            on b.club_id = c.id and b.uid = v_uid and b.until > now()
      ) x), '[]'::json);
end;
$$;

-- ------------------------------------------------------------
-- RPC — 클럽 들어가기. 멤버로 들어간다. 추방당하고 7일이 안 지났으면 못 들어간다
-- 아무도 없는 클럽이면 처음 만든 사람과 똑같이 된다(대장)
-- ------------------------------------------------------------
create or replace function public.join_club(p_club_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_level int;
  v_club  public.clubs%rowtype;
  v_empty boolean;
begin
  select public.level_of(pf.xp) into v_level from public.profiles pf where pf.uid = v_uid;
  if not found then
    raise exception '로그인이 필요합니다.';
  end if;

  -- 동시에 들어가도 20명을 넘지 않게 클럽 줄을 잠근다
  select * into v_club from public.clubs c where c.id = p_club_id for update;
  if not found then
    raise exception '없는 클럽입니다.';
  end if;
  if exists (select 1 from public.club_members m where m.uid = v_uid and m.club_id = p_club_id) then
    raise exception '이미 들어가 있는 클럽입니다.';
  end if;
  if exists (select 1 from public.club_bans b
              where b.club_id = p_club_id and b.uid = v_uid and b.until > now()) then
    raise exception '추방당한 클럽에는 7일 동안 들어갈 수 없습니다.';
  end if;
  if (v_club.level_mode = 'GTE' and v_level < v_club.level)
     or (v_club.level_mode = 'LTE' and v_level > v_club.level) then
    raise exception '입장 조건에 맞지 않습니다.';
  end if;
  if (select count(*) from public.club_members m where m.club_id = p_club_id) >= public.club_max_members() then
    raise exception '클럽 인원이 가득 찼습니다.';
  end if;

  perform public.club_leave(v_uid);
  v_empty := not exists (select 1 from public.club_members m where m.club_id = p_club_id);
  insert into public.club_members (uid, club_id, rank)
  values (v_uid, p_club_id, case when v_empty then 'LEADER' else 'MEMBER' end);
  perform public.club_event(p_club_id, v_uid, 'JOIN');
  if v_empty then
    update public.clubs c set owner = v_uid where c.id = p_club_id;
    perform public.club_event(p_club_id, v_uid, 'OWNER');
  end if;
end;
$$;

-- ------------------------------------------------------------
-- RPC — 내 클럽. 들어간 클럽이 없으면 null
-- 클럽 카드 + myRank · isOwner(내가 처음 만든 사람)
--   + people [{ uid, nickname, avatar, level, rank, owner }] (계급 높은 순, 먼저 들어온 순)
-- ------------------------------------------------------------
create or replace function public.my_club()
returns json
language sql
stable
security definer
set search_path = public
as $$
  select (public.club_card(m.club_id)
          || jsonb_build_object(
               'myRank', m.rank,
               'isOwner', c.owner = m.uid,
               'people', (
                 select jsonb_agg(jsonb_build_object(
                          'uid', o.uid, 'nickname', pf.nickname, 'avatar', pf.avatar,
                          'level', public.level_of(pf.xp), 'rank', o.rank, 'owner', c.owner = o.uid)
                          order by public.club_rank_order(o.rank), o.joined_at, o.uid)
                   from public.club_members o
                   join public.profiles pf on pf.uid = o.uid
                  where o.club_id = m.club_id)))::json
    from public.club_members m
    join public.clubs c on c.id = m.club_id
   where m.uid = auth.uid();
$$;

-- ------------------------------------------------------------
-- RPC — 클럽 나가기
-- ------------------------------------------------------------
create or replace function public.leave_club()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.club_members m where m.uid = auth.uid()) then
    raise exception '소속된 클럽이 없습니다';
  end if;
  perform public.club_leave(auth.uid());
end;
$$;

-- 계급을 바꾸거나 추방할 때 나와 상대를 확인한다. 같은 클럽이어야 한다
-- 돌려주는 값: 상대의 지금 계급
create or replace function public.club_check_target(p_uid uuid, out o_club bigint, out o_my_rank text,
                                                    out o_rank text, out o_owner boolean)
language plpgsql
security definer
set search_path = public
as $$
begin
  select m.club_id, m.rank into o_club, o_my_rank from public.club_members m where m.uid = auth.uid();
  if not found then
    raise exception '소속된 클럽이 없습니다';
  end if;
  perform 1 from public.clubs c where c.id = o_club for update;

  if p_uid = auth.uid() then
    raise exception '자신에게는 할 수 없습니다.';
  end if;
  select m.rank, c.owner = m.uid into o_rank, o_owner
    from public.club_members m join public.clubs c on c.id = m.club_id
   where m.uid = p_uid and m.club_id = o_club;
  if not found then
    raise exception '클럽에 없는 사람입니다.';
  end if;
end;
$$;

-- ------------------------------------------------------------
-- RPC — 승급 (대장만). 멤버 → 부대장 → 대장
-- ------------------------------------------------------------
create or replace function public.promote_club_member(p_uid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v       record;
  v_to    text;
  v_nick  text;
begin
  select * into v from public.club_check_target(p_uid);
  if v.o_my_rank <> 'LEADER' then
    raise exception '대장만 승급할 수 있습니다.';
  end if;
  v_to := case v.o_rank when 'MEMBER' then 'VICE' when 'VICE' then 'LEADER' end;
  if v_to is null then
    raise exception '더 승급할 수 없습니다.';
  end if;

  update public.club_members m set rank = v_to where m.uid = p_uid;
  select pf.nickname into v_nick from public.profiles pf where pf.uid = p_uid;
  perform public.club_event(v.o_club, auth.uid(), 'PROMOTE', v_nick, v.o_rank, v_to);
end;
$$;

-- ------------------------------------------------------------
-- RPC — 강등 (대장만). 대장 → 부대장 → 멤버. 처음 만든 사람은 강등당하지 않는다
-- ------------------------------------------------------------
create or replace function public.demote_club_member(p_uid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v       record;
  v_to    text;
  v_nick  text;
begin
  select * into v from public.club_check_target(p_uid);
  if v.o_my_rank <> 'LEADER' then
    raise exception '대장만 강등할 수 있습니다.';
  end if;
  if v.o_owner then
    raise exception '처음 만든 사람은 강등할 수 없습니다.';
  end if;
  v_to := case v.o_rank when 'LEADER' then 'VICE' when 'VICE' then 'MEMBER' end;
  if v_to is null then
    raise exception '멤버는 강등할 수 없습니다.';
  end if;

  update public.club_members m set rank = v_to where m.uid = p_uid;
  select pf.nickname into v_nick from public.profiles pf where pf.uid = p_uid;
  perform public.club_event(v.o_club, auth.uid(), 'DEMOTE', v_nick, v.o_rank, v_to);
end;
$$;

-- ------------------------------------------------------------
-- RPC — 추방 (대장 · 부대장). 멤버만 추방한다. 7일 동안 다시 못 들어온다
-- ------------------------------------------------------------
create or replace function public.kick_club_member(p_uid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v       record;
  v_nick  text;
begin
  select * into v from public.club_check_target(p_uid);
  if v.o_my_rank not in ('LEADER', 'VICE') then
    raise exception '대장과 부대장만 추방할 수 있습니다.';
  end if;
  if v.o_owner or v.o_rank <> 'MEMBER' then
    raise exception '멤버만 추방할 수 있습니다.';
  end if;

  delete from public.club_members m where m.uid = p_uid;
  insert into public.club_bans (club_id, uid, until)
  values (v.o_club, p_uid, now() + public.club_ban_days())
  on conflict (club_id, uid) do update set until = excluded.until;
  select pf.nickname into v_nick from public.profiles pf where pf.uid = p_uid;
  perform public.club_event(v.o_club, auth.uid(), 'KICK', v_nick);
end;
$$;

revoke all on function public.club_event(bigint, uuid, text, text, text, text) from public, anon, authenticated;
revoke all on function public.club_leave(uuid) from public, anon, authenticated;
revoke all on function public.club_check_target(uuid) from public, anon, authenticated;
revoke all on function public.leave_club() from public, anon;
revoke all on function public.promote_club_member(uuid) from public, anon;
revoke all on function public.demote_club_member(uuid) from public, anon;
revoke all on function public.kick_club_member(uuid) from public, anon;
grant execute on function public.leave_club() to authenticated;
grant execute on function public.promote_club_member(uuid) to authenticated;
grant execute on function public.demote_club_member(uuid) to authenticated;
grant execute on function public.kick_club_member(uuid) to authenticated;
