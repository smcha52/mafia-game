import { useCallback, useEffect, useState } from 'react';
import Alert from '@mui/material/Alert';
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Chip from '@mui/material/Chip';
import CircularProgress from '@mui/material/CircularProgress';
import Dialog from '@mui/material/Dialog';
import IconButton from '@mui/material/IconButton';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import Typography from '@mui/material/Typography';
import ArrowBackIcon from '@mui/icons-material/ArrowBack';

import ProfileAvatar, { AVATARS } from './ProfileAvatar';
import { equipAvatar, myShop } from '../lib/api';
import { t } from '../lib/i18n';

// 상점 아래 장착 버튼으로 여는 화면. 산 프로필 중 하나를 고른다
// 바꾸면 onEquipped 로 프로필을 다시 읽게 한다
export default function EquipDialog({ open, onClose, onEquipped, nickname }) {
  const [data, setData] = useState(null);
  const [error, setError] = useState('');
  // 바꾸는 중인 프로필 id. 기본 프로필은 'DEFAULT'
  const [busy, setBusy] = useState(null);

  const load = useCallback(async () => {
    setError('');
    try {
      setData(await myShop());
    } catch (e) {
      setError(e.message);
    }
  }, []);

  useEffect(() => {
    if (open) load();
  }, [open, load]);

  async function equip(id) {
    setBusy(id ?? 'DEFAULT');
    setError('');
    try {
      await equipAvatar(id);
      await load();
      await onEquipped?.();
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(null);
    }
  }

  // 맨 위는 기본 프로필(id null), 그 아래에 산 프로필
  const rows = data
    ? [{ id: null, name: t('기본 프로필') },
      ...data.owned
        .filter((o) => o.kind === 'AVATAR')
        .map((o) => ({ id: o.id, name: AVATARS[o.id]?.name ?? o.id }))]
    : [];

  return (
    <Dialog open={open} onClose={onClose} fullScreen>
      <Box sx={{ maxWidth: 480, width: '100%', mx: 'auto', px: 2, py: 2 }}>
        <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 2 }}>
          <IconButton onClick={onClose} aria-label={t('뒤로')}>
            <ArrowBackIcon />
          </IconButton>
          <Typography variant="h6" sx={{ flex: 1 }}>{t('장착')}</Typography>
        </Stack>

        {error && <Alert severity="error" sx={{ mb: 2 }}>{t(error)}</Alert>}

        {!data ? (
          !error && (
            <Stack alignItems="center" sx={{ py: 6 }}>
              <CircularProgress />
            </Stack>
          )
        ) : (
          <Stack spacing={1}>
            <Typography variant="caption" color="text.secondary">
              {t('프로필 · 상점에서 산 프로필이 여기에 모입니다.')}
            </Typography>
            {rows.map((row) => {
              const equipped = (data.avatar ?? null) === row.id;
              const key = row.id ?? 'DEFAULT';
              return (
                <Paper key={key} sx={{ p: 2 }}>
                  <Stack direction="row" alignItems="center" spacing={1.5}>
                    <ProfileAvatar avatar={row.id} nickname={nickname} size={56} />
                    <Typography fontWeight={700} sx={{ minWidth: 0, flex: 1 }}>{row.name}</Typography>
                    {equipped ? (
                      <Chip label={t('장착 중')} color="primary" size="small" />
                    ) : (
                      <Button
                        variant="contained"
                        size="small"
                        disabled={busy !== null}
                        loading={busy === key}
                        onClick={() => equip(row.id)}
                        sx={{ flexShrink: 0 }}
                      >
                        {t('장착')}
                      </Button>
                    )}
                  </Stack>
                </Paper>
              );
            })}
          </Stack>
        )}
      </Box>
    </Dialog>
  );
}
