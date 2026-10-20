import Alert from '@mui/material/Alert';
import AlertTitle from '@mui/material/AlertTitle';
import Chip from '@mui/material/Chip';
import Stack from '@mui/material/Stack';
import Typography from '@mui/material/Typography';

import { TEAM_RESULT, roleInfo } from '../lib/roles';
import { t } from '../lib/i18n';

// 나에게만 보이는 조사 결과. 최신 것이 위에 온다.
export default function PrivateResults({ results }) {
  if (!results || results.length === 0) return null;

  return (
    <Stack spacing={1}>
      {results.map((r) => {
        if (r.kind === 'DOCTOR') {
          return (
            <Alert key={`${r.kind}-${r.day}`} severity="success" icon={false}>
              <AlertTitle sx={{ mb: 0.5 }}>{t('{day}일차 밤 · 치료 성공', { day: r.day })}</AlertTitle>
              <div>
                {t('{name}님이 공격받았지만 살려냈습니다.', { name: <strong>{r.payload.savedNickname}</strong> })}
              </div>
              <Typography variant="caption" color="text.secondary">
                {t('이 정보는 당신에게만 보입니다.')}
              </Typography>
            </Alert>
          );
        }
        if (r.kind === 'ASSASSIN') {
          const ok = r.payload.success;
          return (
            <Alert
              key={`${r.kind}-${r.day}`}
              severity={ok ? 'success' : 'error'}
              icon={false}
            >
              <AlertTitle sx={{ mb: 0.5 }}>
                {t(r.payload.phase === 'DAY' ? '{day}일차 낮 · 저격 결과' : '{day}일차 밤 · 저격 결과', { day: r.day })}
              </AlertTitle>
              {ok ? (
                <Stack direction="row" spacing={0.75} alignItems="center" flexWrap="wrap" useFlexGap>
                  <span>
                    {t('{name}님은 정말 {role}이었습니다. 저격 성공.', {
                      name: <strong>{r.payload.targetNickname}</strong>,
                      role: <Chip size="small" color="success" label={roleInfo(r.payload.guess).name} />,
                    })}
                  </span>
                </Stack>
              ) : (
                <Stack direction="row" spacing={0.75} alignItems="center" flexWrap="wrap" useFlexGap>
                  <span>
                    {t('{name}님을 {guess}로 찍었지만 실제로는 {actual}였습니다. 당신이 죽었습니다.', {
                      name: <strong>{r.payload.targetNickname}</strong>,
                      guess: <Chip size="small" variant="outlined" label={roleInfo(r.payload.guess).name} />,
                      actual: <Chip size="small" color="error" label={roleInfo(r.payload.actualRole).name} />,
                    })}
                  </span>
                </Stack>
              )}
              <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 1 }}>
                {t('이 정보는 당신에게만 보입니다.')}
              </Typography>
            </Alert>
          );
        }
        if (r.kind === 'SPY') {
          return (
            <Alert key={`${r.kind}-${r.day}`} severity="info" icon={false}>
              <AlertTitle sx={{ mb: 0.5 }}>{t('{day}일차 낮 · 투표 결과', { day: r.day })}</AlertTitle>
              <Stack direction="row" spacing={0.75} alignItems="center" flexWrap="wrap" useFlexGap>
                <span>
                  {t('당신이 투표한 {name}님의 직업은 {role}입니다.', {
                    name: <strong>{r.payload.targetNickname}</strong>,
                    role: <Chip size="small" color="error" label={roleInfo(r.payload.role).name} />,
                  })}
                </span>
              </Stack>
              <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 1 }}>
                {t('이 정보는 스파이에게만 보입니다.')}
              </Typography>
            </Alert>
          );
        }
        if (r.kind === 'MEDIUM') {
          return (
            <Alert key={`${r.kind}-${r.day}`} severity="info" icon={false}>
              <AlertTitle sx={{ mb: 0.5 }}>{t('{day}일차 밤 · 교신 결과', { day: r.day })}</AlertTitle>
              <Stack direction="row" spacing={0.75} alignItems="center" flexWrap="wrap" useFlexGap>
                <span>
                  {t('{name}님의 직업은 {role}이었습니다.', {
                    name: <strong>{r.payload.targetNickname}</strong>,
                    role: <Chip size="small" label={roleInfo(r.payload.role).name} />,
                  })}
                </span>
              </Stack>
              <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 1 }}>
                {t('이 정보는 당신에게만 보입니다.')}
              </Typography>
            </Alert>
          );
        }
        if (r.kind === 'REPORTER') {
          const team = TEAM_RESULT[r.payload.team] ?? null;
          return (
            <Alert
              key={`${r.kind}-${r.day}`}
              severity={r.payload.success ? 'success' : 'warning'}
              icon={false}
            >
              <AlertTitle sx={{ mb: 0.5 }}>{t('{day}일차 밤 · 취재 결과', { day: r.day })}</AlertTitle>
              {r.payload.success ? (
                <Stack direction="row" spacing={0.75} alignItems="center" flexWrap="wrap" useFlexGap>
                  <span>
                    {t('{name}님의 진영을 {team}으로 보도했습니다.', {
                      name: <strong>{r.payload.targetNickname}</strong>,
                      team: team ? <Chip size="small" color={team.color} label={team.label} /> : '',
                    })}
                  </span>
                </Stack>
              ) : (
                <div>
                  {t('{name}님 취재에 실패했습니다. 아무것도 보도되지 않았습니다.', { name: <strong>{r.payload.targetNickname}</strong> })}
                </div>
              )}
              <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 1 }}>
                {t('이 정보는 당신에게만 보입니다.')}
              </Typography>
            </Alert>
          );
        }
        if (r.kind === 'DETECTIVE') {
          const cands = r.payload.candidates ?? [];
          return (
            <Alert key={`${r.kind}-${r.day}`} severity="info" icon={false}>
              <AlertTitle sx={{ mb: 0.5 }}>{t('{day}일차 밤 · 추리 결과', { day: r.day })}</AlertTitle>
              <div>
                {t('{name}님의 직업은 다음 중 하나입니다.', { name: <strong>{r.payload.targetNickname}</strong> })}
              </div>
              <Stack direction="row" spacing={0.75} sx={{ mt: 1 }} flexWrap="wrap" useFlexGap>
                {cands.map((c) => (
                  <Chip key={c} size="small" label={roleInfo(c).name} />
                ))}
              </Stack>
              <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 1 }}>
                {t('이 중 하나만 진짜입니다. 이 정보는 당신에게만 보입니다.')}
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
              <AlertTitle sx={{ mb: 0.5 }}>{t('{day}일차 밤 · 경호 결과', { day: r.day })}</AlertTitle>
              <div>
                {r.payload.sacrificed
                  ? t('{name}님을 지키고 대신 사망했습니다.', { name: <strong>{r.payload.protectedNickname}</strong> })
                  : t('{name}님이 공격받았지만 의사의 치료로 둘 다 살았습니다.', { name: <strong>{r.payload.protectedNickname}</strong> })}
              </div>
              <Typography variant="caption" color="text.secondary">
                {t('이 정보는 당신에게만 보입니다.')}
              </Typography>
            </Alert>
          );
        }
        if (r.kind !== 'POLICE') return null;
        const team = TEAM_RESULT[r.payload.team] ?? { label: r.payload.team, color: 'default' };
        return (
          <Alert key={`${r.kind}-${r.day}`} severity="info" icon={false}>
            <AlertTitle sx={{ mb: 0.5 }}>
              {t('{day}일차 밤 · 조사 결과', { day: r.day })}
            </AlertTitle>
            <Stack direction="row" spacing={0.75} alignItems="center" flexWrap="wrap" useFlexGap>
              <span>
                {t('{name}님은 {team}입니다.', {
                  name: <strong>{r.payload.targetNickname}</strong>,
                  team: <Chip size="small" color={team.color} label={team.label} />,
                })}
              </span>
            </Stack>
            <Typography variant="caption" color="text.secondary">
              {t('이 정보는 당신에게만 보입니다.')}
            </Typography>
          </Alert>
        );
      })}
    </Stack>
  );
}
