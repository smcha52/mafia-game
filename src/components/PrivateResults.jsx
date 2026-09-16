import Alert from '@mui/material/Alert';
import AlertTitle from '@mui/material/AlertTitle';
import Chip from '@mui/material/Chip';
import Stack from '@mui/material/Stack';
import Typography from '@mui/material/Typography';

import { TEAM_RESULT } from '../lib/roles';

// 나에게만 보이는 조사 결과. 최신 것이 위에 온다.
export default function PrivateResults({ results }) {
  if (!results || results.length === 0) return null;

  return (
    <Stack spacing={1}>
      {results.map((r) => {
        if (r.kind === 'DOCTOR') {
          return (
            <Alert key={`${r.kind}-${r.day}`} severity="success" icon={false}>
              <AlertTitle sx={{ mb: 0.5 }}>{r.day}일차 밤 · 치료 성공</AlertTitle>
              <div>
                <strong>{r.payload.savedNickname}</strong>님이 공격받았지만 살려냈습니다.
              </div>
              <Typography variant="caption" color="text.secondary">
                이 정보는 당신에게만 보입니다.
              </Typography>
            </Alert>
          );
        }
        if (r.kind !== 'POLICE') return null;
        const t = TEAM_RESULT[r.payload.team] ?? { label: r.payload.team, color: 'default' };
        return (
          <Alert key={`${r.kind}-${r.day}`} severity="info" icon={false}>
            <AlertTitle sx={{ mb: 0.5 }}>
              {r.day}일차 밤 · 조사 결과
            </AlertTitle>
            <Stack direction="row" spacing={0.75} alignItems="center" flexWrap="wrap" useFlexGap>
              <strong>{r.payload.targetNickname}</strong>
              <span>님은</span>
              <Chip size="small" color={t.color} label={t.label} />
              <span>입니다.</span>
            </Stack>
            <Typography variant="caption" color="text.secondary">
              이 정보는 당신에게만 보입니다.
            </Typography>
          </Alert>
        );
      })}
    </Stack>
  );
}
