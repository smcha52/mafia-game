import { useCallback, useEffect, useRef, useState } from 'react';
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
import Slider from '@mui/material/Slider';
import Stack from '@mui/material/Stack';
import Tab from '@mui/material/Tab';
import Tabs from '@mui/material/Tabs';
import TextField from '@mui/material/TextField';
import ToggleButton from '@mui/material/ToggleButton';
import ToggleButtonGroup from '@mui/material/ToggleButtonGroup';
import Tooltip from '@mui/material/Tooltip';
import Typography from '@mui/material/Typography';
import ArrowBackIcon from '@mui/icons-material/ArrowBack';
import LogoutIcon from '@mui/icons-material/Logout';
import SendIcon from '@mui/icons-material/Send';
import StarIcon from '@mui/icons-material/Star';
import WorkspacePremiumIcon from '@mui/icons-material/WorkspacePremium';

import ProfileAvatar from './ProfileAvatar';
import {
  createClub, demoteClubMember, fetchClubChat, joinClub, kickClubMember, leaveClub, listClubs, myClub,
  promoteClubMember, sendClubChat,
} from '../lib/api';
import { supabase } from '../lib/supabase';
import { t } from '../lib/i18n';

// 클럽 만드는 값 (별). 서버 club_price() 와 같다
const CLUB_PRICE = 100;
const LEVEL_MIN = 1;
const LEVEL_MAX = 50;
// 실시간 알림을 놓쳐도 채팅 · 회원을 다시 읽는 간격
const CHAT_POLL_MS = 10000;

// 입장 조건 글자. GTE = 이상, LTE = 이하
function conditionLabel(club) {
  return t(club.levelMode === 'GTE' ? '레벨 {n} 이상' : '레벨 {n} 이하', { n: club.level });
}

// 계급 이름과 색. 서버 rank = LEADER · VICE · MEMBER
const RANKS = {
  LEADER: { label: '대장', color: 'warning', variant: 'filled' },
  VICE: { label: '부대장', color: 'info', variant: 'filled' },
  MEMBER: { label: '멤버', color: 'default', variant: 'outlined' },
};

// 계급 표시. 처음 만든 사람은 왕관을 더 붙인다
function RankBadge({ rank, owner = false }) {
  const r = RANKS[rank];
  if (!r) return null;
  return (
    <Stack direction="row" alignItems="center" spacing={0.25} sx={{ flexShrink: 0 }}>
      <Chip
        size="small"
        color={r.color}
        variant={r.variant}
        label={t(r.label)}
        sx={{ height: 20, '& .MuiChip-label': { px: 0.75, fontSize: 11 } }}
      />
      {owner && (
        <Tooltip title={t('처음 만든 사람')}>
          <WorkspacePremiumIcon fontSize="small" sx={{ color: '#ffa000' }} aria-label={t('처음 만든 사람')} />
        </Tooltip>
      )}
    </Stack>
  );
}

// 승급·강등 소식 글자. 계급이 바뀐 길마다 문장이 다르다
const RANK_CHANGE = {
  'MEMBER>VICE': '{name}님이 멤버에서 부대장으로 승급했습니다',
  'VICE>LEADER': '{name}님이 부대장에서 대장으로 승급했습니다',
  'LEADER>VICE': '{name}님이 대장에서 부대장으로 강등했습니다',
  'VICE>MEMBER': '{name}님이 부대장에서 멤버로 강등했습니다',
};

// 클럽 소식 한 줄 (채팅이 아닌 것)
function eventText(m) {
  const name = m.sender_nickname;
  switch (m.kind) {
    case 'CREATE': return t('{name}님이 클럽을 만들었습니다', { name });
    case 'JOIN': return t('{name}님이 들어왔습니다', { name });
    case 'LEAVE': return t('{name}님이 나갔습니다', { name });
    case 'OWNER': return t('{name}님이 처음 만든 사람을 이어받아 대장이 되었습니다', { name });
    case 'KICK': return t('{name}님이 {by}님에 의하여 추방당했습니다', { name: m.target_nickname, by: name });
    case 'PROMOTE':
    case 'DEMOTE': {
      const key = RANK_CHANGE[`${m.from_rank}>${m.to_rank}`];
      return key ? t(key, { name: m.target_nickname }) : '';
    }
    default: return '';
  }
}

// 추방이 풀리기까지 남은 시간
function banLeft(iso) {
  const min = Math.max(1, Math.ceil((new Date(iso).getTime() - Date.now()) / 60000));
  const d = Math.floor(min / 1440);
  const h = Math.floor((min % 1440) / 60);
  if (d) return t('{d}일 {h}시간 남음', { d, h });
  if (h) return t('{h}시간 {m}분 남음', { h, m: min % 60 });
  return t('{m}분 남음', { m: min });
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

// 클럽 채팅과 클럽 소식. 새 메시지 알림이 오면 다시 읽는다 (RLS 가 내 클럽 것만 준다)
// 소식이 오면 계급·회원이 바뀌었을 수 있어 onActivity 로 클럽도 다시 읽게 한다
// ranks = { uid: { rank, owner } } — 보낸 사람 옆에 지금 계급을 보여준다
function ClubChat({ clubId, uid, ranks, onActivity }) {
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
        (payload) => {
          reload();
          if (payload.new?.kind !== 'CHAT') onActivity?.();
        },
      )
      .subscribe();
    const poll = setInterval(reload, CHAT_POLL_MS);
    return () => {
      clearInterval(poll);
      supabase.removeChannel(channel);
    };
  }, [clubId, reload, onActivity]);

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
            {messages.map((m) => (m.kind && m.kind !== 'CHAT' ? (
              <Typography
                key={m.id}
                variant="caption"
                color="text.secondary"
                sx={{ display: 'block', textAlign: 'center', py: 0.25 }}
              >
                {eventText(m)}
              </Typography>
            ) : (
              <Box key={m.id}>
                <Stack direction="row" alignItems="center" spacing={0.5}>
                  <Typography
                    variant="caption"
                    sx={{ color: m.sender_uid === uid ? 'primary.main' : 'text.secondary', fontWeight: 700 }}
                  >
                    {m.sender_nickname}
                  </Typography>
                  {ranks[m.sender_uid] && (
                    <RankBadge rank={ranks[m.sender_uid].rank} owner={ranks[m.sender_uid].owner} />
                  )}
                </Stack>
                <Typography variant="body2" sx={{ wordBreak: 'break-word' }}>{m.body}</Typography>
              </Box>
            )))}
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

// 클럽 회원 한 명. 내 계급에 따라 승급 · 강등 · 추방 버튼이 붙는다
//   대장   — 대장이 아닌 사람 승급, 멤버가 아닌 사람 강등 (처음 만든 사람 빼고), 멤버 추방
//   부대장 — 멤버 추방
function MemberRow({ p, me, myRank, busy, onPromote, onDemote, onKick }) {
  const isMe = p.uid === me;
  const leader = myRank === 'LEADER';
  const canPromote = !isMe && leader && p.rank !== 'LEADER';
  const canDemote = !isMe && leader && p.rank !== 'MEMBER' && !p.owner;
  const canKick = !isMe && (leader || myRank === 'VICE') && p.rank === 'MEMBER' && !p.owner;
  const disabled = busy !== '';

  return (
    <Stack direction="row" alignItems="center" spacing={1.25} sx={{ py: 0.75 }}>
      <ProfileAvatar avatar={p.avatar} nickname={p.nickname} size={36} />
      <Stack spacing={0.25} sx={{ minWidth: 0, flex: 1 }}>
        <Stack direction="row" alignItems="center" spacing={0.5} sx={{ minWidth: 0 }}>
          <Typography fontWeight={700} noWrap sx={{ color: isMe ? 'primary.main' : undefined }}>
            {p.nickname}
          </Typography>
          <RankBadge rank={p.rank} owner={p.owner} />
        </Stack>
        <Typography variant="caption" color="text.secondary">Lv.{p.level}</Typography>
      </Stack>
      {(canPromote || canDemote || canKick) && (
        <Stack direction="row" spacing={0.5} sx={{ flexShrink: 0 }}>
          {canPromote && (
            <Button size="small" variant="outlined" disabled={disabled}
              loading={busy === `promote:${p.uid}`} onClick={() => onPromote(p)}>
              {t('승급')}
            </Button>
          )}
          {canDemote && (
            <Button size="small" variant="outlined" color="inherit" disabled={disabled}
              loading={busy === `demote:${p.uid}`} onClick={() => onDemote(p)}>
              {t('강등')}
            </Button>
          )}
          {canKick && (
            <Button size="small" variant="outlined" color="error" disabled={disabled} onClick={() => onKick(p)}>
              {t('추방')}
            </Button>
          )}
        </Stack>
      )}
    </Stack>
  );
}

// 클럽 탭 — 들어간 클럽의 이름, 회원과 계급, 채팅, 나가기. 없으면 안내만
function ClubTab({ club, uid, onChanged }) {
  const [busy, setBusy] = useState('');
  const [error, setError] = useState('');
  // 추방할지 묻고 있는 회원 · 나갈지 묻는 중인지
  const [kicking, setKicking] = useState(null);
  const [leaving, setLeaving] = useState(false);

  async function run(kind, fn) {
    setBusy(kind);
    setError('');
    try {
      await fn();
      await onChanged();
      return true;
    } catch (e) {
      setError(e.message);
      return false;
    } finally {
      setBusy('');
    }
  }

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
  const ranks = Object.fromEntries(club.people.map((p) => [p.uid, p]));

  return (
    <Stack spacing={2}>
      <Stack direction="row" alignItems="flex-start" spacing={1}>
        <Stack spacing={0.5} sx={{ minWidth: 0, flex: 1 }}>
          <Typography variant="h5" fontWeight={700} sx={{ wordBreak: 'break-word' }}>{club.name}</Typography>
          <ClubInfo club={club} />
        </Stack>
        <Button
          size="small"
          color="inherit"
          variant="outlined"
          startIcon={<LogoutIcon />}
          disabled={busy !== ''}
          onClick={() => setLeaving(true)}
          sx={{ flexShrink: 0 }}
        >
          {t('클럽 나가기')}
        </Button>
      </Stack>

      {error && <Alert severity="error">{t(error)}</Alert>}

      <ClubChat clubId={club.id} uid={uid} ranks={ranks} onActivity={onChanged} />

      <Paper sx={{ px: 2, py: 1 }}>
        <Typography variant="subtitle2" color="text.secondary" sx={{ py: 0.5 }}>
          {t('회원 {n}/{max}명', { n: club.members, max: club.maxMembers })}
        </Typography>
        {club.people.map((p) => (
          <MemberRow
            key={p.uid}
            p={p}
            me={uid}
            myRank={club.myRank}
            busy={busy}
            onPromote={(x) => run(`promote:${x.uid}`, () => promoteClubMember(x.uid))}
            onDemote={(x) => run(`demote:${x.uid}`, () => demoteClubMember(x.uid))}
            onKick={setKicking}
          />
        ))}
      </Paper>

      <Dialog open={kicking !== null} onClose={busy ? undefined : () => setKicking(null)} maxWidth="xs" fullWidth>
        <DialogContent>
          <Typography>
            {t('{name}님을 추방할까요? 7일 동안 이 클럽에 다시 들어올 수 없습니다.', {
              name: <strong>{kicking?.nickname}</strong>,
            })}
          </Typography>
        </DialogContent>
        <DialogActions>
          <Button color="inherit" disabled={busy !== ''} onClick={() => setKicking(null)}>{t('취소')}</Button>
          <Button
            color="error"
            variant="contained"
            loading={busy === 'kick'}
            onClick={() => run('kick', () => kickClubMember(kicking.uid)).then(() => setKicking(null))}
          >
            {t('추방')}
          </Button>
        </DialogActions>
      </Dialog>

      <Dialog open={leaving} onClose={busy ? undefined : () => setLeaving(false)} maxWidth="xs" fullWidth>
        <DialogContent>
          <Typography>{t('{name} 클럽에서 나갈까요?', { name: <strong>{club.name}</strong> })}</Typography>
          {club.isOwner && club.members > 1 && (
            <Typography variant="body2" color="text.secondary" sx={{ mt: 1 }}>
              {t('처음 만든 사람이 나가면 다음으로 먼저 들어온 사람이 이어받아 대장이 됩니다.')}
            </Typography>
          )}
        </DialogContent>
        <DialogActions>
          <Button color="inherit" disabled={busy !== ''} onClick={() => setLeaving(false)}>{t('취소')}</Button>
          <Button
            color="error"
            variant="contained"
            loading={busy === 'leave'}
            onClick={() => run('leave', leaveClub).then(() => setLeaving(false))}
          >
            {t('나가기')}
          </Button>
        </DialogActions>
      </Dialog>
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
              {c.bannedUntil && (
                <Typography variant="caption" color="error">
                  {t('추방당해 들어갈 수 없음 · {left}', { left: banLeft(c.bannedUntil) })}
                </Typography>
              )}
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

  // 열려 있는 동안 회원 · 계급을 새로 읽는다. 추방당하면 소식이 오지 않아 이것으로 알게 된다
  useEffect(() => {
    if (!open) return undefined;
    setTab('CLUB');
    load();
    const timer = setInterval(load, CHAT_POLL_MS);
    return () => clearInterval(timer);
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

        {tab === 'CLUB' && <ClubTab club={club} uid={uid} onChanged={load} />}
        {tab === 'FIND' && <FindTab clubs={clubs} busy={busy} onJoin={join} />}
        {tab === 'CREATE' && <CreateTab stars={stars} onCreated={created} />}
      </Box>
    </Dialog>
  );
}
