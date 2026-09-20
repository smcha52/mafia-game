import Alert from '@mui/material/Alert';
import AlertTitle from '@mui/material/AlertTitle';
import Chip from '@mui/material/Chip';
import Stack from '@mui/material/Stack';
import Typography from '@mui/material/Typography';

import { TEAM_RESULT, roleInfo } from '../lib/roles';

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
        if (r.kind === 'MEDIUM') {
          return (
            <Alert key={`${r.kind}-${r.day}`} severity="info" icon={false}>
              <AlertTitle sx={{ mb: 0.5 }}>{r.day}일차 밤 · 교신 결과</AlertTitle>
              <Stack direction="row" spacing={0.75} alignItems="center" flexWrap="wrap" useFlexGap>
                <strong>{r.payload.targetNickname}</strong>
                <span>님의 직업은</span>
                <Chip size="small" label={roleInfo(r.payload.role).name} />
                <span>이었습니다.</span>
              </Stack>
              <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 1 }}>
                이 정보는 당신에게만 보입니다.
              </Typography>
            </Alert>
          );
        }
        if (r.kind === 'REPORTER') {
          const t = TEAM_RESULT[r.payload.team] ?? null;
          return (
            <Alert
              key={`${r.kind}-${r.day}`}
              severity={r.payload.success ? 'success' : 'warning'}
              icon={false}
            >
              <AlertTitle sx={{ mb: 0.5 }}>{r.day}일차 밤 · 취재 결과</AlertTitle>
              {r.payload.success ? (
                <Stack direction="row" spacing={0.75} alignItems="center" flexWrap="wrap" useFlexGap>
                  <strong>{r.payload.targetNickname}</strong>
                  <span>님의 진영을</span>
                  {t && <Chip size="small" color={t.color} label={t.label} />}
                  <span>으로 보도했습니다.</span>
                </Stack>
              ) : (
                <div>
                  <strong>{r.payload.targetNickname}</strong>님 취재에 실패했습니다.
                  아무것도 보도되지 않았습니다.
                </div>
              )}
              <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 1 }}>
                이 정보는 당신에게만 보입니다.
              </Typography>
            </Alert>
          );
        }
        if (r.kind === 'DETECTIVE') {
          const cands = r.payload.candidates ?? [];
          return (
            <Alert key={`${r.kind}-${r.day}`} severity="info" icon={false}>
              <AlertTitle sx={{ mb: 0.5 }}>{r.day}일차 밤 · 추리 결과</AlertTitle>
              <div>
                <strong>{r.payload.targetNickname}</strong>님의 직업은 다음 중 하나입니다.
              </div>
              <Stack direction="row" spacing={0.75} sx={{ mt: 1 }} flexWrap="wrap" useFlexGap>
                {cands.map((c) => (
                  <Chip key={c} size="small" label={roleInfo(c).name} />
                ))}
              </Stack>
              <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 1 }}>
                이 중 하나만 진짜입니다. 이 정보는 당신에게만 보입니다.
              </Typography>
            </Alert>
          );
        }
        if (r.kind === 'BODYGUARD') {
          return (
            <Alert
              key={`${r.kind}-${r.day}`}
              severity={r.payload.sacrificed ? 'warning' : 'success'}
              icon={false}
            >
              <AlertTitle sx={{ mb: 0.5 }}>{r.day}일차 밤 · 경호 결과</AlertTitle>
              <div>
                {r.payload.sacrificed
                  ? <><strong>{r.payload.protectedNickname}</strong>님을 지키고 대신 사망했습니다.</>
                  : <><strong>{r.payload.protectedNickname}</strong>님이 공격받았지만 의사의 치료로 둘 다 살았습니다.</>}
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
