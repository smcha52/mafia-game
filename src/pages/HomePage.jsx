import { useState } from 'react';
import Alert from '@mui/material/Alert';
import Button from '@mui/material/Button';
import Divider from '@mui/material/Divider';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import TextField from '@mui/material/TextField';
import Typography from '@mui/material/Typography';
import RefreshIcon from '@mui/icons-material/Refresh';

import RoomListPage from './RoomListPage';
import CreateRoomDialog from '../components/CreateRoomDialog';
import DailyRewards from '../components/DailyRewards';
import { createRoom, joinRoom, quickJoin } from '../lib/api';

// 로그인한 닉네임으로 방에 들어간다
// hint 가 있으면 맨 아래에 안내 문구로 보여준다 (튜토리얼 뒤 안내)
export default function HomePage({ nickname, onEntered, notice = '', onCloseNotice, hint = '' }) {
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState('');
  const [error, setError] = useState('');
  // 방 찾기 화면을 보고 있는지
  const [finding, setFinding] = useState(false);
  const [reloading, setReloading] = useState(false);

  // Ctrl+Shift+R 과 같다. location.reload() 는 캐시를 쓸 수 있으므로
  // 먼저 페이지를 캐시 없이 다시 받아 캐시를 새 배포로 바꾼 뒤 새로고침한다
  async function hardReload() {
    setReloading(true);
    try {
      await fetch(window.location.href, { cache: 'reload' });
    } catch {
      // 받기에 실패해도 새로고침은 한다
    }
    window.location.reload();
  }
  // 방 설정 화면이 열려 있는지와 그 화면의 오류
  const [creating, setCreating] = useState(false);
  const [createError, setCreateError] = useState('');

  async function create(options) {
    setBusy('create');
    setCreateError('');
    try {
      const result = await createRoom(nickname, options);
      onEntered(result.room_id);
    } catch (e) {
      setCreateError(e.message);
      setBusy('');
    }
  }

  async function run(kind, fn) {
    setBusy(kind);
    setError('');
    try {
      const result = await fn();
      onEntered(result.room_id);
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy('');
    }
  }

  if (finding) {
    return (
      <RoomListPage
        nickname={nickname}
        onEntered={onEntered}
        onBack={() => setFinding(false)}
      />
    );
  }

  return (
    <Stack alignItems="center" spacing={3} sx={{ maxWidth: 420, mx: 'auto' }}>
      <Stack alignItems="center" spacing={0.5}>
        <Typography variant="h5">마피아 게임</Typography>
        <Typography variant="body2" color="text.secondary">
          5~15명이 함께하는 온라인 추리 게임
        </Typography>
      </Stack>

      {notice && (
        <Alert severity="warning" onClose={onCloseNotice} sx={{ width: '100%' }}>
          {notice}
        </Alert>
      )}

      <Paper sx={{ p: 3, width: '100%' }}>
        <Stack spacing={2.5}>
          <Button
            variant="contained"
            color="secondary"
            size="large"
            disabled={busy !== ''}
            loading={busy === 'quick'}
            onClick={() => run('quick', () => quickJoin(nickname))}
          >
            빠른 시작
          </Button>

          <Button
            variant="contained"
            size="large"
            disabled={busy !== ''}
            onClick={() => {
              setError('');
              setCreateError('');
              setCreating(true);
            }}
          >
            방 만들기
          </Button>

          <Button
            variant="outlined"
            size="large"
            disabled={busy !== ''}
            onClick={() => {
              setError('');
              setFinding(true);
            }}
          >
            방 찾기
          </Button>

          <DailyRewards />

          <Divider>또는</Divider>

          <TextField
            label="방 코드"
            value={code}
            onChange={(e) => setCode(e.target.value.toUpperCase())}
            slotProps={{ htmlInput: { maxLength: 6, style: { letterSpacing: '0.3em' } } }}
            helperText="6자리 코드"
            fullWidth
            autoComplete="off"
          />

          <Button
            variant="outlined"
            size="large"
            disabled={code.trim().length !== 6 || busy !== ''}
            loading={busy === 'join'}
            onClick={() => run('join', () => joinRoom(code.trim(), nickname))}
          >
            입장하기
          </Button>

          {error && <Alert severity="error">{error}</Alert>}
        </Stack>
      </Paper>

      <CreateRoomDialog
        open={creating}
        busy={busy === 'create'}
        error={createError}
        onClose={() => setCreating(false)}
        onCreate={create}
      />

      {hint && (
        <Alert severity="success" sx={{ width: '100%' }}>
          {hint}
        </Alert>
      )}

      <Stack alignItems="center" spacing={0.75}>
        <Button
          variant="outlined"
          color="inherit"
          startIcon={<RefreshIcon />}
          loading={reloading}
          onClick={hardReload}
        >
          새로고침
        </Button>
        <Typography variant="caption" color="text.secondary" textAlign="center">
          눌러 보세요. 새로운 기능을 사용할 수 있을지도 모릅니다.
        </Typography>
      </Stack>
    </Stack>
  );
}
