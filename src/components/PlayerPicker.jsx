import Avatar from '@mui/material/Avatar';
import Chip from '@mui/material/Chip';
import List from '@mui/material/List';
import ListItemAvatar from '@mui/material/ListItemAvatar';
import ListItemButton from '@mui/material/ListItemButton';
import ListItemText from '@mui/material/ListItemText';
import Paper from '@mui/material/Paper';
import Radio from '@mui/material/Radio';
import Stack from '@mui/material/Stack';

// 살아 있는 참가자 중에서 대상을 고른다.
// locked 이면 이미 제출한 상태라 바꿀 수 없다.
export default function PlayerPicker({
  players, uid, value, onChange, locked = false, excludeSelf = false,
}) {
  const candidates = players.filter(
    (p) => p.alive && (!excludeSelf || p.uid !== uid),
  );

  return (
    <Paper sx={{ overflow: 'hidden' }}>
      <List disablePadding>
        {candidates.map((p) => {
          const selected = value === p.uid;
          return (
            <ListItemButton
              key={p.uid}
              divider
              selected={selected}
              disabled={locked && !selected}
              onClick={() => !locked && onChange(p.uid)}
            >
              <ListItemAvatar>
                <Avatar sx={{ bgcolor: selected ? 'primary.main' : 'secondary.main' }}>
                  {p.nickname.slice(0, 1)}
                </Avatar>
              </ListItemAvatar>
              <ListItemText
                primary={
                  <Stack direction="row" spacing={0.75} alignItems="center">
                    <span>{p.nickname}</span>
                    {p.uid === uid && <Chip size="small" label="나" />}
                  </Stack>
                }
              />
              <Radio checked={selected} disabled={locked} tabIndex={-1} />
            </ListItemButton>
          );
        })}
      </List>
    </Paper>
  );
}
