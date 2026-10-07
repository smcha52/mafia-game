import { useCallback, useEffect, useState } from 'react';
import Box from '@mui/material/Box';
import CircularProgress from '@mui/material/CircularProgress';
import Stack from '@mui/material/Stack';
import Typography from '@mui/material/Typography';

import AccountBar from './components/AccountBar';
import HomePage from './pages/HomePage';
import GamePage from './pages/GamePage';
import LobbyPage from './pages/LobbyPage';
import LoginPage from './pages/LoginPage';
import SetupNotice from './pages/SetupNotice';
import TutorialPage from './pages/TutorialPage';
import {
  expireIfIdle, isConfigured, markTutorialDone, myProfile, supabase, touchActive,
} from './lib/supabase';
import { heartbeat, myActiveRoom, takeKickNotice } from './lib/api';

export default function App() {
  const [booting, setBooting] = useState(true);
  const [bootError, setBootError] = useState('');
  const [uid, setUid] = useState(null);
  // 로그인한 사람의 프로필. 없으면 로그인 화면을 보여준다
  const [profile, setProfile] = useState(null);
  const [roomId, setRoomId] = useState(null);
  const [phase, setPhase] = useState(null);
  // 첫 화면에 띄울 안내 (추방 등)
  const [notice, setNotice] = useState('');
  // 로그인 화면에서 로그인(가입)하면 튜토리얼부터 한다
  const [tutorial, setTutorial] = useState(false);
  // 튜토리얼을 끝까지 마친 적이 있는지. 없으면 건너뛸 수 없다
  const [tutorialDone, setTutorialDone] = useState(false);
  // 튜토리얼을 마친 뒤의 안내 단계.
  // READY: 첫 화면 "한판 돌려 봅시다" · 승패 화면 "재시작" 안내 → FREE: 첫 화면 "자유롭게 하세요"
  const [guide, setGuide] = useState(null);

  // 로그인한 사람의 프로필을 읽고, 참가 중이던 방이 있으면 대기실로 복원한다 (§8.1-5)
  // fromLogin 이면 방금 로그인한 것이라 튜토리얼을 시작한다.
  // 튜토리얼을 한 번도 마치지 않았으면 새로고침해도 튜토리얼부터 한다
  const loadAccount = useCallback(async (fromLogin = false) => {
    const me = await myProfile();
    if (!me) return false;
    touchActive();

    const active = await myActiveRoom();
    setUid(me.uid);
    setProfile(me);
    setTutorialDone(me.tutorialDone);
    if (fromLogin || !me.tutorialDone) setTutorial(true);
    if (active) {
      setRoomId(active.room_id);
      setPhase(active.phase);
    }
    return true;
  }, []);

  // 앱 시작 시 저장된 로그인이 있으면 이어서 쓴다
  useEffect(() => {
    if (!isConfigured) {
      setBooting(false);
      return;
    }
    let cancelled = false;

    (async () => {
      try {
        // 한 달 넘게 접속하지 않았으면 로그아웃한다. 로그아웃되면 화면이 새로 불린다
        if (await expireIfIdle()) return;
        await loadAccount();
      } catch (e) {
        if (!cancelled) setBootError(e.message);
      } finally {
        if (!cancelled) setBooting(false);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [loadAccount]);

  // 로그인해 있는 동안 접속 시각을 갱신한다. 탭을 오래 열어 둔 채여도 접속으로 본다
  const loggedIn = Boolean(profile);
  useEffect(() => {
    if (!loggedIn) return undefined;
    const onVisible = () => {
      if (document.visibilityState === 'visible') touchActive();
    };
    const timer = setInterval(touchActive, 10 * 60 * 1000);
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      clearInterval(timer);
      document.removeEventListener('visibilitychange', onVisible);
    };
  }, [loggedIn]);

  const handleLeave = useCallback(() => {
    setRoomId(null);
    setPhase(null);
  }, []);

  // 내가 모르는 사이 방에서 빠졌을 때. 추방이면 첫 화면에서 알려준다.
  const handleRemoved = useCallback(async () => {
    const from = roomId;
    let kicked = false;
    try {
      kicked = await takeKickNotice(from);
    } catch {
      // 확인에 실패해도 첫 화면으로는 돌아간다
    }
    handleLeave();
    if (kicked) setNotice('당신은 방장에 의해 추방당했습니다');
  }, [roomId, handleLeave]);

  const handleEntered = useCallback((id) => {
    setNotice('');
    // "자유롭게 하세요" 는 다음 방에 들어가면 더 보여주지 않는다
    setGuide((g) => (g === 'FREE' ? null : g));
    setRoomId(id);
  }, []);

  // 게임 화면에서 나가 첫 화면으로 돌아오면 마지막 안내를 보여준다
  const handleLeaveGame = useCallback(() => {
    handleLeave();
    setGuide((g) => (g === 'READY' ? 'FREE' : g));
  }, [handleLeave]);

  // 튜토리얼을 끝까지 마쳤다. 처음이면 계정에 남긴다
  const handleTutorialDone = useCallback(() => {
    setTutorial(false);
    setGuide('READY');
    if (!tutorialDone) {
      setTutorialDone(true);
      // 저장에 실패하면 다음 로그인 때 한 번 더 할 뿐이다
      markTutorialDone().catch(() => {});
    }
  }, [tutorialDone]);

  // 방에 있는 동안 heartbeat 를 보낸다. 브라우저를 닫으면 끊기고,
  // 60초 뒤 서버가 방에서 내보낸다. 새로고침은 그 안에 다시 보내므로 자리가 유지된다.
  useEffect(() => {
    if (!roomId) return undefined;

    const beat = () => {
      heartbeat(roomId).catch((e) => {
        // 자리를 비운 사이 이미 내보내졌으면 첫 화면으로 돌아간다
        if (e.message.includes('참가자가 아닙니다')) handleRemoved();
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
  }, [roomId, handleRemoved]);

  const handleStarted = useCallback(() => setPhase('NIGHT'), []);
  // 게임이 끝나면 늘어난 XP 를 다시 읽는다
  const handleEnded = useCallback(async () => {
    try {
      const me = await myProfile();
      if (me) setProfile(me);
    } catch {
      // 못 읽으면 다음 접속 때 반영된다
    }
  }, []);
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
      </Stack>
    );
  }

  if (!profile) {
    return (
      <Box sx={{ minHeight: '100dvh', px: 2, py: 4 }}>
        <LoginPage onLoggedIn={() => loadAccount(true)} />
      </Box>
    );
  }

  return (
    <Box sx={{ minHeight: '100dvh', px: 2, py: 2 }}>
      <AccountBar nickname={profile.nickname} xp={profile.xp} />
      {tutorial ? (
        <TutorialPage
          nickname={profile.nickname}
          canSkip={tutorialDone}
          onDone={handleTutorialDone}
          onSkip={() => setTutorial(false)}
        />
      ) : !roomId ? (
        <HomePage
          nickname={profile.nickname}
          onEntered={handleEntered}
          notice={notice}
          onCloseNotice={() => setNotice('')}
          hint={guide === 'READY'
            ? '준비됐나요? 한판 돌려 봅시다!'
            : guide === 'FREE'
              ? '이제 더 알려줄 게 없습니다. 자유롭게 하세요!'
              : ''}
        />
      ) : phase && phase !== 'LOBBY' ? (
        <GamePage
          roomId={roomId}
          uid={uid}
          onLeave={handleLeaveGame}
          onLobby={handleLobby}
          onEnded={handleEnded}
          endHint={guide === 'READY' ? '재시작을 하시면 그대로 한판 더 하실 수 있습니다.' : ''}
        />
      ) : (
        <LobbyPage
          roomId={roomId}
          uid={uid}
          onLeave={handleLeave}
          onRemoved={handleRemoved}
          onStarted={handleStarted}
        />
      )}
    </Box>
  );
}

// 로그아웃하거나 다른 탭에서 로그아웃되면 처음부터 다시 불러 로그인 화면으로 돌아간다
if (isConfigured) {
  supabase.auth.onAuthStateChange((event) => {
    if (event === 'SIGNED_OUT') window.location.reload();
  });
}
