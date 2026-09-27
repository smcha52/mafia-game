import { useCallback, useEffect, useState } from 'react';
import Box from '@mui/material/Box';
import CircularProgress from '@mui/material/CircularProgress';
import Stack from '@mui/material/Stack';
import Typography from '@mui/material/Typography';

import HomePage from './pages/HomePage';
import GamePage from './pages/GamePage';
import LobbyPage from './pages/LobbyPage';
import SetupNotice from './pages/SetupNotice';
import { ensureSession, isConfigured, supabase } from './lib/supabase';
import { heartbeat, myActiveRoom } from './lib/api';

export default function App() {
  const [booting, setBooting] = useState(true);
  const [bootError, setBootError] = useState('');
  const [uid, setUid] = useState(null);
  const [roomId, setRoomId] = useState(null);
  const [phase, setPhase] = useState(null);

  // 앱 시작 시 익명 로그인 후, 참가 중이던 방이 있으면 대기실로 복원한다 (§8.1-5)
  useEffect(() => {
    if (!isConfigured) {
      setBooting(false);
      return;
    }
    let cancelled = false;

    (async () => {
      try {
        const session = await ensureSession();
        if (cancelled) return;
        setUid(session.user.id);

        const active = await myActiveRoom();
        if (cancelled) return;
        if (active) {
          setRoomId(active.room_id);
          setPhase(active.phase);
        }
      } catch (e) {
        if (!cancelled) setBootError(e.message);
      } finally {
        if (!cancelled) setBooting(false);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, []);

  const handleLeave = useCallback(() => {
    setRoomId(null);
    setPhase(null);
  }, []);

  // 방에 있는 동안 heartbeat 를 보낸다. 브라우저를 닫으면 끊기고,
  // 60초 뒤 서버가 방에서 내보낸다. 새로고침은 그 안에 다시 보내므로 자리가 유지된다.
  useEffect(() => {
    if (!roomId) return undefined;

    const beat = () => {
      heartbeat(roomId).catch((e) => {
        // 자리를 비운 사이 이미 내보내졌으면 첫 화면으로 돌아간다
        if (e.message.includes('참가자가 아닙니다')) handleLeave();
      });
    };
    // 백그라운드 탭은 타이머가 늦어지므로 화면에 돌아오면 바로 보낸다
    const onVisible = () => {
      if (document.visibilityState === 'visible') beat();
    };

    beat();
    const timer = setInterval(beat, 15000);
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      clearInterval(timer);
      document.removeEventListener('visibilitychange', onVisible);
    };
  }, [roomId, handleLeave]);

  const handleStarted = useCallback(() => setPhase('NIGHT'), []);
  // 다시하기로 방이 대기실로 돌아가면 화면도 되돌린다
  const handleLobby = useCallback(() => setPhase('LOBBY'), []);

  if (!isConfigured) return <SetupNotice />;

  if (booting) {
    return (
      <Stack sx={{ minHeight: '100dvh' }} alignItems="center" justifyContent="center" spacing={2}>
        <CircularProgress />
        <Typography color="text.secondary">접속 중…</Typography>
      </Stack>
    );
  }

  if (bootError) {
    return (
      <Stack sx={{ minHeight: '100dvh', p: 3 }} alignItems="center" justifyContent="center" spacing={1}>
        <Typography color="error">접속에 실패했습니다.</Typography>
        <Typography color="text.secondary" variant="body2" textAlign="center">
          {bootError}
        </Typography>
        <Typography color="text.secondary" variant="caption" textAlign="center">
          Supabase 대시보드에서 익명 로그인(Anonymous sign-ins)이 켜져 있는지 확인해 주세요.
        </Typography>
      </Stack>
    );
  }

  return (
    <Box sx={{ minHeight: '100dvh', px: 2, py: 4 }}>
      {!roomId ? (
        <HomePage onEntered={setRoomId} />
      ) : phase && phase !== 'LOBBY' ? (
        <GamePage
          roomId={roomId}
          uid={uid}
          onLeave={handleLeave}
          onLobby={handleLobby}
        />
      ) : (
        <LobbyPage
          roomId={roomId}
          uid={uid}
          onLeave={handleLeave}
          onStarted={handleStarted}
        />
      )}
    </Box>
  );
}

// 다른 탭에서 로그아웃되는 등 세션이 사라지면 첫 화면으로 되돌린다
if (isConfigured) {
  supabase.auth.onAuthStateChange((event) => {
    if (event === 'SIGNED_OUT') window.location.reload();
  });
}
