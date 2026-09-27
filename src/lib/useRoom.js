import { useCallback, useEffect, useRef, useState } from 'react';
import { supabase } from './supabase';
import { fetchPlayers, fetchRoom } from './api';

// 방 상태와 참가자 목록을 실시간으로 동기화한다.
// 새로고침해도 서버에서 다시 읽어오므로 화면이 복원된다. (요구사항 §8.1-5)
export function useRoom(roomId) {
  const [room, setRoom] = useState(null);
  const [players, setPlayers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  // 삭제 알림이 이 방 참가자의 것인지 가려내려고 현재 참가자 id 를 들고 있는다
  const playerIds = useRef(new Set());

  const reload = useCallback(async () => {
    if (!roomId) return;
    try {
      const [r, p] = await Promise.all([fetchRoom(roomId), fetchPlayers(roomId)]);
      setRoom(r);
      setPlayers(p ?? []);
      playerIds.current = new Set((p ?? []).map((x) => x.id));
      setError('');
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, [roomId]);

  useEffect(() => {
    if (!roomId) return undefined;

    setLoading(true);
    reload();

    // rooms / players 변경을 구독한다.
    // 변경 내용을 직접 합치지 않고 다시 읽는다 — RLS 통과 결과와 항상 일치시키기 위해서다.
    const channel = supabase
      .channel(`room:${roomId}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'players', filter: `room_id=eq.${roomId}` },
        reload,
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'rooms', filter: `id=eq.${roomId}` },
        reload,
      )
      // Realtime 은 필터를 건 구독에 DELETE 를 보내지 않는다. 그래서 나가기·추방·
      // 자동 퇴장이 목록에 반영되지 않았다. DELETE 만 필터 없이 받아(행 id 만 온다)
      // 이 방 참가자일 때 다시 읽는다. 추방된 본인도 이 알림으로 바로 빠져나간다.
      .on(
        'postgres_changes',
        { event: 'DELETE', schema: 'public', table: 'players' },
        (payload) => {
          if (playerIds.current.has(payload.old?.id)) reload();
        },
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [roomId, reload]);

  return { room, players, loading, error, reload };
}
