import { useCallback, useEffect, useState } from 'react';
import Alert from '@mui/material/Alert';
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Chip from '@mui/material/Chip';
import CircularProgress from '@mui/material/CircularProgress';
import Dialog from '@mui/material/Dialog';
import DialogActions from '@mui/material/DialogActions';
import DialogContent from '@mui/material/DialogContent';
import IconButton from '@mui/material/IconButton';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import Tab from '@mui/material/Tab';
import Tabs from '@mui/material/Tabs';
import TextField from '@mui/material/TextField';
import Typography from '@mui/material/Typography';
import ArrowBackIcon from '@mui/icons-material/ArrowBack';
import PersonRemoveIcon from '@mui/icons-material/PersonRemove';

import ProfileAvatar from './ProfileAvatar';
import {
  acceptFriendRequest, declineFriendRequest, myFriends, removeFriend, searchPlayer, sendFriendRequest,
} from '../lib/api';
import { t } from '../lib/i18n';

// 친구 목록을 다시 읽는 간격. 접속 여부와 방 코드가 바뀐다
const REFRESH_MS = 20000;

// 프로필 그림 · 닉네임 · 레벨 한 줄. right 에 버튼이나 표시를 넣는다
function PlayerRow({ p, children, right }) {
  return (
    <Paper sx={{ p: 1.5 }}>
      <Stack direction="row" alignItems="center" spacing={1.5}>
        <ProfileAvatar avatar={p.avatar} nickname={p.nickname} size={44} />
        <Stack spacing={0.25} sx={{ minWidth: 0, flex: 1 }}>
          <Stack direction="row" alignItems="center" spacing={0.75}>
            <Typography fontWeight={700} noWrap>{p.nickname}</Typography>
            {p.level != null && <Chip size="small" variant="outlined" label={`Lv.${p.level}`} />}
          </Stack>
          {children}
        </Stack>
        {right}
      </Stack>
    </Paper>
  );
}

// 친구 추가 탭 — 닉네임으로 찾아 프로필을 보고 친구 추가를 요청한다
function AddTab({ onChanged }) {
  const [query, setQuery] = useState('');
  // undefined = 아직 찾지 않음, null = 없음
  const [found, setFound] = useState(undefined);
  const [busy, setBusy] = useState('');
  const [error, setError] = useState('');

  async function search(e) {
    e.preventDefault();
    if (!query.trim() || busy) return;
    setBusy('search');
    setError('');
    try {
      setFound(await searchPlayer(query.trim()));
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy('');
    }
  }

  async function run(fn) {
    setBusy('action');
    setError('');
    try {
      await fn();
      setFound(await searchPlayer(found.nickname));
      onChanged?.();
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy('');
    }
  }

  const status = found?.status;
  let right = null;
  if (status === 'NONE') {
    right = (
      <Button variant="contained" size="small" loading={busy === 'action'}
        onClick={() => run(() => sendFriendRequest(found.uid))}>
        {t('친구 추가')}
      </Button>
    );
  } else if (status === 'RECEIVED') {
    right = (
      <Button variant="contained" size="small" loading={busy === 'action'}
        onClick={() => run(() => acceptFriendRequest(found.uid))}>
        {t('받아 주기')}
      </Button>
    );
  } else if (status) {
    const label = { SENT: '요청함', FRIEND: '친구', ME: '나' }[status];
    right = <Chip size="small" color={status === 'FRIEND' ? 'success' : 'default'} label={t(label)} />;
  }

  return (
    <Stack spacing={2}>
      <Stack component="form" direction="row" spacing={1} onSubmit={search}>
        <TextField
          size="small"
          fullWidth
          label={t('플레이어 닉네임')}
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          slotProps={{ htmlInput: { maxLength: 12 } }}
          autoComplete="off"
        />
        <Button type="submit" variant="outlined" disabled={!query.trim()} loading={busy === 'search'}>
          {t('검색')}
        </Button>
      </Stack>

      {error && <Alert severity="error">{t(error)}</Alert>}

      {found === null && (
        <Paper sx={{ p: 3, textAlign: 'center' }}>
          <Typography color="text.secondary">{t('그 닉네임의 플레이어가 없습니다.')}</Typography>
        </Paper>
      )}

      {found && (
        <PlayerRow p={found} right={right}>
          {status === 'RECEIVED' && (
            <Typography variant="caption" color="text.secondary">
              {t('{name}님이 친구추가를 요청했습니다', { name: found.nickname })}
            </Typography>
          )}
        </PlayerRow>
      )}
    </Stack>
  );
}

// 친구 탭 — 받은 요청과 친구 목록 (접속 여부, 들어가 있는 방 코드)
function FriendsTab({ data, busy, onAccept, onDecline, onRemove }) {
  if (!data) {
    return (
      <Stack alignItems="center" sx={{ py: 6 }}>
        <CircularProgress />
      </Stack>
    );
  }

  return (
    <Stack spacing={2}>
      {data.requests.length > 0 && (
        <Stack spacing={1}>
          <Typography variant="subtitle2" color="text.secondary">{t('받은 친구 요청')}</Typography>
          {data.requests.map((p) => (
            <PlayerRow
              key={p.uid}
              p={p}
              right={(
                <Stack direction="row" spacing={0.5} sx={{ flexShrink: 0 }}>
                  <Button variant="contained" size="small" disabled={busy !== ''}
                    loading={busy === `accept:${p.uid}`} onClick={() => onAccept(p)}>
                    {t('받아 주기')}
                  </Button>
                  <Button color="inherit" size="small" disabled={busy !== ''}
                    loading={busy === `decline:${p.uid}`} onClick={() => onDecline(p)}>
                    {t('거절')}
                  </Button>
                </Stack>
              )}
            >
              <Typography variant="caption" color="text.secondary">
                {t('{name}님이 친구추가를 요청했습니다', { name: p.nickname })}
              </Typography>
            </PlayerRow>
          ))}
        </Stack>
      )}

      <Stack spacing={1}>
        <Typography variant="subtitle2" color="text.secondary">
          {t('친구 {n}명', { n: data.friends.length })}
        </Typography>
        {data.friends.length === 0 ? (
          <Paper sx={{ p: 3, textAlign: 'center' }}>
            <Typography color="text.secondary">
              {t('아직 친구가 없습니다. 친구 추가 탭에서 닉네임으로 찾아보세요.')}
            </Typography>
          </Paper>
        ) : (
          data.friends.map((p) => (
            <PlayerRow
              key={p.uid}
              p={p}
              right={(
                <Stack direction="row" alignItems="center" spacing={0.25} sx={{ flexShrink: 0 }}>
                  <Chip
                    size="small"
                    color={p.online ? 'success' : 'default'}
                    variant={p.online ? 'filled' : 'outlined'}
                    label={t(p.online ? '접속 중' : '접속 안 함')}
                  />
                  <IconButton
                    size="small"
                    aria-label={t('{name} 친구 삭제', { name: p.nickname })}
                    disabled={busy !== ''}
                    onClick={() => onRemove(p)}
                  >
                    <PersonRemoveIcon fontSize="small" />
                  </IconButton>
                </Stack>
              )}
            >
              {/* 비공개 방은 서버가 코드를 주지 않는다 */}
              {p.room && (
                <Typography variant="caption" color="text.secondary">
                  {p.room.code
                    ? t(p.room.phase === 'LOBBY' ? '대기실 · 방 코드 {code}' : '게임 중 · 방 코드 {code}', {
                      code: <strong style={{ letterSpacing: '0.15em' }}>{p.room.code}</strong>,
                    })
                    : t(p.room.phase === 'LOBBY' ? '대기실 · 비공개 방' : '게임 중 · 비공개 방')}
                </Typography>
              )}
            </PlayerRow>
          ))
        )}
      </Stack>

      {data.sent.length > 0 && (
        <Stack spacing={1}>
          <Typography variant="subtitle2" color="text.secondary">{t('보낸 친구 요청')}</Typography>
          {data.sent.map((p) => (
            <PlayerRow key={p.uid} p={p} right={<Chip size="small" label={t('요청함')} />} />
          ))}
        </Stack>
      )}
    </Stack>
  );
}

// 연속 출석 아래 친구 버튼으로 여는 화면. 친구 목록으로 열리고, 탭으로 친구 추가와 오간다
export default function FriendDialog({ open, onClose }) {
  const [tab, setTab] = useState('FRIENDS');
  const [data, setData] = useState(null);
  const [busy, setBusy] = useState('');
  const [error, setError] = useState('');
  // 삭제할지 묻고 있는 친구
  const [removing, setRemoving] = useState(null);

  useEffect(() => {
    if (open) setTab('FRIENDS');
  }, [open]);

  const load = useCallback(async () => {
    try {
      setData(await myFriends());
      setError('');
    } catch (e) {
      setError(e.message);
    }
  }, []);

  // 열려 있는 동안 접속 여부와 방 코드를 새로 읽는다
  useEffect(() => {
    if (!open) return undefined;
    load();
    const timer = setInterval(load, REFRESH_MS);
    return () => clearInterval(timer);
  }, [open, load]);

  async function run(kind, fn) {
    setBusy(kind);
    setError('');
    try {
      await fn();
      await load();
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy('');
    }
  }

  const requests = data?.requests.length ?? 0;

  return (
    <Dialog open={open} onClose={onClose} fullScreen>
      <Box sx={{ maxWidth: 480, width: '100%', mx: 'auto', px: 2, py: 2 }}>
        <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 1 }}>
          <IconButton onClick={onClose} aria-label={t('뒤로')}>
            <ArrowBackIcon />
          </IconButton>
          <Typography variant="h6" sx={{ flex: 1 }}>{t('친구')}</Typography>
        </Stack>

        <Tabs value={tab} onChange={(_, v) => setTab(v)} variant="fullWidth" sx={{ mb: 2 }}>
          <Tab value="FRIENDS" label={requests > 0 ? `${t('친구')} (${requests})` : t('친구')} />
          <Tab value="ADD" label={t('친구 추가')} />
        </Tabs>

        {error && <Alert severity="error" sx={{ mb: 2 }}>{t(error)}</Alert>}

        {tab === 'ADD' ? (
          <AddTab onChanged={load} />
        ) : (
          <FriendsTab
            data={data}
            busy={busy}
            onAccept={(p) => run(`accept:${p.uid}`, () => acceptFriendRequest(p.uid))}
            onDecline={(p) => run(`decline:${p.uid}`, () => declineFriendRequest(p.uid))}
            onRemove={setRemoving}
          />
        )}
      </Box>

      <Dialog open={removing !== null} onClose={busy ? undefined : () => setRemoving(null)} maxWidth="xs" fullWidth>
        <DialogContent>
          <Typography>
            {t('{name}님을 친구에서 삭제할까요? 상대 친구 목록에서도 사라집니다.', { name: <strong>{removing?.nickname}</strong> })}
          </Typography>
        </DialogContent>
        <DialogActions>
          <Button color="inherit" disabled={busy !== ''} onClick={() => setRemoving(null)}>{t('취소')}</Button>
          <Button
            color="error"
            variant="contained"
            loading={busy === 'remove'}
            onClick={() => run('remove', () => removeFriend(removing.uid)).then(() => setRemoving(null))}
          >
            {t('삭제')}
          </Button>
        </DialogActions>
      </Dialog>
    </Dialog>
  );
}
