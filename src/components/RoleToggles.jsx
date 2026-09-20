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
import { TOGGLEABLE, roleInfo } from '../lib/roles';
import { roleComposition, setDisabledRoles } from '../lib/api';

// 대기실에서 직업을 켜고 끈다. 끈 직업 자리는 시민이 채운다.
export default function RoleToggles({ room, isHost, playerCount }) {
  const disabled = room?.disabled_roles ?? [];
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
    roleComposition(playerCount, disabled)
      .then((rows) => {
        if (!cancelled) setPreview(rows);
      })
      .catch(() => {
        if (!cancelled) setPreview(null);
      });
    return () => {
      cancelled = true;
    };
  }, [room, playerCount, disabled.join(',')]);

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

  const counts = (preview ?? []).reduce((acc, r) => {
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

      {isHost ? (
        <Box
          sx={{
            display: 'grid',
            gridTemplateColumns: { xs: '1fr 1fr', sm: '1fr 1fr 1fr' },
            columnGap: 1,
          }}
        >
          {TOGGLEABLE.map((code) => {
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
                    <Typography variant="body2">{roleInfo(code).name}</Typography>
                  </Stack>
                }
              />
            );
          })}
        </Box>
      ) : (
        <Stack direction="row" spacing={0.5} flexWrap="wrap" useFlexGap>
          {TOGGLEABLE.map((code) => (
            <Chip
              key={code}
              size="small"
              variant={disabled.includes(code) ? 'outlined' : 'filled'}
              color={disabled.includes(code) ? 'default' : 'primary'}
              label={roleInfo(code).name}
            />
          ))}
        </Stack>
      )}

      {/* 지금 인원으로 실제 나오는 구성 */}
      {preview && (
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
        마피아와 시민은 끌 수 없습니다.
      </Typography>

      {error && <Alert severity="error" sx={{ mt: 1 }}>{error}</Alert>}
    </Paper>
  );
}
