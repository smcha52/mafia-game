import { useState } from 'react';
import Alert from '@mui/material/Alert';
import Avatar from '@mui/material/Avatar';
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Chip from '@mui/material/Chip';
import List from '@mui/material/List';
import ListItemAvatar from '@mui/material/ListItemAvatar';
import ListItemButton from '@mui/material/ListItemButton';
import ListItemText from '@mui/material/ListItemText';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import Typography from '@mui/material/Typography';

import RoleAvatar from './RoleAvatar';
import { ALL_ROLES, roleInfo } from '../lib/roles';
import { t } from '../lib/i18n';

// 저격 화면. 대상을 고르고 그 사람의 직업을 맞힌다.
// 맞히면 대상이 죽고, 틀리면 저격수가 죽는다.
export default function AssassinPanel({
  players, uid, onSubmit, onCancel, busy, error, state, isNight,
}) {
  const locked = state?.done === true;
  const submitted = state?.targetUid ?? null;
  const guess = state?.guess ?? null;
  const [target, setTarget] = useState(submitted ?? null);
  const [pick, setPick] = useState(guess ?? null);

  const candidates = players.filter((p) => p.alive && p.uid !== uid);
  const nickOf = (id) => players.find((p) => p.uid === id)?.nickname ?? t('알 수 없음');

  if (locked) {
    const done = state?.resolved === true;
    return (
      <Paper sx={{ p: 2 }}>
        <Stack direction="row" spacing={1} alignItems="center" sx={{ mb: 1 }}>
          <Typography variant="subtitle1">
            🎯 {t(done ? '저격 완료' : '저격 예약됨')}
          </Typography>
        </Stack>
        {done ? (
          <Alert severity={state.success ? 'success' : 'error'}>
            {state.success ? (
              <>
                {t('{name}님은 정말 {role}였습니다. 저격 성공.', {
                  name: <strong>{nickOf(submitted)}</strong>,
                  role: <strong>{roleInfo(guess).name}</strong>,
                })}
              </>
            ) : (
              <>
                {t('{name}님은 {role}였습니다. 당신이 죽었습니다.', {
                  name: <strong>{nickOf(submitted)}</strong>,
                  role: <strong>{roleInfo(state.actualRole).name}</strong>,
                })}
              </>
            )}
          </Alert>
        ) : (
          <Alert severity="warning">
            {t('{name}님을 {role}로 찍었습니다. 아침에 결과가 나옵니다. 맞으면 상대가 죽고, 틀리면 당신이 죽습니다.', {
              name: <strong>{nickOf(submitted)}</strong>,
              role: <strong>{roleInfo(guess).name}</strong>,
            })}
          </Alert>
        )}
        <Button color="inherit" sx={{ mt: 1 }} onClick={onCancel}>
          {t('돌아가기')}
        </Button>
      </Paper>
    );
  }

  return (
    <Paper sx={{ p: 2 }}>
      <Stack direction="row" spacing={1} alignItems="center" sx={{ mb: 1 }}>
        <Typography variant="subtitle1">🎯 {t('저격')}</Typography>
        <Chip size="small" color="error" label={t('틀리면 내가 죽습니다')} />
        <Chip size="small" variant="outlined" label={t(isNight ? '아침에 결과' : '즉시 처리')} />
      </Stack>

      <Typography variant="body2" color="text.secondary" sx={{ mb: 1 }}>
        1. {t('대상을 고르세요')}
      </Typography>

      <Paper variant="outlined" sx={{ overflow: 'hidden', mb: 2 }}>
        <List disablePadding>
          {candidates.map((p) => (
            <ListItemButton
              key={p.uid}
              divider
              selected={target === p.uid}
              onClick={() => setTarget(p.uid)}
            >
              <ListItemAvatar>
                <Avatar sx={{ bgcolor: target === p.uid ? 'error.main' : 'secondary.main' }}>
                  {p.nickname.slice(0, 1)}
                </Avatar>
              </ListItemAvatar>
              <ListItemText primary={p.nickname} />
            </ListItemButton>
          ))}
        </List>
      </Paper>

      <Typography variant="body2" color="text.secondary" sx={{ mb: 1 }}>
        2. {target ? t('{name}님의 직업을 찍으세요', { name: nickOf(target) }) : t('직업을 찍으세요')}
      </Typography>

      <Box
        sx={{
          display: 'grid',
          gridTemplateColumns: { xs: 'repeat(3, 1fr)', sm: 'repeat(4, 1fr)' },
          gap: 0.75,
          mb: 2,
        }}
      >
        {ALL_ROLES.map((code) => {
          const on = pick === code;
          return (
            <Button
              key={code}
              size="small"
              variant={on ? 'contained' : 'outlined'}
              color={on ? 'error' : 'inherit'}
              onClick={() => setPick(code)}
              sx={{ flexDirection: 'column', py: 0.75, minWidth: 0 }}
            >
              <RoleAvatar role={code} size={22} />
              <Typography variant="caption" sx={{ mt: 0.25 }}>
                {roleInfo(code).name}
              </Typography>
            </Button>
          );
        })}
      </Box>

      {error && <Alert severity="error" sx={{ mb: 1 }}>{t(error)}</Alert>}

      <Stack spacing={1}>
        <Button
          variant="contained"
          color="error"
          size="large"
          disabled={!target || !pick || busy !== ''}
          loading={busy === 'assassin'}
          onClick={() => onSubmit(target, pick)}
        >
          {t('저격 확정')}
        </Button>
        <Button color="inherit" disabled={busy !== ''} onClick={onCancel}>
          {t('돌아가기')}
        </Button>
      </Stack>
    </Paper>
  );
}
