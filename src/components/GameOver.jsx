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

import RoleAvatar from './RoleAvatar';
import { TEAMS, WINNERS, roleInfo } from '../lib/roles';
import { finalRoles } from '../lib/api';

export default function GameOver({ roomId, winner }) {
  const [rows, setRows] = useState(null);
  const [error, setError] = useState('');

  useEffect(() => {
    finalRoles(roomId).then(setRows).catch((e) => setError(e.message));
  }, [roomId]);

  const w = WINNERS[winner] ?? { title: '게임 종료', emoji: '🏁', color: 'text.primary' };

  return (
    <Stack spacing={2}>
      <Paper sx={{ p: 3, textAlign: 'center' }}>
        <Box sx={{ fontSize: 44, lineHeight: 1 }}>{w.emoji}</Box>
        <Typography variant="h5" sx={{ mt: 1, color: w.color }}>
          {w.title}
        </Typography>
      </Paper>

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
                        <Chip size="small" color={team.color} label={info.name} />
                      </Stack>
                    }
                    secondary={r.alive ? '생존' : '사망'}
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
