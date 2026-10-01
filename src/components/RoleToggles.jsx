import { useEffect, useState } from 'react';
import Alert from '@mui/material/Alert';
import Box from '@mui/material/Box';
import Chip from '@mui/material/Chip';
import FormControlLabel from '@mui/material/FormControlLabel';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import Switch from '@mui/material/Switch';
import Typography from '@mui/material/Typography';

import RoleAvatar from './RoleAvatar';
import { roleInfo } from '../lib/roles';
import {
  roleComposition, setDisabledRoles, setRandomRoles, teamComposition,
} from '../lib/api';

// 진영별 이름 색. 목록에 없는 직업(시민 진영)은 기본 흰색.
const NAME_COLOR = {
  MAFIA: 'error.main',
  SPY: 'error.main',
  ASSASSIN: 'error.main',
  JESTER: '#FFD54F',
  KILLER: '#42A5F5',
};

// 직업 설정을 진영별로 묶어 보여준다
const GROUPS = [
  { title: '시민 진영', roles: ['POLICE', 'DOCTOR', 'BODYGUARD', 'DETECTIVE', 'REPORTER', 'MEDIUM', 'VIGILANTE', 'SHERIFF'] },
  { title: '마피아 진영', roles: ['MAFIA', 'SPY', 'ASSASSIN'] },
  { title: '중립 진영', roles: ['JESTER', 'KILLER'] },
];

// 대기실에서 직업을 켜고 끈다. 끈 직업 자리는 시민이 채운다.
export default function RoleToggles({ room, isHost, playerCount }) {
  const disabled = room?.disabled_roles ?? [];
  const random = room?.random_roles ?? true;
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [preview, setPreview] = useState(null);

  // 지금 인원과 설정으로 어떤 구성이 나오는지 서버에 물어 미리 보여준다.
  // 구성표를 화면에 또 적어두면 서버와 어긋날 수 있다.
  useEffect(() => {
    if (!room || playerCount < 5 || playerCount > 15) {
      setPreview(null);
      return;
    }
    let cancelled = false;
    // 랜덤 구성은 직업이 매번 달라서 진영별 인원만 보여준다
    const ask = random ? teamComposition : roleComposition;
    ask(playerCount, disabled)
      .then((rows) => {
        if (!cancelled) setPreview(rows);
      })
      .catch(() => {
        if (!cancelled) setPreview(null);
      });
    return () => {
      cancelled = true;
    };
  }, [room, playerCount, random, disabled.join(',')]);

  if (!room) return null;

  async function toggle(code, on) {
    const next = on
      ? disabled.filter((x) => x !== code)
      : [...disabled, code];
    setBusy(true);
    setError('');
    try {
      await setDisabledRoles(room.id, next);
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }

  async function toggleRandom(on) {
    setBusy(true);
    setError('');
    try {
      await setRandomRoles(room.id, on);
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }

  const counts = (Array.isArray(preview) ? preview : []).reduce((acc, r) => {
    acc[r] = (acc[r] ?? 0) + 1;
    return acc;
  }, {});

  // 마피아 진영이 0명이면 시작할 수 없다. 미리보기가 없으면 켜진 직업으로만 판단한다.
  const MAFIA_TEAM = ['MAFIA', 'SPY', 'ASSASSIN'];
  const noMafiaTeam = preview
    ? (Array.isArray(preview)
      ? !preview.some((r) => MAFIA_TEAM.includes(r))
      : preview.mafia === 0)
    : MAFIA_TEAM.every((r) => disabled.includes(r));

  return (
    <Paper sx={{ p: 2 }}>
      <Typography variant="body2" color="text.secondary" sx={{ mb: 1.5 }}>
        {isHost
          ? '직업 설정 — 끈 직업은 시민으로 대체됩니다'
          : '직업 설정'}
      </Typography>

      {/* 랜덤 구성: 진영별 인원만 정하고 진영 안에서 직업을 무작위로 뽑는다 */}
      {isHost ? (
        <FormControlLabel
          sx={{ ml: 0, mb: 1 }}
          control={
            <Switch
              size="small"
              checked={random}
              disabled={busy}
              onChange={(e) => toggleRandom(e.target.checked)}
            />
          }
          label={<Typography variant="body2">랜덤 구성</Typography>}
        />
      ) : (
        <Chip
          size="small"
          sx={{ mb: 1 }}
          label={random ? '랜덤 구성' : '고정 구성'}
        />
      )}

      <Stack spacing={1.5}>
        {GROUPS.map((group) => (
          <Box key={group.title}>
            <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mb: 0.5 }}>
              {group.title}
            </Typography>

            {isHost ? (
              <Box
                sx={{
                  display: 'grid',
                  gridTemplateColumns: { xs: '1fr 1fr', sm: '1fr 1fr 1fr' },
                  columnGap: 1,
                }}
              >
                {group.roles.map((code) => {
                  const on = !disabled.includes(code);
                  return (
                    <FormControlLabel
                      key={code}
                      sx={{ ml: 0, mr: 0 }}
                      control={
                        <Switch
                          size="small"
                          checked={on}
                          disabled={busy}
                          onChange={(e) => toggle(code, e.target.checked)}
                        />
                      }
                      label={
                        <Stack direction="row" spacing={0.5} alignItems="center">
                          <RoleAvatar role={code} size={20} hidden={!on} />
                          <Typography variant="body2" sx={{ color: NAME_COLOR[code] }}>
                            {roleInfo(code).name}
                          </Typography>
                        </Stack>
                      }
                    />
                  );
                })}
              </Box>
            ) : (
              <Stack direction="row" spacing={0.5} flexWrap="wrap" useFlexGap>
                {group.roles.map((code) => (
                  <Chip
                    key={code}
                    size="small"
                    variant={disabled.includes(code) ? 'outlined' : 'filled'}
                    // 색 이름은 주황 배경에서 안 보이므로 회색 배경을 쓴다
                    color={disabled.includes(code) || NAME_COLOR[code] ? 'default' : 'primary'}
                    label={roleInfo(code).name}
                    sx={{ color: NAME_COLOR[code] }}
                  />
                ))}
              </Stack>
            )}
          </Box>
        ))}
      </Stack>

      {/* 랜덤 구성: 진영별 인원 */}
      {preview && random && !Array.isArray(preview) && (
        <Box sx={{ mt: 1.5 }}>
          <Typography variant="caption" color="text.secondary">
            {playerCount}명 구성 — 진영 안의 직업은 시작할 때 무작위로 정해집니다
          </Typography>
          <Stack direction="row" spacing={0.5} sx={{ mt: 0.5 }} flexWrap="wrap" useFlexGap>
            <Chip size="small" label={`시민 진영 ${preview.citizen}`} />
            <Chip size="small" label={`마피아 진영 ${preview.mafia}`} sx={{ color: 'error.main' }} />
            {preview.neutral > 0 && (
              <Chip size="small" label={`중립 ${preview.neutral}`} />
            )}
          </Stack>
        </Box>
      )}

      {/* 고정 구성: 지금 인원으로 실제 나오는 구성 */}
      {preview && !random && Array.isArray(preview) && (
        <Box sx={{ mt: 1.5 }}>
          <Typography variant="caption" color="text.secondary">
            {playerCount}명 구성
          </Typography>
          <Stack direction="row" spacing={0.5} sx={{ mt: 0.5 }} flexWrap="wrap" useFlexGap>
            {Object.entries(counts)
              .sort((a, b) => b[1] - a[1])
              .map(([code, n]) => (
                <Chip key={code} size="small" label={`${roleInfo(code).name} ${n}`} />
              ))}
          </Stack>
        </Box>
      )}

      {!preview && playerCount > 0 && playerCount < 5 && (
        <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 1.5 }}>
          5명부터 구성을 볼 수 있습니다.
        </Typography>
      )}

      <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 1 }}>
        시민은 끌 수 없습니다.
      </Typography>

      {noMafiaTeam && (
        <Alert severity="warning" sx={{ mt: 1 }}>
          마피아 진영 직업이 하나도 없어 게임을 시작할 수 없습니다.
        </Alert>
      )}

      {error && <Alert severity="error" sx={{ mt: 1 }}>{error}</Alert>}
    </Paper>
  );
}
