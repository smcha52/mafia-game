import Chip from '@mui/material/Chip';
import List from '@mui/material/List';
import ListItem from '@mui/material/ListItem';
import ListItemAvatar from '@mui/material/ListItemAvatar';
import ListItemText from '@mui/material/ListItemText';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import Typography from '@mui/material/Typography';

import RoleAvatar from './RoleAvatar';
import { TEAMS, roleInfo } from '../lib/roles';
import { t } from '../lib/i18n';

// 비공개 방에서 죽은 사람에게만 보여주는 참가자 직업 (0050 dead_roles)
// rows = [{ uid, nickname, role, team, alive }]
export default function DeadRoles({ rows, uid }) {
  if (!rows?.length) return null;

  return (
    <Stack spacing={1}>
      <Typography variant="subtitle2" color="text.secondary">
        {t('참가자 직업 — 사망자에게만 보입니다')}
      </Typography>
      <Paper sx={{ overflow: 'hidden' }}>
        <List disablePadding>
          {rows.map((r) => {
            const info = roleInfo(r.role);
            const team = TEAMS[r.team] ?? { name: r.team, color: 'default' };
            return (
              <ListItem key={r.uid} divider>
                <ListItemAvatar>
                  <RoleAvatar role={r.role} size={36} />
                </ListItemAvatar>
                <ListItemText
                  primary={
                    <Stack direction="row" spacing={0.75} alignItems="center" flexWrap="wrap">
                      <span style={{ textDecoration: r.alive ? 'none' : 'line-through' }}>
                        {r.nickname}
                      </span>
                      {r.uid === uid && <Chip size="small" label={t('나')} />}
                      <Chip size="small" color={team.color} label={info.name} />
                    </Stack>
                  }
                />
                {!r.alive && <Chip size="small" variant="outlined" label={t('사망')} />}
              </ListItem>
            );
          })}
        </List>
      </Paper>
    </Stack>
  );
}
