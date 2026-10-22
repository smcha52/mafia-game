import { useCallback, useEffect, useRef, useState } from 'react';
import Alert from '@mui/material/Alert';
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Chip from '@mui/material/Chip';
import CircularProgress from '@mui/material/CircularProgress';
import Dialog from '@mui/material/Dialog';
import IconButton from '@mui/material/IconButton';
import Paper from '@mui/material/Paper';
import Slider from '@mui/material/Slider';
import Stack from '@mui/material/Stack';
import Tab from '@mui/material/Tab';
import Tabs from '@mui/material/Tabs';
import TextField from '@mui/material/TextField';
import ToggleButton from '@mui/material/ToggleButton';
import ToggleButtonGroup from '@mui/material/ToggleButtonGroup';
import Typography from '@mui/material/Typography';
import ArrowBackIcon from '@mui/icons-material/ArrowBack';
import SendIcon from '@mui/icons-material/Send';
import StarIcon from '@mui/icons-material/Star';

import {
  createClub, fetchClubChat, joinClub, listClubs, myClub, sendClubChat,
} from '../lib/api';
import { supabase } from '../lib/supabase';
import { t } from '../lib/i18n';

// 클럽 만드는 값 (별). 서버 club_price() 와 같다
const CLUB_PRICE = 100;
const LEVEL_MIN = 1;
const LEVEL_MAX = 50;
// 실시간 알림을 놓쳐도 채팅을 다시 읽는 간격
const CHAT_POLL_MS = 10000;

// 입장 조건 글자. GTE = 이상, LTE = 이하
function conditionLabel(club) {
  return t(club.levelMode === 'GTE' ? '레벨 {n} 이상' : '레벨 {n} 이하', { n: club.level });
}

// 클럽 이름 · 입장 조건 · 사람 수
function ClubInfo({ club }) {
  return (
    <Stack direction="row" alignItems="center" spacing={0.75} flexWrap="wrap" useFlexGap>
      <Chip size="small" variant="outlined" label={conditionLabel(club)} />
      <Typography variant="caption" color="text.secondary">
        {t('회원 {n}/{max}명', { n: club.members, max: club.maxMembers })}
      </Typography>
    </Stack>
  );
}

// 클럽 채팅. 새 메시지 알림이 오면 다시 읽는다 (RLS 가 내 클럽 것만 준다)
function ClubChat({ clubId, uid }) {
  const [messages, setMessages] = useState([]);
  const [body, setBody] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const endRef = useRef(null);

  const reload = useCallback(async () => {
    try {
      setMessages((await fetchClubChat(clubId)) ?? []);
    } catch {
      // 조회 실패는 화면을 비우지 않고 무시한다
    }
  }, [clubId]);

  useEffect(() => {
    reload();
    const channel = supabase
      .channel(`club:${clubId}`)
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'club_messages', filter: `club_id=eq.${clubId}` },
        reload,
      )
      .subscribe();
    const poll = setInterval(reload, CHAT_POLL_MS);
    return () => {
      clearInterval(poll);
      supabase.removeChannel(channel);
    };
  }, [clubId, reload]);

  // 새 메시지가 오면 아래로 붙인다
  useEffect(() => {
    endRef.current?.scrollIntoView({ block: 'end' });
  }, [messages]);

  async function submit(e) {
    e.preventDefault();
    const text = body.trim();
    if (!text || busy) return;
    setBusy(true);
    setError('');
    try {
      await sendClubChat(text);
      setBody('');
      await reload();
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Paper sx={{ p: 2 }}>
      <Box
        sx={{
          height: 320,
          overflowY: 'auto',
          bgcolor: 'background.default',
          borderRadius: 1,
          p: 1.25,
          mb: 1,
        }}
      >
        {messages.length === 0 ? (
          <Typography variant="body2" color="text.secondary">{t('아직 대화가 없습니다.')}</Typography>
        ) : (
          <Stack spacing={0.75}>
            {messages.map((m) => (
              <Box key={m.id}>
                <Typography
                  variant="caption"
                  sx={{ color: m.sender_uid === uid ? 'primary.main' : 'text.secondary', fontWeight: 700 }}
                >
                  {m.sender_nickname}
                </Typography>
                <Typography variant="body2" sx={{ wordBreak: 'break-word' }}>{m.body}</Typography>
              </Box>
            ))}
            <div ref={endRef} />
          </Stack>
        )}
      </Box>

      {error && <Alert severity="error" sx={{ mb: 1 }}>{t(error)}</Alert>}

      <Stack component="form" direction="row" spacing={1} onSubmit={submit}>
        <TextField
          size="small"
          fullWidth
          placeholder={t('메시지 입력')}
          value={body}
          disabled={busy}
          onChange={(e) => setBody(e.target.value)}
          slotProps={{ htmlInput: { maxLength: 300 } }}
          autoComplete="off"
        />
        <IconButton type="submit" color="primary" disabled={!body.trim() || busy} aria-label={t('보내기')}>
          <SendIcon />
        </IconButton>
      </Stack>
    </Paper>
  );
}

// 클럽 탭 — 들어간 클럽의 이름과 채팅. 없으면 안내만
function ClubTab({ club, uid }) {
  if (club === undefined) {
    return (
      <Stack alignItems="center" sx={{ py: 6 }}>
        <CircularProgress />
      </Stack>
    );
  }
  if (club === null) {
    return (
      <Paper sx={{ p: 3, textAlign: 'center' }}>
        <Typography color="text.secondary">{t('소속된 클럽이 없습니다')}</Typography>
      </Paper>
    );
  }
  return (
    <Stack spacing={2}>
      <Stack spacing={0.5}>
        <Typography variant="h5" fontWeight={700}>{club.name}</Typography>
        <ClubInfo club={club} />
      </Stack>
      <ClubChat clubId={club.id} uid={uid} />
    </Stack>
  );
}

// 클럽 찾기 탭 — 모든 클럽과 클럽 들어가기
function FindTab({ clubs, busy, onJoin }) {
  if (!clubs) {
    return (
      <Stack alignItems="center" sx={{ py: 6 }}>
        <CircularProgress />
      </Stack>
    );
  }
  if (clubs.length === 0) {
    return (
      <Paper sx={{ p: 3, textAlign: 'center' }}>
        <Typography color="text.secondary">{t('아직 클럽이 없습니다. 클럽 만들기에서 만들어 보세요.')}</Typography>
      </Paper>
    );
  }
  return (
    <Stack spacing={1}>
      {clubs.map((c) => (
        <Paper key={c.id} sx={{ p: 1.5 }}>
          <Stack direction="row" alignItems="center" spacing={1.5}>
            <Stack spacing={0.5} sx={{ minWidth: 0, flex: 1 }}>
              <Typography fontWeight={700} noWrap>{c.name}</Typography>
              <ClubInfo club={c} />
            </Stack>
            {c.mine ? (
              <Chip size="small" color="success" label={t('소속 중')} />
            ) : (
              <Button
                variant="contained"
                size="small"
                disabled={!c.canJoin || busy !== ''}
                loading={busy === `join:${c.id}`}
                onClick={() => onJoin(c)}
                sx={{ flexShrink: 0 }}
              >
                {t('클럽 들어가기')}
              </Button>
            )}
          </Stack>
        </Paper>
      ))}
    </Stack>
  );
}

// 클럽 만들기 탭 — 이름 · 입장 조건(레벨 N 이상 / 이하) · 별 100
function CreateTab({ stars, onCreated }) {
  const [name, setName] = useState('');
  const [mode, setMode] = useState('GTE');
  const [level, setLevel] = useState(1);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const trimmed = name.trim();
  const enough = stars >= CLUB_PRICE;

  async function submit(e) {
    e.preventDefault();
    if (busy) return;
    setBusy(true);
    setError('');
    try {
      await createClub(trimmed, mode, level);
      setName('');
      setMode('GTE');
      setLevel(1);
      onCreated();
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Stack component="form" spacing={2.5} onSubmit={submit}>
      <TextField
        label={t('클럽 이름')}
        value={name}
        onChange={(e) => setName(e.target.value)}
        helperText={t('2~12자')}
        slotProps={{ htmlInput: { maxLength: 12 } }}
        autoComplete="off"
        fullWidth
      />

      <Stack spacing={1}>
        <Typography variant="subtitle2">
          {t('클럽 입장 조건')} — {conditionLabel({ levelMode: mode, level })}
        </Typography>
        <ToggleButtonGroup size="small" exclusive value={mode} onChange={(_, v) => v && setMode(v)}>
          <ToggleButton value="GTE" sx={{ px: 2 }}>{t('이상')}</ToggleButton>
          <ToggleButton value="LTE" sx={{ px: 2 }}>{t('이하')}</ToggleButton>
        </ToggleButtonGroup>
        <Slider
          value={level}
          min={LEVEL_MIN}
          max={LEVEL_MAX}
          step={1}
          valueLabelDisplay="auto"
          onChange={(_, v) => setLevel(v)}
          marks={[{ value: LEVEL_MIN, label: LEVEL_MIN }, { value: LEVEL_MAX, label: LEVEL_MAX }]}
          aria-label={t('입장 조건 레벨')}
          sx={{ mx: 1, width: 'auto' }}
        />
      </Stack>

      {error && <Alert severity="error">{t(error)}</Alert>}

      <Button
        type="submit"
        variant="contained"
        size="large"
        startIcon={<StarIcon sx={{ color: '#fdd835' }} />}
        disabled={trimmed.length < 2 || !enough}
        loading={busy}
      >
        {t('만들기 · 별 {n}', { n: CLUB_PRICE })}
      </Button>
      {!enough && (
        <Typography variant="caption" color="text.secondary" textAlign="center">
          {t('별이 부족합니다.')}
        </Typography>
      )}
    </Stack>
  );
}

// 친구 아래 클럽 버튼으로 여는 화면. 클럽 · 클럽 찾기 · 클럽 만들기 세 탭
// 만들면 그 클럽에 바로 들어가고 클럽 찾기로, 다른 클럽에 들어가면 클럽 탭으로 넘어간다
export default function ClubDialog({ open, uid, stars, onClose, onChanged }) {
  const [tab, setTab] = useState('CLUB');
  // undefined = 읽는 중, null = 소속 없음
  const [club, setClub] = useState(undefined);
  const [clubs, setClubs] = useState(null);
  const [busy, setBusy] = useState('');
  const [error, setError] = useState('');

  const load = useCallback(async () => {
    try {
      const [mine, all] = await Promise.all([myClub(), listClubs()]);
      setClub(mine);
      setClubs(all);
      setError('');
    } catch (e) {
      setError(e.message);
    }
  }, []);

  useEffect(() => {
    if (!open) return;
    setTab('CLUB');
    load();
  }, [open, load]);

  async function join(c) {
    setBusy(`join:${c.id}`);
    setError('');
    try {
      await joinClub(c.id);
      await load();
      setTab('CLUB');
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy('');
    }
  }

  function created() {
    onChanged?.();
    load();
    setTab('FIND');
  }

  return (
    <Dialog open={open} onClose={onClose} fullScreen>
      <Box sx={{ maxWidth: 480, width: '100%', mx: 'auto', px: 2, py: 2 }}>
        <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 1 }}>
          <IconButton onClick={onClose} aria-label={t('뒤로')}>
            <ArrowBackIcon />
          </IconButton>
          <Typography variant="h6" sx={{ flex: 1 }}>{t('클럽')}</Typography>
        </Stack>

        <Tabs value={tab} onChange={(_, v) => setTab(v)} variant="fullWidth" sx={{ mb: 2 }}>
          <Tab value="CLUB" label={t('클럽')} />
          <Tab value="FIND" label={t('클럽 찾기')} />
          <Tab value="CREATE" label={t('클럽 만들기')} />
        </Tabs>

        {error && <Alert severity="error" sx={{ mb: 2 }}>{t(error)}</Alert>}

        {tab === 'CLUB' && <ClubTab club={club} uid={uid} />}
        {tab === 'FIND' && <FindTab clubs={clubs} busy={busy} onJoin={join} />}
        {tab === 'CREATE' && <CreateTab stars={stars} onCreated={created} />}
      </Box>
    </Dialog>
  );
}
