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

// uid 를 넘기면 내가 이번 판에 얻은 XP 를 따로 보여준다
export default function GameOver({ roomId, winner, uid }) {
  const [rows, setRows] = useState(null);
  const [error, setError] = useState('');

  useEffect(() => {
    finalRoles(roomId).then(setRows).catch((e) => setError(e.message));
  }, [roomId]);

  const w = WINNERS[winner] ?? { title: '게임 종료', emoji: '🏁', color: 'text.primary' };
  // XP 는 0038 적용 뒤에만 온다
  const mine = rows?.find((r) => r.uid === uid);
  const hasXp = mine?.xpGained != null;

  return (
    <Stack spacing={2}>
      <Paper sx={{ p: 3, textAlign: 'center' }}>
        <Box sx={{ fontSize: 44, lineHeight: 1 }}>{w.emoji}</Box>
        <Typography variant="h5" sx={{ mt: 1, color: w.color }}>
          {w.title}
        </Typography>
        {winner === 'DRAW' && (
          <Typography variant="body2" color="text.secondary" sx={{ mt: 1 }}>
            마지막 날까지 승부가 나지 않았습니다.
          </Typography>
        )}
      </Paper>

      {hasXp && (
        <Paper sx={{ p: 2 }}>
          <Stack direction="row" alignItems="center" justifyContent="space-between">
            <Typography fontWeight={700}>이번 판 XP</Typography>
            <Typography variant="h6" color="primary.main">+{mine.xpGained} XP</Typography>
          </Stack>
          <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
            {didWin(winner, mine.role, mine.team)
              ? `직업 행동 ${mine.xpBase} XP × 2 (승리)`
              : `직업 행동 ${mine.xpBase} XP${winner === 'DRAW' ? ' (무승부)' : ' (패배)'}`}
          </Typography>
        </Paper>
      )}

      {error && <Alert severity="error">{error}</Alert>}

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
                  <ResultChips alive={r.alive} win={didWin(winner, r.role, r.team)} />
                </ListItem>
              );
            })}
          </List>
        </Paper>
      )}
    </Stack>
  );
}
