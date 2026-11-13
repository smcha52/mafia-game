import { useState } from 'react';
import Alert from '@mui/material/Alert';
import Button from '@mui/material/Button';
import Chip from '@mui/material/Chip';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import Typography from '@mui/material/Typography';
import { t } from '../lib/i18n';

// 산타의 선물(제거 가능)을 받은 사람(직업과 상관없이)의 화면.
// 낮에는 다음 밤에 쓸 수 있다고 알리고, 밤에는 제거할 사람을 고른다 (0075 GIFT_KILL)
export default function GiftKillPanel({ players, uid, state, isNight, busy, onSubmit }) {
  const [pick, setPick] = useState(null);
  const nickOf = (id) => players.find((p) => p.uid === id)?.nickname ?? t('알 수 없음');

  return (
    <Paper sx={{ p: 2, border: 1, borderColor: 'success.main' }}>
      <Typography variant="subtitle1">🎁 {t('산타의 선물 · 제거 가능')}</Typography>
      {!isNight ? (
        <Alert severity="success" sx={{ mt: 1 }}>
          {t('오늘 밤에 한 명을 제거할 수 있습니다.')}
        </Alert>
      ) : state?.acted ? (
        <Alert severity="success" sx={{ mt: 1 }}>
          {state.target
            ? t('{name}님을 제거하기로 했습니다. 아침에 결과가 드러납니다.', { name: <strong>{nickOf(state.target)}</strong> })
            : t('선물을 쓰지 않았습니다.')}
        </Alert>
      ) : (
        <>
          <Typography variant="body2" color="text.secondary" sx={{ mt: 1 }}>
            {t('제거할 사람을 고르세요. 의사 치료와 경호원 보호에 막힐 수 있습니다.')}
          </Typography>
          <Stack direction="row" spacing={0.75} flexWrap="wrap" useFlexGap sx={{ mt: 1 }}>
            {players.filter((p) => p.alive && p.uid !== uid).map((p) => (
              <Chip
                key={p.uid}
                label={p.nickname}
                color={pick === p.uid ? 'success' : 'default'}
                onClick={() => setPick(p.uid)}
              />
            ))}
          </Stack>
          <Stack spacing={1} sx={{ mt: 1.5 }}>
            <Button
              fullWidth
              variant="contained"
              color="success"
              disabled={!pick || busy !== ''}
              loading={busy === 'gift-kill'}
              onClick={() => onSubmit(pick)}
            >
              {t('제거 확정')}
            </Button>
            <Button
              fullWidth
              color="inherit"
              disabled={busy !== ''}
              loading={busy === 'gift-skip'}
              onClick={() => onSubmit(null)}
            >
              {t('오늘은 사용하지 않기')}
            </Button>
          </Stack>
        </>
      )}
    </Paper>
  );
}
