import { useState } from 'react';
import Alert from '@mui/material/Alert';
import Button from '@mui/material/Button';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import Tab from '@mui/material/Tab';
import Tabs from '@mui/material/Tabs';
import TextField from '@mui/material/TextField';
import Typography from '@mui/material/Typography';

import { signIn, signUp } from '../lib/supabase';

// 오늘 날짜 (생년월일 입력의 최댓값)
function today() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

// 게임 시작 전 화면. 로그인하거나 닉네임·비밀번호·생년월일로 가입한다.
export default function LoginPage({ onLoggedIn }) {
  const [mode, setMode] = useState('login');
  const [nickname, setNickname] = useState('');
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [birth, setBirth] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const isSignUp = mode === 'signup';
  const nick = nickname.trim();
  const mismatch = isSignUp && confirm.length > 0 && confirm !== password;
  const shortPassword = isSignUp && password.length > 0 && password.length < 6;

  const canSubmit = isSignUp
    ? nick.length > 0 && password.length >= 6 && confirm === password && birth !== ''
    : nick.length > 0 && password.length > 0;

  function changeMode(next) {
    setMode(next);
    setError('');
    setPassword('');
    setConfirm('');
  }

  async function submit(e) {
    e.preventDefault();
    if (!canSubmit || busy) return;
    setBusy(true);
    setError('');
    try {
      if (isSignUp) await signUp(nick, password, birth);
      else await signIn(nick, password);
      if (!(await onLoggedIn())) throw new Error('프로필을 찾을 수 없습니다. 다시 가입해 주세요.');
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  }

  return (
    <Stack alignItems="center" spacing={3} sx={{ maxWidth: 420, mx: 'auto' }}>
      <Stack alignItems="center" spacing={0.5}>
        <Typography variant="h5">마피아 게임</Typography>
        <Typography variant="body2" color="text.secondary">
          5~15명이 함께하는 온라인 추리 게임
        </Typography>
      </Stack>

      <Paper sx={{ width: '100%', overflow: 'hidden' }}>
        <Tabs value={mode} onChange={(_, v) => changeMode(v)} variant="fullWidth">
          <Tab value="login" label="로그인" disabled={busy} />
          <Tab value="signup" label="회원가입" disabled={busy} />
        </Tabs>

        <Stack component="form" onSubmit={submit} spacing={2.5} sx={{ p: 3 }}>
          <TextField
            label="닉네임"
            value={nickname}
            onChange={(e) => setNickname(e.target.value)}
            slotProps={{ htmlInput: { maxLength: 12 } }}
            helperText={isSignUp ? '12자 이내, 게임에서 이 닉네임을 씁니다' : ' '}
            fullWidth
            autoComplete="username"
          />

          <TextField
            label="비밀번호"
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            error={shortPassword}
            helperText={isSignUp ? '6자 이상' : ' '}
            fullWidth
            autoComplete={isSignUp ? 'new-password' : 'current-password'}
          />

          {isSignUp && (
            <>
              <TextField
                label="비밀번호 확인"
                type="password"
                value={confirm}
                onChange={(e) => setConfirm(e.target.value)}
                error={mismatch}
                helperText={mismatch ? '비밀번호가 같지 않습니다' : ' '}
                fullWidth
                autoComplete="new-password"
              />

              <TextField
                label="생년월일"
                type="date"
                value={birth}
                onChange={(e) => setBirth(e.target.value)}
                slotProps={{
                  inputLabel: { shrink: true },
                  htmlInput: { min: '1900-01-01', max: today() },
                }}
                sx={{ '& input': { colorScheme: 'dark' } }}
                fullWidth
              />
            </>
          )}

          {error && <Alert severity="error">{error}</Alert>}

          <Button type="submit" variant="contained" size="large" disabled={!canSubmit} loading={busy}>
            {isSignUp ? '가입하고 시작하기' : '로그인'}
          </Button>
        </Stack>
      </Paper>
    </Stack>
  );
}
