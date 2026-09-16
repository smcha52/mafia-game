import Avatar from '@mui/material/Avatar';
import Chip from '@mui/material/Chip';
import List from '@mui/material/List';
import ListItem from '@mui/material/ListItem';
import ListItemAvatar from '@mui/material/ListItemAvatar';
import ListItemText from '@mui/material/ListItemText';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import CheckCircleIcon from '@mui/icons-material/CheckCircle';
import StarIcon from '@mui/icons-material/Star';

export default function PlayerList({ players, uid }) {
  return (
    <Paper sx={{ overflow: 'hidden' }}>
      <List disablePadding>
        {players.map((p) => {
          const isMe = p.uid === uid;
          return (
            <ListItem key={p.id} divider>
              <ListItemAvatar>
                <Avatar sx={{ bgcolor: p.is_host ? 'primary.main' : 'secondary.main' }}>
                  {p.nickname.slice(0, 1)}
                </Avatar>
              </ListItemAvatar>
              <ListItemText
                primary={
                  <Stack direction="row" spacing={0.75} alignItems="center" flexWrap="wrap">
                    <span>{p.nickname}</span>
                    {isMe && <Chip size="small" label="나" />}
                    {p.is_host && (
                      <Chip size="small" color="primary" icon={<StarIcon />} label="방장" />
                    )}
                  </Stack>
                }
              />
              {p.is_ready && !p.is_host && (
                <CheckCircleIcon color="success" aria-label="준비 완료" />
              )}
            </ListItem>
          );
        })}
      </List>
    </Paper>
  );
}
