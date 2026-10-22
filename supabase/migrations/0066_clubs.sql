-- ============================================================
-- 마피아 게임 · 클럽
-- ============================================================
-- 별 100 개로 클럽을 만든다. 클럽 이름과 입장 조건(레벨 N 이상 / N 이하, N = 1~50)을 정한다.
-- 클럽 찾기에서 클럽 들어가기를 누르면 그 클럽에 들어가고, 클럽 탭에서 클럽 사람끼리 채팅한다.
--
--   clubs          클럽 하나. 이름은 대소문자를 무시하고 겹치지 않는다
--   club_members   한 사람은 한 클럽에만 들어가 있다. 다른 클럽에 들어가면 옮겨 간다
--   club_messages  클럽 채팅. 그 클럽 사람만 읽는다 (RLS, 실시간)
--
-- 만든 사람은 그 클럽에 바로 들어간다. 클럽 하나에 최대 20명.
-- 익명 사용자(테스트)는 프로필이 없어 클럽 기능을 쓸 수 없다.
-- ============================================================

create table if not exists public.clubs (
  id          bigint generated always as identity primary key,
  name        text not null check (char_length(name) between 2 and 12),
  level_mode  text not null check (level_mode in ('GTE', 'LTE')),
  level       int  not null check (level between 1 and 50),
  owner       uuid not null references public.profiles (uid) on delete cascade,
  created_at  timestamptz not null default now()
);
create unique index if not exists clubs_name_key on public.clubs (lower(name));

create table if not exists public.club_members (
  uid        uuid primary key references public.profiles (uid) on delete cascade,
  club_id    bigint not null references public.clubs (id) on delete cascade,
  joined_at  timestamptz not null default now()
);
create index if not exists club_members_club_idx on public.club_members (club_id);

create table if not exists public.club_messages (
  id               bigint generated always as identity primary key,
  club_id          bigint not null references public.clubs (id) on delete cascade,
  sender_uid       uuid not null,
  sender_nickname  text not null,
  body             text not null check (char_length(btrim(body)) between 1 and 300),
  created_at       timestamptz not null default now()
);
create index if not exists club_messages_club_idx on public.club_messages (club_id, id);

-- 클럽과 회원은 RPC 로만 다룬다
alter table public.clubs enable row level security;
alter table public.club_members enable row level security;
alter table public.club_messages enable row level security;
revoke all on public.clubs from anon, authenticated;
revoke all on public.club_members from anon, authenticated;
revoke all on public.club_messages from anon, authenticated;

-- 클럽 만드는 값 (별)
create or replace function public.club_price()
returns int
language sql
immutable
as $$ select 100 $$;

-- 클럽 하나에 들어갈 수 있는 사람 수
create or replace function public.club_max_members()
returns int
language sql
immutable
as $$ select 20 $$;

-- 내가 그 클럽에 들어가 있는지 (채팅 읽기 정책에서 쓴다)
create or replace function public.is_club_member(p_club_id bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.club_members m
                  where m.uid = auth.uid() and m.club_id = p_club_id);
$$;

-- 클럽 채팅은 그 클럽 사람만 읽는다
drop policy if exists "클럽 채팅 읽기" on public.club_messages;
create policy "클럽 채팅 읽기"
  on public.club_messages for select
  using (public.is_club_member(club_messages.club_id));
grant select on public.club_messages to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'club_messages'
  ) then
    alter publication supabase_realtime add table public.club_messages;
  end if;
end;
$$;

-- 클럽 한 곳 { id, name, levelMode, level, members, maxMembers }
create or replace function public.club_card(p_club_id bigint)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
           'id', c.id, 'name', c.name, 'levelMode', c.level_mode, 'level', c.level,
           'members', (select count(*) from public.club_members m where m.club_id = c.id),
           'maxMembers', public.club_max_members())
    from public.clubs c where c.id = p_club_id;
$$;

-- ------------------------------------------------------------
-- RPC — 클럽 만들기. 별 100 개. 만든 사람은 바로 들어간다 (다른 클럽에 있었으면 옮겨 간다)
-- 만든 뒤 남은 별을 돌려준다
-- p_level_mode = GTE(이상) · LTE(이하), p_level = 1~50
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
  insert into public.club_members (uid, club_id) values (v_uid, v_id)
  on conflict (uid) do update set club_id = excluded.club_id, joined_at = now();

  return json_build_object('id', v_id, 'stars', v_stars - public.club_price());
end;
$$;

-- ------------------------------------------------------------
-- RPC — 클럽 찾기. 모든 클럽 (사람 많은 순, 같으면 최근에 만든 순)
-- [클럽 카드 + mine(내가 들어가 있음) · canJoin(내 레벨이 조건에 맞고 자리가 있음)]
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
                    'canJoin', case c.level_mode
                                 when 'GTE' then v_level >= c.level
                                 else v_level <= c.level
                               end
                               and (select count(*) from public.club_members m where m.club_id = c.id)
                                   < public.club_max_members()) as card,
               (select count(*) from public.club_members m where m.club_id = c.id) as members,
               c.created_at
          from public.clubs c
      ) x), '[]'::json);
end;
$$;

-- ------------------------------------------------------------
-- RPC — 클럽 들어가기. 다른 클럽에 들어가 있었으면 옮겨 간다. 20명이 차면 못 들어간다
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
  if (v_club.level_mode = 'GTE' and v_level < v_club.level)
     or (v_club.level_mode = 'LTE' and v_level > v_club.level) then
    raise exception '입장 조건에 맞지 않습니다.';
  end if;
  if (select count(*) from public.club_members m where m.club_id = p_club_id) >= public.club_max_members() then
    raise exception '클럽 인원이 가득 찼습니다.';
  end if;

  insert into public.club_members (uid, club_id) values (v_uid, p_club_id)
  on conflict (uid) do update set club_id = excluded.club_id, joined_at = now();
end;
$$;

-- ------------------------------------------------------------
-- RPC — 내 클럽. 들어간 클럽이 없으면 null
-- ------------------------------------------------------------
create or replace function public.my_club()
returns json
language sql
stable
security definer
set search_path = public
as $$
  select public.club_card(m.club_id)::json
    from public.club_members m where m.uid = auth.uid();
$$;

-- ------------------------------------------------------------
-- RPC — 클럽 채팅 보내기 (내 클럽에)
-- ------------------------------------------------------------
create or replace function public.send_club_chat(p_body text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_club bigint;
  v_nick text;
  v_body text := btrim(coalesce(p_body, ''));
begin
  select m.club_id, pf.nickname into v_club, v_nick
    from public.club_members m join public.profiles pf on pf.uid = m.uid
   where m.uid = v_uid;
  if not found then
    raise exception '소속된 클럽이 없습니다';
  end if;
  if char_length(v_body) < 1 or char_length(v_body) > 300 then
    raise exception '메시지는 1~300자로 입력해 주세요.';
  end if;

  insert into public.club_messages (club_id, sender_uid, sender_nickname, body)
  values (v_club, v_uid, v_nick, v_body);
end;
$$;

revoke all on function public.is_club_member(bigint) from public, anon;
revoke all on function public.club_card(bigint) from public, anon, authenticated;
revoke all on function public.create_club(text, text, int) from public, anon;
revoke all on function public.list_clubs() from public, anon;
revoke all on function public.join_club(bigint) from public, anon;
revoke all on function public.my_club() from public, anon;
revoke all on function public.send_club_chat(text) from public, anon;
grant execute on function public.is_club_member(bigint) to authenticated;
grant execute on function public.create_club(text, text, int) to authenticated;
grant execute on function public.list_clubs() to authenticated;
grant execute on function public.join_club(bigint) to authenticated;
grant execute on function public.my_club() to authenticated;
grant execute on function public.send_club_chat(text) to authenticated;
