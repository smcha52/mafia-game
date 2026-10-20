import { useCallback, useEffect, useState } from 'react';
import Alert from '@mui/material/Alert';
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import CircularProgress from '@mui/material/CircularProgress';
import Dialog from '@mui/material/Dialog';
import IconButton from '@mui/material/IconButton';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import Typography from '@mui/material/Typography';
import ArrowBackIcon from '@mui/icons-material/ArrowBack';
import CheckCircleIcon from '@mui/icons-material/CheckCircle';

import { Wallet } from './AccountBar';
import BoxArt from './BoxArt';
import { OpenDialog } from './DailyRewards';
import { REWARD, untilText } from './QuestDialog';
import { claimAttendance, myAttendance } from '../lib/api';
import { t } from '../lib/i18n';

// 하루 칸 — 날짜, 보상, 받았으면 체크. 오늘은 테두리로, 지나간 날은 흐리게 보여준다
// 상자는 상자 그림으로 보여준다 (0059)
// 연속 출석 화면에서도 쓴다
export function DayCell({ d, today }) {
  const isToday = d.day === today;
  return (
    <Paper
      sx={{
        p: 1,
        minHeight: 84,
        textAlign: 'center',
        border: 2,
        borderColor: isToday ? 'primary.main' : 'transparent',
        opacity: d.day < today ? 0.5 : 1,
      }}
      aria-current={isToday ? 'date' : undefined}
    >
      <Typography variant="caption" color={isToday ? 'primary' : 'text.secondary'} fontWeight={700}>
        {t('{n}일', { n: d.day })}
      </Typography>
      <Stack alignItems="center" spacing={0.25} sx={{ mt: 0.5 }}>
        {d.claimed ? (
          <CheckCircleIcon color="success" aria-label={t('받음')} />
        ) : d.rewards.length === 0 ? (
          <Typography variant="caption" color="text.secondary">{t('준비 중')}</Typography>
        ) : (
          d.rewards.map((r) => r.type === 'BOX' ? (
            <BoxArt key={r.type} box={r.box} size={28} />
          ) : (
            <Stack
              key={r.type}
              direction="row"
              alignItems="center"
              spacing={0.25}
              aria-label={t('{label} {n}개', { label: REWARD[r.type].label, n: r.amount })}
            >
              {REWARD[r.type].icon}
              <Typography variant="body2" fontWeight={700}>{r.amount}</Typography>
            </Stack>
          ))
        )}
      </Stack>
    </Paper>
  );
}

// 장착 아래 출석 버튼으로 여는 화면. 보상을 받으면 onRewarded 로 재화를 다시 읽게 한다
// wallet = 내 재화 { stars, gems, coins } — 오른쪽 위에 보여준다
export default function AttendanceDialog({ open, onClose, onRewarded, wallet }) {
  const [data, setData] = useState(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  // 출석하며 연 상자 { box, result }
  const [opening, setOpening] = useState(null);

  const load = useCallback(async () => {
    setError('');
    try {
      setData(await myAttendance());
    } catch (e) {
      setError(e.message);
    }
  }, []);

  useEffect(() => {
    if (open) load();
  }, [open, load]);

  async function claim() {
    setBusy(true);
    setError('');
    try {
      const res = await claimAttendance();
      const opened = res?.boxes?.[0];
      if (opened) setOpening({ box: opened.box, result: opened });
      await load();
      onRewarded?.();
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }

  const todayCell = data?.days.find((d) => d.day === data.day);

  return (
    <Dialog open={open} onClose={onClose} fullScreen>
      <Box sx={{ maxWidth: 480, width: '100%', mx: 'auto', px: 2, py: 2 }}>
        <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 2 }}>
          <IconButton onClick={onClose} aria-label={t('뒤로')}>
            <ArrowBackIcon />
          </IconButton>
          <Typography variant="h6" sx={{ flex: 1 }}>{t('출석')}</Typography>
          <Wallet {...wallet} />
        </Stack>

        {error && <Alert severity="error" sx={{ mb: 2 }}>{t(error)}</Alert>}

        {!data ? (
          !error && (
            <Stack alignItems="center" sx={{ py: 6 }}>
              <CircularProgress />
            </Stack>
          )
        ) : (
          <Stack spacing={1.5}>
            <Typography variant="caption" color="text.secondary">
              {data.checked ? t('다음 출석까지 {time}', { time: untilText(data.next) }) : t('오늘은 {n}일차', { n: data.day })}
              {' '}· {t('하루에 한 번 출석할 때마다 다음 날 보상을 받습니다. 빠진 날이 있어도 이어서 받고, 30일을 다 받으면 1일부터 다시 시작합니다.')}
            </Typography>
            <Box sx={{ display: 'grid', gridTemplateColumns: 'repeat(5, 1fr)', gap: 1 }}>
              {data.days.map((d) => (
                <DayCell key={d.day} d={d} today={data.day} />
              ))}
            </Box>
            <Button
              variant="contained"
              size="large"
              disabled={data.checked}
              loading={busy}
              onClick={claim}
            >
              {data.checked
                ? t('오늘 출석 완료')
                : todayCell.rewards.length === 0
                  ? t('{n}일차 출석하기 (보상 없음)', { n: data.day })
                  : t('{n}일차 보상 받기', { n: data.day })}
            </Button>
          </Stack>
        )}
      </Box>
      <OpenDialog opening={opening} onClose={() => setOpening(null)} />
    </Dialog>
  );
}
