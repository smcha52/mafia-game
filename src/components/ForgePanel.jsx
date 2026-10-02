import { useState } from 'react';
import Alert from '@mui/material/Alert';
import Button from '@mui/material/Button';
import Chip from '@mui/material/Chip';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import Typography from '@mui/material/Typography';

// 위조범의 밤 위조. 마피아 투표와 별개로, 고른 사람을 오늘 밤 조사하면 오답이 나온다.
// 영매 조사를 막을 수 있도록 사망자와 자기 자신도 고를 수 있다.
export default function ForgePanel({ players, uid, state, busy, onSubmit }) {
  const [pick, setPick] = useState(null);
  const limit = state?.limit ?? 0;
  const used = state?.used ?? 0;
  const tonight = state?.tonight ?? null;
  const left = Math.max(0, limit - used);
  const nickOf = (id) => players.find((p) => p.uid === id)?.nickname ?? '알 수 없음';

  return (
    <Paper sx={{ p: 2 }}>
      <Stack direction="row" alignItems="center" justifyContent="space-between">
        <Typography variant="subtitle1">🖋️ 위조</Typography>
        <Chip size="small" label={`남은 횟수 ${left} / ${limit}`} />
      </Stack>
      <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
        오늘 밤 위조한 사람을 경찰·탐정·기자·영매가 조사하면 반대 진영으로 나옵니다.
      </Typography>

      {tonight && (
        <Alert severity="success" sx={{ mt: 1.5 }}>
          오늘 밤 <strong>{nickOf(tonight)}</strong>님을 위조했습니다.
        </Alert>
      )}

      {left === 0 ? (
        <Alert severity="info" sx={{ mt: 1.5 }}>위조 기회를 모두 썼습니다.</Alert>
      ) : (
        <>
          <Stack direction="row" spacing={0.75} flexWrap="wrap" useFlexGap sx={{ mt: 1.5 }}>
            {players.map((p) => (
              <Chip
                key={p.uid}
                label={`${p.nickname}${p.uid === uid ? ' (나)' : ''}${p.alive ? '' : ' · 사망'}`}
                color={(pick ?? tonight) === p.uid ? 'primary' : 'default'}
                variant={p.alive ? 'filled' : 'outlined'}
                onClick={() => setPick(p.uid)}
              />
            ))}
          </Stack>
          <Button
            sx={{ mt: 1.5 }}
            fullWidth
            variant="outlined"
            disabled={!pick || pick === tonight || busy !== ''}
            loading={busy === 'forge'}
            onClick={() => onSubmit(pick)}
          >
            {tonight ? '위조 대상 바꾸기' : '위조 확정'}
          </Button>
        </>
      )}
    </Paper>
  );
}
