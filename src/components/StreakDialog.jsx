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
import LocalFireDepartmentIcon from '@mui/icons-material/LocalFireDepartment';

import { Wallet } from './AccountBar';
import { DayCell } from './AttendanceDialog';
import { untilText } from './QuestDialog';
import { claimStreak, myStreak } from '../lib/api';

// 출석 아래 연속 출석 버튼으로 여는 화면. 하루에 한 번 출석하고, 하루라도 빠지면 0일로 돌아간다
// 보상은 출석과 같은 30일 표를 쓰고, 연속 일수만큼 칸이 채워진다
// 보상을 받으면 onRewarded 로 재화를 다시 읽게 한다
// wallet = 내 재화 { stars, gems, coins } — 오른쪽 위에 보여준다
export default function StreakDialog({ open, onClose, onRewarded, wallet }) {
  const [data, setData] = useState(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setError('');
    try {
      setData(await myStreak());
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
      await claimStreak();
      await load();
      onRewarded?.();
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open={open} onClose={onClose} fullScreen>
      <Box sx={{ maxWidth: 480, width: '100%', mx: 'auto', px: 2, py: 2 }}>
        <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 2 }}>
          <IconButton onClick={onClose} aria-label="뒤로">
            <ArrowBackIcon />
          </IconButton>
          <Typography variant="h6" sx={{ flex: 1 }}>연속 출석</Typography>
          <Wallet {...wallet} />
        </Stack>

        {error && <Alert severity="error" sx={{ mb: 2 }}>{error}</Alert>}

        {!data ? (
          !error && (
            <Stack alignItems="center" sx={{ py: 6 }}>
              <CircularProgress />
            </Stack>
          )
        ) : (
          <Stack spacing={1.5}>
            <Paper sx={{ p: 2 }}>
              <Stack direction="row" alignItems="center" justifyContent="center" spacing={1}>
                <LocalFireDepartmentIcon
                  sx={{ fontSize: 40, color: data.streak > 0 ? '#ff6d00' : 'text.disabled' }}
                />
                <Typography variant="h4" fontWeight={700} sx={{ fontVariantNumeric: 'tabular-nums' }}>
                  {data.streak.toLocaleString()}일
                </Typography>
                <Typography color="text.secondary">연속 출석</Typography>
              </Stack>
            </Paper>
            <Typography variant="caption" color="text.secondary">
              {data.checked
                ? `다음 출석까지 ${untilText(data.next)} · 다음 날 안에 출석하지 않으면 0일로 돌아갑니다.`
                : data.streak > 0
                  ? `${untilText(data.next)} 안에 출석하지 않으면 0일로 돌아갑니다.`
                  : '하루에 한 번 출석합니다. 하루라도 빠지면 0일로 돌아갑니다.'}
              {' '}보상은 출석과 같고, 30일을 채우면 1일 보상부터 다시 받습니다.
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
              {data.checked ? '오늘 출석 완료' : '출석하기'}
            </Button>
          </Stack>
        )}
      </Box>
    </Dialog>
  );
}
