import { useEffect, useState } from 'react';
import Alert from '@mui/material/Alert';
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Chip from '@mui/material/Chip';
import CircularProgress from '@mui/material/CircularProgress';
import IconButton from '@mui/material/IconButton';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import Tooltip from '@mui/material/Tooltip';
import Typography from '@mui/material/Typography';
import ContentCopyIcon from '@mui/icons-material/ContentCopy';
import LogoutIcon from '@mui/icons-material/Logout';

import PlayerList from '../components/PlayerList';
import { useRoom } from '../lib/useRoom';
import { leaveRoom, setReady, startGame } from '../lib/api';

const MIN_PLAYERS = 5;
const MAX_PLAYERS = 15;

export default function LobbyPage({ roomId, uid, onLeave, onStarted }) {
  const { room, players, loading, error } = useRoom(roomId);
  const [busy, setBusy] = useState('');
  const [actionError, setActionError] = useState('');
  const [copied, setCopied] = useState(false);

  const started = Boolean(room) && room.phase !== 'LOBBY';

  // 방이 시작되면 상위에서 게임 화면으로 바꾼다.
  // 렌더 중에 부모 state 를 건드리면 안 되므로 effect 에서 알린다.
  useEffect(() => {
    if (started) onStarted?.();
  }, [started, onStarted]);

  const me = players.find((p) => p.uid === uid) ?? null;
  // 방장 판정은 rooms.host_uid 를 기준으로 한다.
  // 참가자 목록에서 나를 찾는 방식은 목록이 늦게 오면 조용히 틀린 답을 낸다.
  const isHost = Boolean(room) && room.host_uid === uid;
  // 목록은 왔는데 내가 없으면 세션이 어긋난 것이다. 조용히 넘기지 않는다.
  const sessionMismatch = players.length > 0 && !me;
  const total = players.length;
  const readyCount = players.filter((p) => p.is_ready).length;
  const canStart = total >= MIN_PLAYERS && total <= MAX_PLAYERS && readyCount === total;

  async function run(kind, fn) {
    setBusy(kind);
    setActionError('');
    try {
      await fn();
    } catch (e) {
      setActionError(e.message);
    } finally {
      setBusy('');
    }
  }

  async function handleCopy() {
    try {
      await navigator.clipboard.writeText(room.code);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      // 클립보드 권한이 없으면 무시한다 — 코드는 화면에 이미 보인다
    }
  }

  if (loading) {
    return (
      <Stack sx={{ minHeight: '60dvh' }} alignItems="center" justifyContent="center">
        <CircularProgress />
      </Stack>
    );
  }

  if (error || !room) {
    return (
      <Stack spacing={2} sx={{ maxWidth: 420, mx: 'auto' }}>
        <Alert severity="error">{error || '방을 찾을 수 없습니다. 방장이 나갔을 수 있습니다.'}</Alert>
        <Button variant="outlined" onClick={onLeave}>
          첫 화면으로
        </Button>
      </Stack>
    );
  }

  if (started) {
    return (
      <Stack sx={{ minHeight: '40dvh' }} alignItems="center" justifyContent="center">
        <CircularProgress />
      </Stack>
    );
  }

  return (
    <Stack spacing={2.5} sx={{ maxWidth: 480, mx: 'auto' }}>
      <Paper sx={{ p: 2.5 }}>
        <Stack direction="row" alignItems="center" justifyContent="space-between">
          <Box>
            <Typography variant="body2" color="text.secondary">
              방 코드
            </Typography>
            <Typography variant="h5" sx={{ letterSpacing: '0.25em', fontFamily: 'monospace' }}>
              {room.code}
            </Typography>
          </Box>
          <Tooltip title={copied ? '복사됨' : '코드 복사'}>
            <IconButton onClick={handleCopy} aria-label="방 코드 복사">
              <ContentCopyIcon />
            </IconButton>
          </Tooltip>
        </Stack>
      </Paper>

      <Stack direction="row" alignItems="center" justifyContent="space-between">
        <Typography variant="h6">참가자</Typography>
        <Chip
          size="small"
          color={total >= MIN_PLAYERS ? 'success' : 'default'}
          label={`${readyCount} / ${total}명 준비`}
        />
      </Stack>

      <PlayerList players={players} uid={uid} />

      {total < MIN_PLAYERS && (
        <Alert severity="info">
          {MIN_PLAYERS - total}명이 더 필요합니다. (최소 {MIN_PLAYERS}명 · 최대 {MAX_PLAYERS}명)
        </Alert>
      )}

      {sessionMismatch && (
        <Alert
          severity="warning"
          action={
            <Button color="inherit" size="small" onClick={() => window.location.reload()}>
              새로고침
            </Button>
          }
        >
          이 브라우저의 로그인 정보가 참가자 목록과 맞지 않습니다.
          새로고침해도 같으면 나갔다가 다시 입장해 주세요.
        </Alert>
      )}

      {actionError && <Alert severity="error">{actionError}</Alert>}

      <Stack spacing={1.5}>
        {isHost ? (
          <Button
            variant="contained"
            size="large"
            disabled={!canStart || busy !== ''}
            loading={busy === 'start'}
            onClick={() => run('start', () => startGame(roomId))}
          >
            게임 시작
          </Button>
        ) : (
          <Button
            variant={me?.is_ready ? 'outlined' : 'contained'}
            size="large"
            disabled={busy !== ''}
            loading={busy === 'ready'}
            onClick={() => run('ready', () => setReady(roomId, !me?.is_ready))}
          >
            {me?.is_ready ? '준비 취소' : '준비 완료'}
          </Button>
        )}

        <Button
          color="inherit"
          startIcon={<LogoutIcon />}
          disabled={busy !== ''}
          loading={busy === 'leave'}
          onClick={() => run('leave', async () => {
            await leaveRoom(roomId);
            onLeave();
          })}
        >
          {isHost ? '방 닫고 나가기' : '나가기'}
        </Button>
      </Stack>
    </Stack>
  );
}
