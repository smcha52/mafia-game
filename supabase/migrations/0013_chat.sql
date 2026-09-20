-- ============================================================
-- 마피아 게임 · 채팅
-- ============================================================
-- 요구사항에 없는 추가 기능이다.
--
-- 채널
--   PUBLIC : 대기실·낮·종료 후. 같은 방 참가자면 모두 읽는다
--   MAFIA  : 밤. 마피아 진영만 읽고 쓴다
--
-- 쓰기 권한
--   대기실   전원
--   낮       생존자만 (사망자가 말하면 정보가 새어 게임이 성립하지 않는다)
--   밤       마피아 진영 생존자만
--   종료 후  전원 (사망자 포함)
--
-- 보안 (§6.2)
--   밤 채팅이 다른 진영에게 보이면 게임이 무너진다.
--   RLS 로 읽기를 막고, 쓰기는 RPC 로만 받는다.
--   화면에서 숨기는 방식은 쓰지 않는다.
-- ============================================================

create table if not exists public.chat_messages (
  id         bigint generated always as identity primary key,
  room_id    uuid not null references public.rooms(id) on delete cascade,
  channel    text not null check (channel in ('PUBLIC', 'MAFIA')),
  sender_uid uuid not null,
  sender_nickname text not null,
  body       text not null check (char_length(btrim(body)) between 1 and 300),
  day_number int  not null default 0,
  phase      text not null,
  created_at timestamptz not null default now()
);

create index if not exists chat_room_idx
  on public.chat_messages (room_id, channel, id);

alter table public.chat_messages enable row level security;

-- ------------------------------------------------------------
-- 마피아 진영 여부 (정책 안에서 private_roles 를 직접 읽지 않기 위해)
-- ------------------------------------------------------------

create or replace function public.is_mafia_member(p_room_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.private_roles pr
     where pr.room_id = p_room_id
       and pr.uid = auth.uid()
       and pr.team = 'MAFIA'
  );
$$;

grant execute on function public.is_mafia_member(uuid) to anon, authenticated;

-- ------------------------------------------------------------
-- 읽기 정책 — MAFIA 채널은 마피아 진영만
-- ------------------------------------------------------------

drop policy if exists "채팅 읽기" on public.chat_messages;
create policy "채팅 읽기"
  on public.chat_messages for select
  using (
    public.is_room_member(chat_messages.room_id)
    and (
      chat_messages.channel = 'PUBLIC'
      or public.is_mafia_member(chat_messages.room_id)
    )
  );

grant select on public.chat_messages to anon, authenticated;
revoke insert, update, delete on public.chat_messages from anon, authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public'
       and tablename = 'chat_messages'
  ) then
    alter publication supabase_realtime add table public.chat_messages;
  end if;
end $$;

-- ------------------------------------------------------------
-- 전송 — 페이즈에 따라 채널과 권한이 결정된다
-- ------------------------------------------------------------

create or replace function public.send_chat(p_room_id uuid, p_body text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_room    public.rooms%rowtype;
  v_nick    text;
  v_alive   boolean;
  v_team    text;
  v_channel text;
  v_body    text := btrim(coalesce(p_body, ''));
begin
  if char_length(v_body) = 0 then
    raise exception '내용을 입력해 주세요.';
  end if;
  if char_length(v_body) > 300 then
    raise exception '300자까지 보낼 수 있습니다.';
  end if;

  select * into v_room from public.rooms r where r.id = p_room_id;
  if not found then
    raise exception '존재하지 않는 방입니다.';
  end if;

  select pl.nickname, pl.alive into v_nick, v_alive
    from public.players pl
   where pl.room_id = p_room_id and pl.uid = v_uid;
  if not found then
    raise exception '이 방의 참가자가 아닙니다.';
  end if;

  if v_room.phase = 'LOBBY' then
    v_channel := 'PUBLIC';

  elsif v_room.phase = 'ENDED' then
    -- 게임이 끝났으면 사망자도 이야기할 수 있다
    v_channel := 'PUBLIC';

  elsif v_room.phase = 'DAY' then
    if not v_alive then
      raise exception '사망한 참가자는 낮에 대화할 수 없습니다.';
    end if;
    v_channel := 'PUBLIC';

  elsif v_room.phase = 'NIGHT' then
    select pr.team into v_team
      from public.private_roles pr
     where pr.room_id = p_room_id and pr.uid = v_uid;

    if coalesce(v_team, '') <> 'MAFIA' then
      raise exception '밤에는 마피아 진영만 대화할 수 있습니다.';
    end if;
    if not v_alive then
      raise exception '사망한 참가자는 대화할 수 없습니다.';
    end if;
    v_channel := 'MAFIA';

  else
    raise exception '지금은 대화할 수 없습니다.';
  end if;

  insert into public.chat_messages
    (room_id, channel, sender_uid, sender_nickname, body, day_number, phase)
  values
    (p_room_id, v_channel, v_uid, v_nick, v_body, v_room.day_number, v_room.phase);

  return json_build_object('channel', v_channel);
end;
$$;

grant execute on function public.send_chat(uuid, text) to anon, authenticated;
