import Avatar from '@mui/material/Avatar';
import Chip from '@mui/material/Chip';
import IconButton from '@mui/material/IconButton';
import List from '@mui/material/List';
import ListItem from '@mui/material/ListItem';
import ListItemAvatar from '@mui/material/ListItemAvatar';
import ListItemText from '@mui/material/ListItemText';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import Tooltip from '@mui/material/Tooltip';
import CheckCircleIcon from '@mui/icons-material/CheckCircle';
import StarIcon from '@mui/icons-material/Star';

import FootIcon from './FootIcon';

// onKick 을 넘기면(방장·대기실) 다른 참가자 옆에 추방 버튼을 보여준다
export default function PlayerList({ players, uid, onKick, kickingUid = null }) {
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
                    {p.level != null && <Chip size="small" variant="outlined" label={`Lv.${p.level}`} />}
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
              {onKick && !isMe && (
                <Tooltip title="추방">
                  <span>
                    <IconButton
                      size="small"
                      color="error"
                      sx={{ ml: 1 }}
                      aria-label={`${p.nickname} 추방`}
                      disabled={kickingUid !== null}
                      loading={kickingUid === p.uid}
                      onClick={() => onKick(p)}
                    >
                      <FootIcon fontSize="small" />
                    </IconButton>
                  </span>
                </Tooltip>
              )}
            </ListItem>
          );
        })}
      </List>
    </Paper>
  );
}
