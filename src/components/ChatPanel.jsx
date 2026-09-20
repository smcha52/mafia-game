import { useEffect, useRef, useState } from 'react';
import Alert from '@mui/material/Alert';
import Box from '@mui/material/Box';
import Chip from '@mui/material/Chip';
import IconButton from '@mui/material/IconButton';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import TextField from '@mui/material/TextField';
import Typography from '@mui/material/Typography';
import SendIcon from '@mui/icons-material/Send';

import { sendChat } from '../lib/api';

// 페이즈별로 쓸 수 있는 조건이 다르다. 서버가 최종 판정하고
// 여기서는 왜 못 쓰는지 미리 알려준다.
function writeState({ phase, alive, team }) {
  if (phase === 'LOBBY') return { can: true, note: '' };
  if (phase === 'ENDED') return { can: true, note: '' };
  if (phase === 'DAY') {
    return alive
      ? { can: true, note: '' }
      : { can: false, note: '사망하여 대화할 수 없습니다. 읽기만 가능합니다.' };
  }
  if (phase === 'NIGHT') {
    if (team !== 'MAFIA') {
      return { can: false, note: '밤에는 마피아 진영만 대화할 수 있습니다.' };
    }
    return alive
      ? { can: true, note: '' }
      : { can: false, note: '사망하여 대화할 수 없습니다.' };
  }
  return { can: false, note: '' };
}

export default function ChatPanel({ roomId, phase, uid, alive = true, team = null, messages }) {
  const [body, setBody] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const endRef = useRef(null);

  const isMafiaChannel = phase === 'NIGHT';
  const { can, note } = writeState({ phase, alive, team });

  // 새 메시지가 오면 아래로 붙인다
  useEffect(() => {
    endRef.current?.scrollIntoView({ block: 'end' });
  }, [messages]);

  async function submit(e) {
    e?.preventDefault();
    const text = body.trim();
    if (!text || busy) return;
    setBusy(true);
    setError('');
    try {
      await sendChat(roomId, text);
      setBody('');
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Paper sx={{ p: 2 }}>
      <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 1 }}>
        <Typography variant="body2" color="text.secondary">
          {isMafiaChannel ? '마피아 대화' : '전체 대화'}
        </Typography>
        {isMafiaChannel && (
          <Chip size="small" color="error" label="마피아 진영에게만 보입니다" />
        )}
        {phase === 'ENDED' && (
          <Chip size="small" variant="outlined" label="밤 대화까지 모두 공개" />
        )}
      </Stack>

      <Box
        sx={{
          height: 180,
          overflowY: 'auto',
          bgcolor: 'background.default',
          borderRadius: 1,
          p: 1.25,
          mb: 1,
        }}
      >
        {messages.length === 0 ? (
          <Typography variant="body2" color="text.secondary">
            {isMafiaChannel ? '동료와 작전을 의논하세요.' : '아직 대화가 없습니다.'}
          </Typography>
        ) : (
          <Stack spacing={0.75}>
            {messages.map((m) => {
              const mine = m.sender_uid === uid;
              // 종료 후에는 두 채널이 섞여 보이므로 출처를 표시한다
              const tagMafia = m.channel === 'MAFIA' && !isMafiaChannel;
              return (
                <Box key={m.id}>
                  <Stack direction="row" spacing={0.5} alignItems="center">
                    <Typography
                      variant="caption"
                      sx={{ color: mine ? 'primary.main' : 'text.secondary', fontWeight: 700 }}
                    >
                      {m.sender_nickname}
                    </Typography>
                    {tagMafia && (
                      <Chip
                        size="small"
                        color="error"
                        variant="outlined"
                        label={`${m.day_number}일차 밤 · 마피아`}
                        sx={{ height: 18, '& .MuiChip-label': { px: 0.75, fontSize: 10 } }}
                      />
                    )}
                  </Stack>
                  <Typography variant="body2" sx={{ wordBreak: 'break-word' }}>
                    {m.body}
                  </Typography>
                </Box>
              );
            })}
            <div ref={endRef} />
          </Stack>
        )}
      </Box>

      {note && (
        <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mb: 1 }}>
          {note}
        </Typography>
      )}

      {can && (
        <Stack component="form" direction="row" spacing={1} onSubmit={submit}>
          <TextField
            size="small"
            fullWidth
            placeholder={isMafiaChannel ? '동료에게만 보입니다' : '메시지 입력'}
            value={body}
            disabled={busy}
            onChange={(e) => setBody(e.target.value)}
            slotProps={{ htmlInput: { maxLength: 300 } }}
            autoComplete="off"
          />
          <IconButton
            type="submit"
            color="primary"
            disabled={busy || body.trim().length === 0}
            aria-label="보내기"
          >
            <SendIcon />
          </IconButton>
        </Stack>
      )}

      {error && <Alert severity="error" sx={{ mt: 1 }}>{error}</Alert>}
    </Paper>
  );
}
