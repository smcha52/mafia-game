import { useCallback, useEffect, useState } from 'react';
import { supabase } from './supabase';
import { fetchPlayers, fetchResults, fetchRoom, myGameView } from './api';

// 진행 중인 게임의 상태를 모은다.
// 공개 정보(방·참가자·결과)와 비공개 정보(내 직업·내 제출)를 함께 읽되,
// 비공개 쪽은 서버가 본인 몫만 골라 준다.
export function useGame(roomId) {
  const [room, setRoom] = useState(null);
  const [players, setPlayers] = useState([]);
  const [results, setResults] = useState([]);
  const [view, setView] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const reload = useCallback(async () => {
    if (!roomId) return;
    try {
      const [r, p, res] = await Promise.all([
        fetchRoom(roomId),
        fetchPlayers(roomId),
        fetchResults(roomId),
      ]);
      setRoom(r);
      setPlayers(p ?? []);
      setResults(res ?? []);

      // 대기실에서는 아직 직업이 없다
      if (r && r.phase !== 'LOBBY') {
        try {
          setView(await myGameView(roomId));
        } catch {
          setView(null);
        }
      }
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

    const channel = supabase
      .channel(`game:${roomId}`)
      .on('postgres_changes',
        { event: '*', schema: 'public', table: 'players', filter: `room_id=eq.${roomId}` },
        reload)
      .on('postgres_changes',
        { event: '*', schema: 'public', table: 'rooms', filter: `id=eq.${roomId}` },
        reload)
      .on('postgres_changes',
        { event: '*', schema: 'public', table: 'public_results', filter: `room_id=eq.${roomId}` },
        reload)
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [roomId, reload]);

  return { room, players, results, view, loading, error, reload };
}
