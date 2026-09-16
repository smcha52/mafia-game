import { useCallback, useEffect, useState } from 'react';
import Box from '@mui/material/Box';
import CircularProgress from '@mui/material/CircularProgress';
import Stack from '@mui/material/Stack';
import Typography from '@mui/material/Typography';

import HomePage from './pages/HomePage';
import LobbyPage from './pages/LobbyPage';
import SetupNotice from './pages/SetupNotice';
import { ensureSession, isConfigured, supabase } from './lib/supabase';
import { myActiveRoom } from './lib/api';

export default function App() {
  const [booting, setBooting] = useState(true);
  const [bootError, setBootError] = useState('');
  const [uid, setUid] = useState(null);
  const [roomId, setRoomId] = useState(null);

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
        if (active) setRoomId(active.room_id);
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

  const handleLeave = useCallback(() => setRoomId(null), []);

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
      {roomId ? (
        <LobbyPage roomId={roomId} uid={uid} onLeave={handleLeave} />
      ) : (
        <HomePage onEntered={setRoomId} />
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
