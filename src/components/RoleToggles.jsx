import { useEffect, useState } from 'react';
import Alert from '@mui/material/Alert';
import Box from '@mui/material/Box';
import ButtonBase from '@mui/material/ButtonBase';
import Chip from '@mui/material/Chip';
import FormControlLabel from '@mui/material/FormControlLabel';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import Switch from '@mui/material/Switch';
import Typography from '@mui/material/Typography';

import RoleAvatar from './RoleAvatar';
import RoleInfoDialog from './RoleInfoDialog';
import { roleInfo, survivorTarget } from '../lib/roles';
import {
  roleComposition, setDisabledRoles, setRandomRoles, setRoleMax, teamComposition,
} from '../lib/api';

// 진영별 이름 색. 목록에 없는 직업(시민 진영)은 기본 흰색.
const NAME_COLOR = {
  MAFIA: 'error.main',
  SPY: 'error.main',
  ASSASSIN: 'error.main',
  FORGER: 'error.main',
  SURVIVOR: '#B388FF',
  JESTER: '#FFD54F',
  KILLER: '#42A5F5',
};

// 시민 진영 특수 직업. 시민을 끄면 시민 진영 자리를 이 직업들로만 채운다
const CITIZEN_SPECIALS = ['POLICE', 'DOCTOR', 'BODYGUARD', 'DETECTIVE', 'REPORTER', 'MEDIUM', 'VIGILANTE', 'SHERIFF'];

// 직업 설정을 진영별로 묶어 보여준다. 시민은 랜덤 구성일 때만 목록에 나온다
const GROUPS = [
  { title: '시민 진영', roles: ['CITIZEN', ...CITIZEN_SPECIALS] },
  { title: '마피아 진영', roles: ['MAFIA', 'SPY', 'ASSASSIN', 'FORGER'] },
  { title: '중립 진영', roles: ['JESTER', 'KILLER', 'SURVIVOR'] },
];

// 대기실에서 직업을 켜고 끈다. 스위치를 누르면 켜고 끄고, 이름을 누르면 설명이 뜬다.
// onBlockedChange: 지금 설정으로는 시작할 수 없는지(마피아 진영 0명, 시민 진영 직업 부족)를 알린다
export default function RoleToggles({ room, isHost, playerCount, onBlockedChange }) {
  const random = room?.random_roles ?? true;
  // 고정 구성은 끈 직업 자리를 시민이 채우므로 시민 끄기를 무시한다 (서버와 같다, 0040)
  const disabled = (room?.disabled_roles ?? []).filter((r) => random || r !== 'CITIZEN');
  // 랜덤 구성에서 특수 직업마다 넣을 최대 인원 (1~3, 기본 1). 고정 구성은 구성표 그대로다 (0041)
  const roleMax = room?.role_max ?? {};
  const maxOf = (code) => Math.min(3, Math.max(1, Number(roleMax[code]) || 1));
  // 최대 일수가 2일 이하이면 생존자는 이길 날이 없어 넣을 수 없다 (서버도 뺀다)
  const target = survivorTarget(room?.max_days ?? 15);
  const survivorBlocked = target === null;
  const effectiveOff = survivorBlocked ? [...disabled, 'SURVIVOR'] : disabled;
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [preview, setPreview] = useState(null);
  // 설명을 보고 있는 직업
  const [info, setInfo] = useState(null);

  // 지금 인원과 설정으로 어떤 구성이 나오는지 서버에 물어 미리 보여준다.
  // 구성표를 화면에 또 적어두면 서버와 어긋날 수 있다.
  useEffect(() => {
    if (!room || playerCount < 5 || playerCount > 15) {
      setPreview(null);
      return;
    }
    let cancelled = false;
    // 랜덤 구성은 직업이 매번 달라서 진영별 인원만 보여준다
    const ask = random
      ? (count, off) => teamComposition(count, off, roleMax)
      : roleComposition;
    ask(playerCount, effectiveOff)
      .then((rows) => {
        if (!cancelled) setPreview(rows);
      })
      .catch(() => {
        if (!cancelled) setPreview(null);
      });
    return () => {
      cancelled = true;
    };
  }, [room, playerCount, random, effectiveOff.join(','), JSON.stringify(roleMax)]);

  // 마피아 진영이 0명이면 시작할 수 없다. 미리보기가 없으면 켜진 직업으로만 판단한다.
  const MAFIA_TEAM = ['MAFIA', 'SPY', 'ASSASSIN', 'FORGER'];
  const noMafiaTeam = preview
    ? (Array.isArray(preview)
      ? !preview.some((r) => MAFIA_TEAM.includes(r))
      : preview.mafia === 0)
    : MAFIA_TEAM.every((r) => disabled.includes(r));

  // 랜덤 구성에서 시민을 끄면 시민 진영 자리를 켜진 시민 진영 직업(각 최대 인원만큼)만으로 채운다
  const citizenOpen = CITIZEN_SPECIALS
    .filter((r) => !effectiveOff.includes(r))
    .reduce((sum, r) => sum + maxOf(r), 0);
  const citizenShort = random && disabled.includes('CITIZEN')
    && preview && !Array.isArray(preview) && citizenOpen < preview.citizen;

  const blocked = Boolean(noMafiaTeam || citizenShort);
  useEffect(() => {
    onBlockedChange?.(blocked);
  }, [blocked, onBlockedChange]);

  if (!room) return null;

  // 그룹에 보여줄 직업. 시민은 랜덤 구성일 때만
  const shown = (roles) => roles.filter((code) => random || code !== 'CITIZEN');

  // 누르면 설명이 뜨는 직업 이름
  const nameButton = (code, on) => (
    <ButtonBase
      onClick={() => setInfo(code)}
      aria-label={`${roleInfo(code).name} 설명 보기`}
      sx={{ borderRadius: 1, px: 0.5, py: 0.25, justifyContent: 'flex-start' }}
    >
      <Stack direction="row" spacing={0.5} alignItems="center">
        <RoleAvatar role={code} size={20} hidden={!on} />
        <Typography
          variant="body2"
          sx={{ color: NAME_COLOR[code], textDecoration: 'underline dotted', textUnderlineOffset: 3 }}
        >
          {roleInfo(code).name}
        </Typography>
      </Stack>
    </ButtonBase>
  );

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

  // ×1 → ×2 → ×3 → ×1 순서로 바꾼다
  async function cycleMax(code) {
    setBusy(true);
    setError('');
    try {
      await setRoleMax(room.id, code, (maxOf(code) % 3) + 1);
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

      <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mb: 1.5 }}>
        랜덤 구성을 키면 마음대로 키고 끄실 수 있습니다.
        <br />
        {random && (
          <>
            직업 옆 ×1을 누르면 그 직업을 최대 3명까지 넣을 수 있습니다.
            <br />
          </>
        )}
        직업 이름을 누르면 능력과 XP 얻는 법을 볼 수 있습니다.
      </Typography>

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
                {shown(group.roles).map((code) => {
                  const locked = code === 'SURVIVOR' && survivorBlocked;
                  const on = !disabled.includes(code) && !locked;
                  return (
                    // 스위치는 켜고 끄기, 이름은 설명 보기로 따로 누른다
                    <Stack key={code} direction="row" alignItems="center" sx={{ minWidth: 0 }}>
                      <Switch
                        size="small"
                        checked={on}
                        disabled={busy || locked}
                        onChange={(e) => toggle(code, e.target.checked)}
                        slotProps={{ input: { 'aria-label': `${roleInfo(code).name} 켜기/끄기` } }}
                      />
                      {nameButton(code, on)}
                      {/* 랜덤 구성에서 켜진 특수 직업은 최대 인원을 정한다 */}
                      {random && on && code !== 'CITIZEN' && code !== 'MAFIA' && (
                        <ButtonBase
                          onClick={() => cycleMax(code)}
                          disabled={busy}
                          aria-label={`${roleInfo(code).name} 최대 ${maxOf(code)}명, 눌러서 바꾸기`}
                          sx={{
                            ml: 'auto',
                            px: 0.75,
                            borderRadius: 1,
                            border: 1,
                            borderColor: maxOf(code) > 1 ? 'primary.main' : 'divider',
                            color: maxOf(code) > 1 ? 'primary.main' : 'text.secondary',
                            fontSize: 12,
                            fontWeight: 700,
                            flexShrink: 0,
                          }}
                        >
                          ×{maxOf(code)}
                        </ButtonBase>
                      )}
                    </Stack>
                  );
                })}
              </Box>
            ) : (
              <Stack direction="row" spacing={0.5} flexWrap="wrap" useFlexGap>
                {shown(group.roles).map((code) => (
                  <Chip
                    key={code}
                    size="small"
                    onClick={() => setInfo(code)}
                    variant={effectiveOff.includes(code) ? 'outlined' : 'filled'}
                    // 색 이름은 주황 배경에서 안 보이므로 회색 배경을 쓴다
                    color={effectiveOff.includes(code) || NAME_COLOR[code] ? 'default' : 'primary'}
                    label={random && maxOf(code) > 1 && code !== 'CITIZEN' && code !== 'MAFIA'
                      ? `${roleInfo(code).name} ×${maxOf(code)}`
                      : roleInfo(code).name}
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
        {random
          ? '시민을 끄면 시민 진영 자리를 켜진 시민 진영 직업으로만 채웁니다.'
          : '고정 구성에서는 시민을 끌 수 없습니다.'}
        {survivorBlocked
          ? ' 최대 일수가 2일 이하라 생존자는 넣을 수 없습니다.'
          : ` 생존자는 ${target}일째 낮이 끝날 때까지 살아 있으면 승리합니다.`}
      </Typography>

      {noMafiaTeam && (
        <Alert severity="warning" sx={{ mt: 1 }}>
          마피아 진영 직업이 하나도 없어 게임을 시작할 수 없습니다.
        </Alert>
      )}

      {citizenShort && (
        <Alert severity="warning" sx={{ mt: 1 }}>
          시민 진영 직업이 부족해 게임을 시작할 수 없습니다.
          (시민 진영 {preview.citizen}자리, 켜진 직업 {citizenOpen}개)
        </Alert>
      )}

      {error && <Alert severity="error" sx={{ mt: 1 }}>{error}</Alert>}

      <RoleInfoDialog role={info} onClose={() => setInfo(null)} />
    </Paper>
  );
}
