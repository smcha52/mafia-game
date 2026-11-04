import { useState } from 'react';
import Alert from '@mui/material/Alert';
import Button from '@mui/material/Button';
import Chip from '@mui/material/Chip';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import Typography from '@mui/material/Typography';
import { t } from '../lib/i18n';

// 지금 턴에 맞는 안내 문구. 3번째 턴에 넘기면 받은 사람이 터진다
export function bombTurnText(turn) {
  return turn >= 3
    ? t('당신은 3번째 턴 입니다 다음 사람에게 넘기면 터집니다')
    : t('당신은 {n}번째 턴 입니다 다른 사람에게 넘기세요', { n: turn });
}

// 폭탄을 가진 사람(직업과 상관없이)의 화면. 낮에는 턴 안내, 밤에는 넘길 사람을 고른다.
// 넘기지 않아도 밤이 지나면 턴은 오른다 (0074)
export default function BombPanel({ players, uid, state, isNight, busy, onPass }) {
  const [pick, setPick] = useState(null);
  const nickOf = (id) => players.find((p) => p.uid === id)?.nickname ?? t('알 수 없음');
  const turn = state?.turn ?? 1;

  return (
    <Paper sx={{ p: 2, border: 1, borderColor: 'error.main' }}>
      <Stack direction="row" alignItems="center" justifyContent="space-between">
        <Typography variant="subtitle1">💣 {t('폭탄')}</Typography>
        {state?.count > 1 && <Chip size="small" color="error" label={t('{n}개', { n: state.count })} />}
      </Stack>
      <Alert severity={turn >= 3 ? 'error' : 'warning'} sx={{ mt: 1 }}>
        {bombTurnText(turn)}
      </Alert>

      {isNight && (state?.passed ? (
        <Alert severity="success" sx={{ mt: 1.5 }}>
          {state.passTarget
            ? t('{name}님에게 폭탄을 넘겼습니다.', { name: <strong>{nickOf(state.passTarget)}</strong> })
            : t('폭탄을 넘기지 않았습니다.')}
        </Alert>
      ) : (
        <>
          <Typography variant="body2" color="text.secondary" sx={{ mt: 1.5 }}>
            {t('넘기지 않아도 밤이 지나면 턴이 넘어갑니다.')}
          </Typography>
          <Stack direction="row" spacing={0.75} flexWrap="wrap" useFlexGap sx={{ mt: 1 }}>
            {players.filter((p) => p.alive && p.uid !== uid).map((p) => (
              <Chip
                key={p.uid}
                label={p.nickname}
                color={pick === p.uid ? 'error' : 'default'}
                onClick={() => setPick(p.uid)}
              />
            ))}
          </Stack>
          <Stack spacing={1} sx={{ mt: 1.5 }}>
            <Button
              fullWidth
              variant="contained"
              color="error"
              disabled={!pick || busy !== ''}
              loading={busy === 'bomb-pass'}
              onClick={() => onPass(pick)}
            >
              {t('폭탄 넘기기')}
            </Button>
            <Button
              fullWidth
              color="inherit"
              disabled={busy !== ''}
              loading={busy === 'bomb-keep'}
              onClick={() => onPass(null)}
            >
              {t('넘기지 않기')}
            </Button>
          </Stack>
        </>
      ))}
    </Paper>
  );
}
