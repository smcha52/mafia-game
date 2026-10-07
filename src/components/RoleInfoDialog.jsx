import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Chip from '@mui/material/Chip';
import Dialog from '@mui/material/Dialog';
import DialogActions from '@mui/material/DialogActions';
import DialogContent from '@mui/material/DialogContent';
import Stack from '@mui/material/Stack';
import Typography from '@mui/material/Typography';

import RoleAvatar from './RoleAvatar';
import { TEAMS, XP_RULES, roleInfo, roleTeam } from '../lib/roles';

// 직업 이름을 누르면 뜨는 설명 — 능력과 XP 얻는 법
export default function RoleInfoDialog({ role, onClose }) {
  const info = role ? roleInfo(role) : null;
  const team = role ? TEAMS[roleTeam(role)] : null;

  return (
    <Dialog open={Boolean(role)} onClose={onClose} fullWidth maxWidth="xs">
      {info && (
        <>
          <DialogContent>
            <Stack direction="row" spacing={1.5} alignItems="center">
              <RoleAvatar role={role} size={52} />
              <Box>
                <Typography variant="h6">{info.name}</Typography>
                <Chip size="small" color={team.color} label={team.name} />
              </Box>
            </Stack>

            <Typography variant="subtitle2" color="text.secondary" sx={{ mt: 2 }}>
              능력
            </Typography>
            <Typography variant="body2" sx={{ mt: 0.5 }}>
              {info.desc}
            </Typography>

            <Typography variant="subtitle2" color="text.secondary" sx={{ mt: 2 }}>
              XP 얻는 법
            </Typography>
            <Box component="ul" sx={{ m: 0, mt: 0.5, pl: 2.5 }}>
              {(XP_RULES[role] ?? []).map((rule) => (
                <Typography key={rule} component="li" variant="body2">
                  {rule}
                </Typography>
              ))}
            </Box>
            <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 1 }}>
              게임이 끝날 때 이기면 2배, 지면 그대로 받습니다.
            </Typography>
          </DialogContent>
          <DialogActions>
            <Button onClick={onClose}>닫기</Button>
          </DialogActions>
        </>
      )}
    </Dialog>
  );
}
