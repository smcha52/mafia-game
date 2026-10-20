import { useCallback, useEffect, useState } from 'react';
import Alert from '@mui/material/Alert';
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Chip from '@mui/material/Chip';
import CircularProgress from '@mui/material/CircularProgress';
import Dialog from '@mui/material/Dialog';
import IconButton from '@mui/material/IconButton';
import LinearProgress from '@mui/material/LinearProgress';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import Tab from '@mui/material/Tab';
import Tabs from '@mui/material/Tabs';
import Typography from '@mui/material/Typography';
import ArrowBackIcon from '@mui/icons-material/ArrowBack';
import DiamondIcon from '@mui/icons-material/Diamond';
import MonetizationOnIcon from '@mui/icons-material/MonetizationOn';
import StarIcon from '@mui/icons-material/Star';

import { Wallet } from './AccountBar';
import { claimQuest, myQuests } from '../lib/api';
import { roleInfo } from '../lib/roles';
import { localized, t } from '../lib/i18n';

const TABS = localized([
  { key: 'MAIN', label: '메인' },
  { key: 'DAILY', label: '일간' },
  { key: 'WEEKLY', label: '주간' },
  { key: 'MONTHLY', label: '월간' },
  { key: 'YEARLY', label: '연간' },
  { key: 'ROLE', label: '직업미션' },
]);

// 퀘스트 이름 (0047 quest_pool, 0049 role_quest_pool)
const KIND_TEXT = {
  WIN: (n) => t('{n}승 하기', { n }),
  STREAK: (n) => t('{n}연승 하기', { n }),
  KILL: (n) => t('{n}킬 하기', { n }),
  SURVIVE: (n) => t('총 {n}일 생존하기', { n }),
  PLAY: (n) => t('{n}판 하기', { n }),
  CLEAR: (n) => t('퀘스트 {n}개 깨기', { n }),
  FIND_MAFIA: (n) => t('마피아 조사 {n}회', { n }),
  INVESTIGATE: (n) => t('조사 {n}회', { n }),
  HEAL: (n) => t('치료로 살리기 {n}회', { n }),
  GUARD: (n) => t('공격받은 사람 보호 {n}회', { n }),
  REPORT: (n) => t('보도 {n}회', { n }),
  REPORT_MAFIA: (n) => t('마피아 보도 {n}회', { n }),
  SEANCE: (n) => t('죽은 사람 직업 확인 {n}회', { n }),
  DIE: (n) => t('{n}번 죽기', { n }),
  KILL_MAFIA: (n) => t('마피아 {n}킬', { n }),
  KILL_NEUTRAL: (n) => t('중립 {n}킬', { n }),
  IDENTIFY: (n) => t('직업 확인 {n}회', { n }),
  FORGE: (n) => t('위조 {n}회', { n }),
  FORGE_HIT: (n) => t('위조한 사람이 조사당하기 {n}회', { n }),
  VOTES: (n) => t('총 {n}표 받기', { n }),
  DUEL: (n) => t('1대1 상황 {n}회', { n }),
};

// 직업에 따라 이름이 달라지는 퀘스트
const ROLE_KIND_TEXT = {
  ASSASSIN: { KILL: (n) => t('저격 {n}킬', { n }) },
};

function questText(q) {
  const text = ROLE_KIND_TEXT[q.role]?.[q.kind] ?? KIND_TEXT[q.kind];
  return text?.(q.target) ?? q.kind;
}

// 직업미션 탭에서 고르는 직업. 진영별로 묶는다 (0049 quest_roles)
const ROLE_GROUPS = localized([
  { title: '시민 진영', roles: ['CITIZEN', 'POLICE', 'DOCTOR', 'BODYGUARD', 'DETECTIVE', 'REPORTER', 'MEDIUM', 'VIGILANTE', 'SHERIFF'] },
  { title: '마피아 진영', roles: ['MAFIA', 'SPY', 'ASSASSIN', 'FORGER'] },
  { title: '중립 진영', roles: ['JESTER', 'KILLER', 'SURVIVOR'] },
]);

const DIFFICULTY = localized({
  EASY: { label: '쉬움', color: 'success' },
  NORMAL: { label: '보통', color: 'warning' },
  HARD: { label: '어려움', color: 'error' },
});

export const REWARD = localized({
  STAR: { label: '별', icon: <StarIcon fontSize="small" sx={{ color: '#f5b301' }} /> },
  GEM: { label: '보석', icon: <DiamondIcon fontSize="small" sx={{ color: '#29b6f6' }} /> },
  COIN: { label: '코인', icon: <MonetizationOnIcon fontSize="small" sx={{ color: '#ffa000' }} /> },
});

// 다음 퀘스트까지 남은 시간
export function untilText(iso) {
  const ms = new Date(iso).getTime() - Date.now();
  if (!(ms > 0)) return t('곧');
  const min = Math.ceil(ms / 60000);
  const d = Math.floor(min / 1440);
  const h = Math.floor((min % 1440) / 60);
  const m = min % 60;
  if (d) return t('{d}일 {h}시간', { d, h });
  if (h) return t('{h}시간 {m}분', { h, m });
  return t('{m}분', { m });
}

function QuestCard({ q, busy, onClaim }) {
  const done = q.progress >= q.target;
  const reward = REWARD[q.rewardType];
  const difficulty = DIFFICULTY[q.difficulty];
  return (
    <Paper sx={{ p: 2 }}>
      <Stack direction="row" alignItems="center" justifyContent="space-between" spacing={1}>
        <Stack spacing={0.75} sx={{ minWidth: 0, flex: 1 }}>
          <Stack direction="row" alignItems="center" spacing={0.75}>
            <Typography fontWeight={700}>{questText(q)}</Typography>
            {difficulty && (
              <Chip label={difficulty.label} color={difficulty.color} size="small" variant="outlined" />
            )}
          </Stack>
          <Stack direction="row" alignItems="center" spacing={1}>
            <LinearProgress
              variant="determinate"
              value={(q.progress / q.target) * 100}
              sx={{ flex: 1, height: 6, borderRadius: 3 }}
              aria-label={t('진행도')}
            />
            <Typography variant="caption" color="text.secondary" sx={{ fontVariantNumeric: 'tabular-nums' }}>
              {q.progress} / {q.target}
            </Typography>
          </Stack>
          <Stack direction="row" alignItems="center" spacing={0.5}>
            {reward.icon}
            <Typography variant="body2">
              {reward.label} {q.rewardAmount.toLocaleString()}
            </Typography>
          </Stack>
        </Stack>
        {q.claimed ? (
          <Chip label={t('완료')} size="small" />
        ) : (
          <Button
            variant="contained"
            size="small"
            disabled={!done}
            loading={busy}
            onClick={() => onClaim(q)}
            sx={{ flexShrink: 0 }}
          >
            {t('받기')}
          </Button>
        )}
      </Stack>
    </Paper>
  );
}

// 로그아웃 아래 퀘스트 버튼으로 여는 화면. 보상을 받으면 onRewarded 로 재화를 다시 읽게 한다
// wallet = 내 재화 { stars, gems, coins } — 오른쪽 위에 보여준다
export default function QuestDialog({ open, onClose, onRewarded, wallet }) {
  const [tab, setTab] = useState('MAIN');
  // 직업미션 탭에서 보고 있는 직업
  const [role, setRole] = useState('CITIZEN');
  const [data, setData] = useState(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(null);

  const load = useCallback(async () => {
    setError('');
    try {
      setData(await myQuests());
    } catch (e) {
      setError(e.message);
    }
  }, []);

  useEffect(() => {
    if (open) load();
  }, [open, load]);

  async function claim(q) {
    setBusy(q.id);
    setError('');
    try {
      await claimQuest(q.id);
      await load();
      onRewarded?.();
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(null);
    }
  }

  const list = data?.quests.filter(
    (q) => q.category === tab && (tab !== 'ROLE' || q.role === role),
  ) ?? [];

  return (
    <Dialog open={open} onClose={onClose} fullScreen>
      <Box sx={{ maxWidth: 480, width: '100%', mx: 'auto', px: 2, py: 2 }}>
        <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 1 }}>
          <IconButton onClick={onClose} aria-label={t('뒤로')}>
            <ArrowBackIcon />
          </IconButton>
          <Typography variant="h6" sx={{ flex: 1 }}>{t('퀘스트')}</Typography>
          <Wallet {...wallet} />
        </Stack>

        <Tabs
          value={tab}
          onChange={(_, v) => setTab(v)}
          variant="scrollable"
          scrollButtons="auto"
          allowScrollButtonsMobile
          sx={{ mb: 2 }}
        >
          {TABS.map((item) => (
            <Tab key={item.key} value={item.key} label={item.label} sx={{ minWidth: 64 }} />
          ))}
        </Tabs>

        {error && <Alert severity="error" sx={{ mb: 2 }}>{t(error)}</Alert>}

        {tab === 'ROLE' && (
          <Stack spacing={1} sx={{ mb: 2 }}>
            {ROLE_GROUPS.map((group) => (
              <Box key={group.title}>
                <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mb: 0.5 }}>
                  {group.title}
                </Typography>
                <Stack direction="row" sx={{ flexWrap: 'wrap', gap: 0.75 }}>
                  {group.roles.map((r) => (
                    <Chip
                      key={r}
                      label={`${roleInfo(r).emoji} ${roleInfo(r).name}`}
                      color={r === role ? 'primary' : 'default'}
                      variant={r === role ? 'filled' : 'outlined'}
                      onClick={() => setRole(r)}
                    />
                  ))}
                </Stack>
              </Box>
            ))}
          </Stack>
        )}

        {!data ? (
          !error && (
            <Stack alignItems="center" sx={{ py: 6 }}>
              <CircularProgress />
            </Stack>
          )
        ) : (
          <Stack spacing={1}>
            <Typography variant="caption" color="text.secondary">
              {tab === 'ROLE'
                ? t('다음 퀘스트까지 {time} · 직업마다 최대 10개이고, 넘으면 오래된 퀘스트부터 사라집니다. 퀘스트가 생긴 뒤에 {role}(으)로 끝낸 게임만 셉니다.', { time: untilText(data.next?.[tab]), role: roleInfo(role).name })
                : t('다음 퀘스트까지 {time} · 최대 20개이고, 넘으면 오래된 퀘스트부터 사라집니다. 퀘스트가 생긴 뒤에 끝난 게임만 셉니다.', { time: untilText(data.next?.[tab]) })}
            </Typography>
            {list.length === 0 ? (
              <Paper sx={{ p: 4, textAlign: 'center' }}>
                <Typography color="text.secondary">{t('퀘스트가 없습니다.')}</Typography>
              </Paper>
            ) : (
              list.map((q) => (
                <QuestCard key={q.id} q={q} busy={busy === q.id} onClaim={claim} />
              ))
            )}
          </Stack>
        )}
      </Box>
    </Dialog>
  );
}
