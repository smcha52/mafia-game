import { useState } from 'react';
import Alert from '@mui/material/Alert';
import Button from '@mui/material/Button';
import Divider from '@mui/material/Divider';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import TextField from '@mui/material/TextField';
import Typography from '@mui/material/Typography';

import { createRoom, joinRoom } from '../lib/api';

export default function HomePage({ onEntered }) {
  const [nickname, setNickname] = useState('');
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState('');
  const [error, setError] = useState('');

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

  const nicknameEmpty = nickname.trim().length === 0;

  return (
    <Stack alignItems="center" spacing={3} sx={{ maxWidth: 420, mx: 'auto' }}>
      <Stack alignItems="center" spacing={0.5}>
        <Typography variant="h5">마피아 게임</Typography>
        <Typography variant="body2" color="text.secondary">
          5~15명이 함께하는 온라인 추리 게임
        </Typography>
      </Stack>

      <Paper sx={{ p: 3, width: '100%' }}>
        <Stack spacing={2.5}>
          <TextField
            label="닉네임"
            value={nickname}
            onChange={(e) => setNickname(e.target.value)}
            slotProps={{ htmlInput: { maxLength: 12 } }}
            helperText="12자 이내"
            fullWidth
            autoComplete="off"
          />

          <Button
            variant="contained"
            size="large"
            disabled={nicknameEmpty || busy !== ''}
            loading={busy === 'create'}
            onClick={() => run('create', () => createRoom(nickname.trim()))}
          >
            방 만들기
          </Button>

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
            disabled={nicknameEmpty || code.trim().length !== 6 || busy !== ''}
            loading={busy === 'join'}
            onClick={() => run('join', () => joinRoom(code.trim(), nickname.trim()))}
          >
            입장하기
          </Button>

          {error && <Alert severity="error">{error}</Alert>}
        </Stack>
      </Paper>
    </Stack>
  );
}
