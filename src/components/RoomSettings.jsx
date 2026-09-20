import { useEffect, useState } from 'react';
import Alert from '@mui/material/Alert';
import Chip from '@mui/material/Chip';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import TextField from '@mui/material/TextField';
import Typography from '@mui/material/Typography';

import { setTimers } from '../lib/api';

// 서버 제약과 같은 범위 (0012 마이그레이션)
const SEC_MIN = 10;
const SEC_MAX = 600;
const SEC_STEP = 5;
const DAYS_MIN = 1;
const DAYS_MAX = 50;

const fmt = (sec) => {
  if (sec < 60) return `${sec}초`;
  const m = Math.floor(sec / 60);
  const s = sec % 60;
  return s ? `${m}분 ${s}초` : `${m}분`;
};

// 5초 단위로 맞추고 범위 안으로 가둔다
const snapSec = (v) => {
  const n = Math.round(Number(v) / SEC_STEP) * SEC_STEP;
  if (!Number.isFinite(n)) return SEC_MIN;
  return Math.min(SEC_MAX, Math.max(SEC_MIN, n));
};

const clampDays = (v) => {
  const n = Math.round(Number(v));
  if (!Number.isFinite(n)) return DAYS_MIN;
  return Math.min(DAYS_MAX, Math.max(DAYS_MIN, n));
};

// 대기실의 진행 설정. 방장만 바꿀 수 있고 나머지는 읽기만 한다.
export default function RoomSettings({ room, isHost }) {
  const night = room?.night_seconds ?? 30;
  const day = room?.day_seconds ?? 60;
  const maxDays = room?.max_days ?? 15;

  // 입력 중에는 로컬 값을 쓰고, 확정될 때 서버에 보낸다
  const [draft, setDraft] = useState({ night, day, maxDays });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    setDraft({ night, day, maxDays });
  }, [night, day, maxDays]);

  if (!room) return null;

  async function commit(next) {
    const value = {
      night: snapSec(next.night ?? draft.night),
      day: snapSec(next.day ?? draft.day),
      maxDays: clampDays(next.maxDays ?? draft.maxDays),
    };
    setDraft(value);

    if (value.night === night && value.day === day && value.maxDays === maxDays) return;

    setBusy(true);
    setError('');
    try {
      await setTimers(room.id, value.night, value.day, value.maxDays);
    } catch (e) {
      setError(e.message);
      setDraft({ night, day, maxDays });
    } finally {
      setBusy(false);
    }
  }

  if (!isHost) {
    return (
      <Paper sx={{ p: 2 }}>
        <Typography variant="body2" color="text.secondary" sx={{ mb: 1 }}>
          진행 설정
        </Typography>
        <Stack direction="row" spacing={0.75} flexWrap="wrap" useFlexGap>
          <Chip size="small" label={`🌙 ${fmt(night)}`} />
          <Chip size="small" label={`☀️ ${fmt(day)}`} />
          <Chip size="small" label={`최대 ${maxDays}일`} />
        </Stack>
      </Paper>
    );
  }

  const secField = (key, label) => (
    <TextField
      type="number"
      size="small"
      label={label}
      value={draft[key]}
      disabled={busy}
      onChange={(e) => setDraft((d) => ({ ...d, [key]: e.target.value }))}
      onBlur={() => commit({ [key]: draft[key] })}
      slotProps={{
        htmlInput: { min: SEC_MIN, max: SEC_MAX, step: SEC_STEP, inputMode: 'numeric' },
      }}
      helperText={fmt(snapSec(draft[key]))}
      sx={{ minWidth: 96, flex: 1 }}
    />
  );

  return (
    <Paper sx={{ p: 2 }}>
      <Typography variant="body2" color="text.secondary" sx={{ mb: 1.5 }}>
        진행 설정 — 방장만 바꿀 수 있습니다 (5초 단위)
      </Typography>

      <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap>
        {secField('night', '밤(초)')}
        {secField('day', '낮(초)')}
        <TextField
          type="number"
          size="small"
          label="최대 일수"
          value={draft.maxDays}
          disabled={busy}
          onChange={(e) => setDraft((d) => ({ ...d, maxDays: e.target.value }))}
          onBlur={() => commit({ maxDays: draft.maxDays })}
          slotProps={{
            htmlInput: { min: DAYS_MIN, max: DAYS_MAX, step: 1, inputMode: 'numeric' },
          }}
          helperText={`${clampDays(draft.maxDays)}일차까지`}
          sx={{ minWidth: 96, flex: 1 }}
        />
      </Stack>

      <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 1 }}>
        {SEC_MIN}~{SEC_MAX}초 범위이며 {SEC_STEP}초 단위로 맞춰집니다.
        시간이 지나면 미제출자는 기권 처리되고, 최대 일수까지 승부가 안 나면 무승부입니다.
      </Typography>

      {error && <Alert severity="error" sx={{ mt: 1 }}>{error}</Alert>}
    </Paper>
  );
}
