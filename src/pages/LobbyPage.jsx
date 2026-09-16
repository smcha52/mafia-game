import { useState } from 'react';
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

export default function LobbyPage({ roomId, uid, onLeave }) {
  const { room, players, loading, error } = useRoom(roomId);
  const [busy, setBusy] = useState('');
  const [actionError, setActionError] = useState('');
  const [copied, setCopied] = useState(false);

  const me = players.find((p) => p.uid === uid) ?? null;
  const isHost = me?.is_host ?? false;
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

  // 2단계(직업 배정)에서 이 화면이 밤/낮 화면으로 교체된다
  if (room.phase !== 'LOBBY') {
    return (
      <Stack spacing={2} sx={{ maxWidth: 420, mx: 'auto' }} alignItems="center">
        <Typography variant="h6">게임이 시작되었습니다</Typography>
        <Typography color="text.secondary" variant="body2" textAlign="center">
          {room.day_number}일차 · {room.phase === 'NIGHT' ? '밤' : '낮'}
        </Typography>
        <Alert severity="info" sx={{ width: '100%' }}>
          직업 배정과 밤/낮 진행은 2단계에서 구현됩니다.
        </Alert>
        <Button
          variant="outlined"
          startIcon={<LogoutIcon />}
          loading={busy === 'leave'}
          onClick={() => run('leave', async () => {
            await leaveRoom(roomId);
            onLeave();
          })}
        >
          나가기
        </Button>
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
