import { useCallback, useEffect, useState } from 'react';
import { supabase } from './supabase';
import { fetchChat } from './api';

// 채팅을 실시간으로 받는다.
// 새 메시지 알림이 오면 직접 합치지 않고 다시 읽는다 —
// RLS 를 통과한 결과와 항상 일치시키기 위해서다.
export function useChat(roomId) {
  const [messages, setMessages] = useState([]);

  const reload = useCallback(async () => {
    if (!roomId) return;
    try {
      setMessages((await fetchChat(roomId)) ?? []);
    } catch {
      // 조회 실패는 화면을 비우지 않고 무시한다
    }
  }, [roomId]);

  useEffect(() => {
    if (!roomId) return undefined;
    reload();

    const channel = supabase
      .channel(`chat:${roomId}`)
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'chat_messages',
          filter: `room_id=eq.${roomId}` },
        reload,
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [roomId, reload]);

  return { messages, reload };
}
