import Box from '@mui/material/Box';
import Chip from '@mui/material/Chip';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import Typography from '@mui/material/Typography';

import { TEAMS, roleInfo } from '../lib/roles';

export default function RoleCard({ view }) {
  if (!view) return null;
  const info = roleInfo(view.role);
  const team = TEAMS[view.team] ?? { name: view.team, color: 'default' };
  const mates = (view.mafiaMembers ?? []).filter((m) => m.role !== undefined);

  return (
    <Paper sx={{ p: 2 }}>
      <Stack direction="row" spacing={1.5} alignItems="flex-start">
        <Box sx={{ fontSize: 34, lineHeight: 1 }}>{info.emoji}</Box>
        <Box sx={{ flex: 1, minWidth: 0 }}>
          <Stack direction="row" spacing={1} alignItems="center" flexWrap="wrap">
            <Typography variant="h6">{info.name}</Typography>
            <Chip size="small" color={team.color} label={team.name} />
            {!view.alive && <Chip size="small" label="사망" />}
          </Stack>
          <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
            {info.desc}
          </Typography>

          {mates.length > 0 && (
            <Box sx={{ mt: 1.5 }}>
              <Typography variant="caption" color="text.secondary">
                마피아 진영 — 당신에게만 보입니다
              </Typography>
              <Stack direction="row" spacing={0.75} sx={{ mt: 0.5 }} flexWrap="wrap" useFlexGap>
                {mates.map((m) => (
                  <Chip
                    key={m.uid}
                    size="small"
                    variant={m.alive ? 'filled' : 'outlined'}
                    color={m.alive ? 'error' : 'default'}
                    label={`${m.nickname} · ${roleInfo(m.role).name}`}
                  />
                ))}
              </Stack>
            </Box>
          )}
        </Box>
      </Stack>
    </Paper>
  );
}
