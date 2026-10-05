import { useCallback, useEffect, useRef, useState } from 'react';
import Alert from '@mui/material/Alert';
import Button from '@mui/material/Button';
import ButtonBase from '@mui/material/ButtonBase';
import Chip from '@mui/material/Chip';
import CircularProgress from '@mui/material/CircularProgress';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import Typography from '@mui/material/Typography';
import ArrowBackIcon from '@mui/icons-material/ArrowBack';
import RefreshIcon from '@mui/icons-material/Refresh';

import { joinRoom, listRooms } from '../lib/api';

const MAX_PLAYERS = 15;

// 들어갈 수 있는 대기실 목록. 10개씩 보여주고, 새로고침하면 아직 안 본 방 10개를 보여준다.
// 더 볼 방이 없으면 처음부터 다시 보여준다.
export default function RoomListPage({ nickname, onEntered, onBack }) {
  const [rooms, setRooms] = useState([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState('');
  const [error, setError] = useState('');
  // 이번 방 찾기에서 이미 보여준 방
  const seen = useRef(new Set());

  const load = useCallback(async (fresh) => {
    setLoading(true);
    setError('');
    try {
      let list = await listRooms(fresh ? [] : [...seen.current]);
      if (!fresh && list.length === 0) {
        // 다른 방이 없으면 처음부터 다시
        seen.current = new Set();
        list = await listRooms([]);
      }
      if (fresh) seen.current = new Set();
      list.forEach((r) => seen.current.add(r.id));
      setRooms(list);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load(true);
  }, [load]);

  async function enter(room) {
    setBusy(room.id);
    setError('');
    try {
      const result = await joinRoom(room.code, nickname);
      onEntered(result.room_id);
    } catch (e) {
      setError(e.message);
      setBusy('');
    }
  }

  return (
    <Stack spacing={2.5} sx={{ maxWidth: 420, mx: 'auto' }}>
      <Stack direction="row" alignItems="center" justifyContent="space-between">
        <Button color="inherit" startIcon={<ArrowBackIcon />} onClick={onBack} disabled={busy !== ''}>
          처음으로
        </Button>
        <Button
          variant="outlined"
          startIcon={<RefreshIcon />}
          onClick={() => load(false)}
          disabled={loading || busy !== ''}
        >
          새로고침
        </Button>
      </Stack>

      <Stack spacing={0.5}>
        <Typography variant="h6">방 찾기</Typography>
        <Typography variant="body2" color="text.secondary">
          대기 중인 방을 누르면 <strong>{nickname}</strong> 닉네임으로 입장합니다.
        </Typography>
      </Stack>

      {error && <Alert severity="error">{error}</Alert>}

      {loading ? (
        <Stack alignItems="center" sx={{ py: 6 }}>
          <CircularProgress />
        </Stack>
      ) : rooms.length === 0 ? (
        <Paper sx={{ p: 4, textAlign: 'center' }}>
          <Typography color="text.secondary">방이 없음</Typography>
        </Paper>
      ) : (
        <Stack spacing={1}>
          {rooms.map((r) => (
            <Paper key={r.id} sx={{ overflow: 'hidden' }}>
              <ButtonBase
                onClick={() => enter(r)}
                disabled={busy !== ''}
                sx={{ width: '100%', p: 2, justifyContent: 'stretch', textAlign: 'left' }}
              >
                <Stack direction="row" alignItems="center" justifyContent="space-between" sx={{ width: '100%' }}>
                  <Stack spacing={0.25} sx={{ minWidth: 0 }}>
                    <Typography noWrap>
                      <strong>{r.host ?? '알 수 없음'}</strong>님의 방
                    </Typography>
                    <Typography variant="caption" color="text.secondary" sx={{ letterSpacing: '0.2em' }}>
                      {r.code}
                    </Typography>
                  </Stack>
                  {busy === r.id ? (
                    <CircularProgress size={20} />
                  ) : (
                    <Chip
                      size="small"
                      label={`${r.players} / ${MAX_PLAYERS}명`}
                      sx={{ fontVariantNumeric: 'tabular-nums' }}
                    />
                  )}
                </Stack>
              </ButtonBase>
            </Paper>
          ))}
        </Stack>
      )}
    </Stack>
  );
}
