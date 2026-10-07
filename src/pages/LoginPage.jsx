import { useState } from 'react';
import Alert from '@mui/material/Alert';
import AlertTitle from '@mui/material/AlertTitle';
import Button from '@mui/material/Button';
import IconButton from '@mui/material/IconButton';
import InputAdornment from '@mui/material/InputAdornment';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import Tab from '@mui/material/Tab';
import Tabs from '@mui/material/Tabs';
import TextField from '@mui/material/TextField';
import Typography from '@mui/material/Typography';
import Visibility from '@mui/icons-material/Visibility';
import VisibilityOff from '@mui/icons-material/VisibilityOff';

import { signIn, signUp } from '../lib/supabase';

// 오늘 날짜 (생년월일 입력의 최댓값)
function today() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

// 눈 모양 버튼을 누르면 입력한 비밀번호가 보이는 입력칸
function PasswordField(props) {
  const [show, setShow] = useState(false);

  return (
    <TextField
      {...props}
      type={show ? 'text' : 'password'}
      fullWidth
      slotProps={{
        input: {
          endAdornment: (
            <InputAdornment position="end">
              <IconButton
                aria-label={show ? '비밀번호 숨기기' : '비밀번호 보기'}
                onClick={() => setShow((v) => !v)}
                onMouseDown={(e) => e.preventDefault()}
                edge="end"
              >
                {show ? <VisibilityOff /> : <Visibility />}
              </IconButton>
            </InputAdornment>
          ),
        },
      }}
    />
  );
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

      <Stack spacing={0.5} alignItems="center" sx={{ textAlign: 'center' }}>
        <Typography variant="body2">
          계정을 만들 때는 <strong>회원가입</strong>을 하고, 로그아웃을 하면 <strong>로그인</strong>을 해주세요.
        </Typography>
        <Typography variant="body2" color="error" fontWeight={700}>
          &lt;주의&gt; 비밀번호를 잊어버리면 안 됩니다 &lt;주의&gt;
        </Typography>
        <Typography variant="body2" color="text.secondary">
          한 달 이상 접속이 없을 시 자동으로 로그아웃 됩니다.
        </Typography>
      </Stack>

      <Paper sx={{ width: '100%', overflow: 'hidden' }}>
        <Tabs value={mode} onChange={(_, v) => changeMode(v)} variant="fullWidth">
          <Tab value="login" label="로그인" disabled={busy} />
          <Tab value="signup" label="회원가입" disabled={busy} />
        </Tabs>

        <Stack component="form" onSubmit={submit} spacing={2.5} sx={{ p: 3 }}>
          {isSignUp && (
            <Alert severity="info">
              <AlertTitle sx={{ mb: 0.5 }}>회원가입 방법</AlertTitle>
              <Stack component="ol" spacing={0.5} sx={{ m: 0, pl: 2.5 }}>
                <li>닉네임을 정하세요. 게임에서 쓰는 이름이고, 로그인할 때도 씁니다.</li>
                <li>
                  비밀번호를 6자 이상 입력하세요.{' '}
                  <strong>비밀번호는 다시 찾을 수 없으니 까먹지 마세요!</strong>
                </li>
                <li>비밀번호를 한 번 더 입력하고 생년월일을 고르세요.</li>
              </Stack>
              <Typography variant="body2" sx={{ mt: 1 }}>
                가입하면 바로 튜토리얼 게임이 시작됩니다.
              </Typography>
            </Alert>
          )}

          <TextField
            label="닉네임"
            value={nickname}
            onChange={(e) => setNickname(e.target.value)}
            slotProps={{ htmlInput: { maxLength: 12 } }}
            helperText={isSignUp ? '12자 이내, 게임에서 이 닉네임을 씁니다' : ' '}
            fullWidth
            autoComplete="username"
          />

          <PasswordField
            label="비밀번호"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            error={shortPassword}
            helperText={isSignUp ? '6자 이상 · 까먹지 마세요!' : ' '}
            autoComplete={isSignUp ? 'new-password' : 'current-password'}
          />

          {isSignUp && (
            <>
              <PasswordField
                label="비밀번호 확인"
                value={confirm}
                onChange={(e) => setConfirm(e.target.value)}
                error={mismatch}
                helperText={mismatch ? '비밀번호가 같지 않습니다' : ' '}
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
