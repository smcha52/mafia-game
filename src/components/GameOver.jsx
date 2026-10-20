import { useEffect, useState } from 'react';
import Alert from '@mui/material/Alert';
import Box from '@mui/material/Box';
import Chip from '@mui/material/Chip';
import List from '@mui/material/List';
import ListItem from '@mui/material/ListItem';
import ListItemAvatar from '@mui/material/ListItemAvatar';
import ListItemText from '@mui/material/ListItemText';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import Typography from '@mui/material/Typography';

import ResultChips from './ResultChips';
import RoleAvatar from './RoleAvatar';
import { TEAMS, WINNERS, didWin, roleInfo } from '../lib/roles';
import { finalRoles } from '../lib/api';
import { streakBonus } from '../lib/level';
import { t } from '../lib/i18n';

// uid 를 넘기면 내가 이번 판에 얻은 XP 를 따로 보여준다
export default function GameOver({ roomId, winner, uid }) {
  const [rows, setRows] = useState(null);
  const [error, setError] = useState('');

  useEffect(() => {
    finalRoles(roomId).then(setRows).catch((e) => setError(e.message));
  }, [roomId]);

  const w = WINNERS[winner] ?? { title: t('게임 종료'), emoji: '🏁', color: 'text.primary' };
  // XP 는 0038 적용 뒤에만 온다
  const mine = rows?.find((r) => r.uid === uid);
  const hasXp = mine?.xpGained != null;
  // 이번 판 연승 보너스. 0062 적용 전이면 streak 가 오지 않아 0 이다
  const bonus = streakBonus(mine?.streak ?? 0);

  return (
    <Stack spacing={2}>
      <Paper sx={{ p: 3, textAlign: 'center' }}>
        <Box sx={{ fontSize: 44, lineHeight: 1 }}>{w.emoji}</Box>
        <Typography variant="h5" sx={{ mt: 1, color: w.color }}>
          {w.title}
        </Typography>
        {winner === 'DRAW' && (
          <Typography variant="body2" color="text.secondary" sx={{ mt: 1 }}>
            {t('마지막 날까지 승부가 나지 않았습니다.')}
          </Typography>
        )}
      </Paper>

      {hasXp && (
        <Paper sx={{ p: 2 }}>
          <Stack direction="row" alignItems="center" justifyContent="space-between">
            <Typography fontWeight={700}>{t('이번 판 XP')}</Typography>
            <Typography variant="h6" color="primary.main">+{mine.xpGained} XP</Typography>
          </Stack>
          <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
            {(mine.won ?? didWin(winner, mine.role, mine.team))
              ? t('직업 행동 {xp} XP × 2 (승리)', { xp: mine.xpBase })
              : t(winner === 'DRAW' ? '직업 행동 {xp} XP (무승부)' : '직업 행동 {xp} XP (패배)', { xp: mine.xpBase })}
          </Typography>
          {bonus > 0 && (
            <Typography variant="body2" fontWeight={700} sx={{ mt: 0.5, color: '#ff6d00' }}>
              🔥 {t('{n}연승 보너스 · XP와 재화 +{pct}%', { n: mine.streak, pct: bonus })}
            </Typography>
          )}
        </Paper>
      )}

      {error && <Alert severity="error">{t(error)}</Alert>}

      {rows && (
        <Paper sx={{ overflow: 'hidden' }}>
          <List disablePadding>
            {rows.map((r) => {
              const info = roleInfo(r.role);
              const team = TEAMS[r.team] ?? { name: r.team, color: 'default' };
              return (
                <ListItem key={r.uid} divider>
                  <ListItemAvatar>
                    <RoleAvatar role={r.role} size={44} />
                  </ListItemAvatar>
                  <ListItemText
                    primary={
                      <Stack direction="row" spacing={0.75} alignItems="center" flexWrap="wrap">
                        <span style={{ textDecoration: r.alive ? 'none' : 'line-through' }}>
                          {r.nickname}
                        </span>
                        {r.level != null && (
                          <Chip size="small" variant="outlined" label={`Lv.${r.level}`} />
                        )}
                        <Chip size="small" color={team.color} label={info.name} />
                      </Stack>
                    }
                  />
                  {/* 이번 판 XP 는 서버가 본인 것만 준다 (0039) */}
                  {r.xpGained != null && (
                    <Typography variant="caption" color="text.secondary" sx={{ ml: 1, flexShrink: 0 }}>
                      +{r.xpGained}
                    </Typography>
                  )}
                  {/* 같은 직업이 여럿일 수 있어 서버가 사람 단위로 판정한 won 을 쓴다 (0041) */}
                  <ResultChips
                    alive={r.alive}
                    win={winner === 'DRAW' ? null : (r.won ?? didWin(winner, r.role, r.team))}
                  />
                </ListItem>
              );
            })}
          </List>
        </Paper>
      )}
    </Stack>
  );
}
