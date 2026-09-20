-- ============================================================
-- 마피아 게임 · 종료 후 마피아 대화 공개
-- ============================================================
-- 이전까지는 MAFIA 채널을 마피아 진영만 영구히 읽을 수 있었다.
-- 게임이 끝난 뒤에는 복기할 수 있도록 전원에게 공개한다.
--
-- 진행 중에는 그대로 막힌다. 종료된 방에서만 열린다.
-- 다음 판은 새 방이므로 이번 판 대화가 영향을 주지 않는다.
-- ============================================================

create or replace function public.room_is_ended(p_room_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.rooms r
     where r.id = p_room_id and r.phase = 'ENDED'
  );
$$;

grant execute on function public.room_is_ended(uuid) to anon, authenticated;

drop policy if exists "채팅 읽기" on public.chat_messages;
create policy "채팅 읽기"
  on public.chat_messages for select
  using (
    public.is_room_member(chat_messages.room_id)
    and (
      chat_messages.channel = 'PUBLIC'
      or public.is_mafia_member(chat_messages.room_id)
      -- 게임이 끝나면 마피아 대화도 복기용으로 공개한다
      or public.room_is_ended(chat_messages.room_id)
    )
  );
