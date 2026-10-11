import { useState } from 'react';
import Alert from '@mui/material/Alert';
import Button from '@mui/material/Button';
import Dialog from '@mui/material/Dialog';
import DialogActions from '@mui/material/DialogActions';
import DialogContent from '@mui/material/DialogContent';
import DialogTitle from '@mui/material/DialogTitle';
import Slider from '@mui/material/Slider';
import Stack from '@mui/material/Stack';
import ToggleButton from '@mui/material/ToggleButton';
import ToggleButtonGroup from '@mui/material/ToggleButtonGroup';
import Typography from '@mui/material/Typography';

import { AGE_MAX, AGE_MIN, LEVEL_MAX, LEVEL_MIN, ruleLabel } from '../lib/roomRules';

// 나이 바로가기. +N 은 N세 이상, -N 은 N세 미만
const AGE_PRESETS = ['+7', '-7', '+13', '-13', '+16', '-16', '+19', '-19'];

const toggleSx = { flexWrap: 'wrap', gap: 0.75, '& .MuiToggleButton-root': { border: 1, borderColor: 'divider', borderRadius: 1, px: 1.5, py: 0.5 } };

// 직접 조절(+/- 와 값 하나) 또는 범위(값 두 개)
function CustomRule({ choice, sign, onSign, value, onValue, range, onRange, min, max, unit }) {
  if (choice === 'CUSTOM') {
    // - 는 그 값보다 낮은 것만 들어올 수 있으므로 최소값보다 커야 한다
    const lo = sign === '-' ? min + 1 : min;
    return (
      <Stack spacing={1} sx={{ mt: 1.5 }}>
        <Stack direction="row" alignItems="center" spacing={1.5}>
          <ToggleButtonGroup
            size="small"
            exclusive
            value={sign}
            onChange={(_, v) => v && onSign(v)}
          >
            <ToggleButton value="+" sx={{ px: 2 }}>+ 이상</ToggleButton>
            <ToggleButton value="-" sx={{ px: 2 }}>- 미만</ToggleButton>
          </ToggleButtonGroup>
          <Typography fontWeight={700}>
            {sign}{Math.max(lo, value)}{unit}
          </Typography>
        </Stack>
        <Slider
          value={Math.max(lo, value)}
          min={lo}
          max={max}
          step={1}
          valueLabelDisplay="auto"
          onChange={(_, v) => onValue(v)}
          marks={[{ value: lo, label: lo }, { value: max, label: max }]}
          sx={{ mx: 1, width: 'auto' }}
        />
      </Stack>
    );
  }
  if (choice === 'RANGE') {
    return (
      <Stack spacing={1} sx={{ mt: 1.5 }}>
        <Typography fontWeight={700}>
          {range[0]}{unit} ~ {range[1]}{unit}
        </Typography>
        <Slider
          value={range}
          min={min}
          max={max}
          step={1}
          valueLabelDisplay="auto"
          onChange={(_, v) => onRange(v)}
          marks={[{ value: min, label: min }, { value: max, label: max }]}
          sx={{ mx: 1, width: 'auto' }}
        />
      </Stack>
    );
  }
  return null;
}

// 고른 버튼과 값으로 서버에 보낼 규칙 { mode, a, b } 를 만든다
function toRule(choice, sign, value, range, min) {
  if (choice === 'NONE' || choice === 'ALL') return { mode: choice };
  if (choice === 'RANGE') return { mode: 'RANGE', a: range[0], b: range[1] };
  if (choice === 'CUSTOM') {
    return sign === '+'
      ? { mode: 'PLUS', a: value }
      : { mode: 'MINUS', a: Math.max(min + 1, value) };
  }
  // 바로가기 (+7, -13 …)
  const n = Number(choice.slice(1));
  return choice[0] === '+' ? { mode: 'PLUS', a: n } : { mode: 'MINUS', a: n };
}

// 방 만들기를 누르면 뜨는 방 설정 화면. 공개 / 비공개는 꼭 골라야 만들 수 있다
export default function CreateRoomDialog({ open, busy, error, onClose, onCreate }) {
  const [isPublic, setIsPublic] = useState(null);

  const [ageChoice, setAgeChoice] = useState('NONE');
  const [ageSign, setAgeSign] = useState('+');
  const [ageValue, setAgeValue] = useState(12);
  const [ageRange, setAgeRange] = useState([10, 15]);

  const [levelChoice, setLevelChoice] = useState('NONE');
  const [levelSign, setLevelSign] = useState('+');
  const [levelValue, setLevelValue] = useState(10);
  const [levelRange, setLevelRange] = useState([10, 30]);

  const age = toRule(ageChoice, ageSign, ageValue, ageRange, AGE_MIN);
  const level = toRule(levelChoice, levelSign, levelValue, levelRange, LEVEL_MIN);

  const summary = (rule, unit) => ruleLabel(rule.mode, rule.a, rule.b, unit) || '설정 안 함';

  return (
    <Dialog open={open} onClose={busy ? undefined : onClose} fullWidth maxWidth="xs">
      <DialogTitle>방 설정</DialogTitle>
      <DialogContent>
        <Stack spacing={3}>
          <div>
            <Typography variant="subtitle2" color="text.secondary" sx={{ mb: 1 }}>
              나이 — {summary(age, '세')}
            </Typography>
            <ToggleButtonGroup
              size="small"
              exclusive
              value={ageChoice}
              onChange={(_, v) => v && setAgeChoice(v)}
              sx={toggleSx}
            >
              <ToggleButton value="NONE">설정 안 하기</ToggleButton>
              <ToggleButton value="ALL">ALL</ToggleButton>
              {AGE_PRESETS.map((p) => (
                <ToggleButton key={p} value={p}>{p}</ToggleButton>
              ))}
              <ToggleButton value="CUSTOM">나이 조절</ToggleButton>
              <ToggleButton value="RANGE">범위 설정</ToggleButton>
            </ToggleButtonGroup>
            <CustomRule
              choice={ageChoice}
              sign={ageSign}
              onSign={setAgeSign}
              value={ageValue}
              onValue={setAgeValue}
              range={ageRange}
              onRange={setAgeRange}
              min={AGE_MIN}
              max={AGE_MAX}
              unit="세"
            />
          </div>

          <div>
            <Typography variant="subtitle2" color="text.secondary" sx={{ mb: 1 }}>
              레벨 제한 — {summary(level, '레벨')}
            </Typography>
            <ToggleButtonGroup
              size="small"
              exclusive
              value={levelChoice}
              onChange={(_, v) => v && setLevelChoice(v)}
              sx={toggleSx}
            >
              <ToggleButton value="NONE">설정 안 하기</ToggleButton>
              <ToggleButton value="CUSTOM">레벨 조절</ToggleButton>
              <ToggleButton value="RANGE">범위 설정</ToggleButton>
            </ToggleButtonGroup>
            <CustomRule
              choice={levelChoice}
              sign={levelSign}
              onSign={setLevelSign}
              value={levelValue}
              onValue={setLevelValue}
              range={levelRange}
              onRange={setLevelRange}
              min={LEVEL_MIN}
              max={LEVEL_MAX}
              unit="레벨"
            />
          </div>

          <div>
            <Typography variant="subtitle2" color="text.secondary" sx={{ mb: 1 }}>
              공개 설정 (필수)
            </Typography>
            <ToggleButtonGroup
              exclusive
              fullWidth
              color="primary"
              value={isPublic}
              onChange={(_, v) => v !== null && setIsPublic(v)}
            >
              <ToggleButton value={true}>공개</ToggleButton>
              <ToggleButton value={false}>비공개</ToggleButton>
            </ToggleButtonGroup>
            <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 0.75 }}>
              {isPublic === null
                ? '공개 또는 비공개를 골라야 방을 만들 수 있습니다.'
                : isPublic
                  ? '빠른 시작과 방 찾기에 나옵니다.'
                  : '방 코드로만 들어올 수 있습니다.'}
            </Typography>
          </div>

          {error && <Alert severity="error">{error}</Alert>}
        </Stack>
      </DialogContent>
      <DialogActions>
        <Button color="inherit" onClick={onClose} disabled={busy}>
          취소
        </Button>
        <Button
          variant="contained"
          disabled={isPublic === null}
          loading={busy}
          onClick={() => onCreate({ isPublic, age, level })}
        >
          방 만들기
        </Button>
      </DialogActions>
    </Dialog>
  );
}
