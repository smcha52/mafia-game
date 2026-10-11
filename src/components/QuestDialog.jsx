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

import { claimQuest, myQuests } from '../lib/api';

const TABS = [
  { key: 'MAIN', label: '메인' },
  { key: 'DAILY', label: '일간' },
  { key: 'WEEKLY', label: '주간' },
  { key: 'MONTHLY', label: '월간' },
  { key: 'YEARLY', label: '연간' },
  { key: 'ROLE', label: '직업미션' },
];

// 퀘스트 이름 (0047 quest_pool)
const KIND_TEXT = {
  WIN: (n) => `${n}승 하기`,
  STREAK: (n) => `${n}연승 하기`,
  KILL: (n) => `${n}킬 하기`,
  SURVIVE: (n) => `총 ${n}일 생존하기`,
  PLAY: (n) => `${n}판 하기`,
  CLEAR: (n) => `퀘스트 ${n}개 깨기`,
};

const REWARD = {
  STAR: { label: '별', icon: <StarIcon fontSize="small" sx={{ color: '#f5b301' }} /> },
  GEM: { label: '보석', icon: <DiamondIcon fontSize="small" sx={{ color: '#29b6f6' }} /> },
  COIN: { label: '코인', icon: <MonetizationOnIcon fontSize="small" sx={{ color: '#ffa000' }} /> },
};

// 다음 퀘스트까지 남은 시간
function untilText(iso) {
  const ms = new Date(iso).getTime() - Date.now();
  if (!(ms > 0)) return '곧';
  const min = Math.ceil(ms / 60000);
  const d = Math.floor(min / 1440);
  const h = Math.floor((min % 1440) / 60);
  const m = min % 60;
  if (d) return `${d}일 ${h}시간`;
  if (h) return `${h}시간 ${m}분`;
  return `${m}분`;
}

function QuestCard({ q, busy, onClaim }) {
  const done = q.progress >= q.target;
  const reward = REWARD[q.rewardType];
  return (
    <Paper sx={{ p: 2 }}>
      <Stack direction="row" alignItems="center" justifyContent="space-between" spacing={1}>
        <Stack spacing={0.75} sx={{ minWidth: 0, flex: 1 }}>
          <Typography fontWeight={700}>{KIND_TEXT[q.kind]?.(q.target) ?? q.kind}</Typography>
          <Stack direction="row" alignItems="center" spacing={1}>
            <LinearProgress
              variant="determinate"
              value={(q.progress / q.target) * 100}
              sx={{ flex: 1, height: 6, borderRadius: 3 }}
              aria-label="진행도"
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
          <Chip label="완료" size="small" />
        ) : (
          <Button
            variant="contained"
            size="small"
            disabled={!done}
            loading={busy}
            onClick={() => onClaim(q)}
            sx={{ flexShrink: 0 }}
          >
            받기
          </Button>
        )}
      </Stack>
    </Paper>
  );
}

// 로그아웃 아래 퀘스트 버튼으로 여는 화면. 보상을 받으면 onRewarded 로 재화를 다시 읽게 한다
export default function QuestDialog({ open, onClose, onRewarded }) {
  const [tab, setTab] = useState('MAIN');
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

  const list = data?.quests.filter((q) => q.category === tab) ?? [];

  return (
    <Dialog open={open} onClose={onClose} fullScreen>
      <Box sx={{ maxWidth: 480, width: '100%', mx: 'auto', px: 2, py: 2 }}>
        <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 1 }}>
          <IconButton onClick={onClose} aria-label="뒤로">
            <ArrowBackIcon />
          </IconButton>
          <Typography variant="h6">퀘스트</Typography>
        </Stack>

        <Tabs
          value={tab}
          onChange={(_, v) => setTab(v)}
          variant="scrollable"
          scrollButtons="auto"
          allowScrollButtonsMobile
          sx={{ mb: 2 }}
        >
          {TABS.map((t) => (
            <Tab key={t.key} value={t.key} label={t.label} sx={{ minWidth: 64 }} />
          ))}
        </Tabs>

        {error && <Alert severity="error" sx={{ mb: 2 }}>{error}</Alert>}

        {tab === 'ROLE' ? (
          <Paper sx={{ p: 4, textAlign: 'center' }}>
            <Typography color="text.secondary">직업 미션은 준비 중입니다.</Typography>
          </Paper>
        ) : !data ? (
          !error && (
            <Stack alignItems="center" sx={{ py: 6 }}>
              <CircularProgress />
            </Stack>
          )
        ) : (
          <Stack spacing={1}>
            <Typography variant="caption" color="text.secondary">
              다음 퀘스트까지 {untilText(data.next?.[tab])} · 최대 20개이고, 넘으면 오래된 퀘스트부터 사라집니다.
              퀘스트가 생긴 뒤에 끝난 게임만 셉니다.
            </Typography>
            {list.length === 0 ? (
              <Paper sx={{ p: 4, textAlign: 'center' }}>
                <Typography color="text.secondary">퀘스트가 없습니다.</Typography>
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
