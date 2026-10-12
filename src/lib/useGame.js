import { useCallback, useEffect, useState } from 'react';
import { supabase } from './supabase';
import { deadRoles, fetchPlayers, fetchResults, fetchRoom, myGameView } from './api';

// 진행 중인 게임의 상태를 모은다.
// 공개 정보(방·참가자·결과)와 비공개 정보(내 직업·내 제출)를 함께 읽되,
// 비공개 쪽은 서버가 본인 몫만 골라 준다.
export function useGame(roomId) {
  const [room, setRoom] = useState(null);
  const [players, setPlayers] = useState([]);
  const [results, setResults] = useState([]);
  const [view, setView] = useState(null);
  const [viewError, setViewError] = useState('');
  // 비공개 방에서 내가 죽었을 때만 받는 전체 직업
  const [roles, setRoles] = useState(null);
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
        let v = null;
        try {
          v = await myGameView(roomId);
          setView(v);
          setViewError('');
        } catch (e) {
          // 조용히 넘기면 직업 카드와 채팅이 이유 없이 사라진다.
          // 사유를 남겨 화면에 보여준다.
          setView(null);
          setViewError(e.message || '내 정보를 불러오지 못했습니다.');
        }

        // 비공개 방에서 죽었으면 다른 사람의 직업을 본다. 끝난 뒤에는 승패 화면이 보여준다
        if (v && v.alive === false && r.is_public === false && r.phase !== 'ENDED') {
          try {
            setRoles(await deadRoles(roomId));
          } catch {
            // 0050 적용 전이거나 조건이 바뀌었으면 보여주지 않는다
            setRoles(null);
          }
        } else {
          setRoles(null);
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

    // Realtime 알림을 놓쳐도 화면이 지난 페이즈에 멈추지 않도록
    // 주기적으로 다시 읽는다. 구독이 정상이면 대체로 변화가 없다.
    const poll = setInterval(reload, 10000);

    return () => {
      clearInterval(poll);
      supabase.removeChannel(channel);
    };
  }, [roomId, reload]);

  return { room, players, results, view, viewError, roles, loading, error, reload };
}
