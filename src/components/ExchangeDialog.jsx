import { useEffect, useState } from 'react';
import Alert from '@mui/material/Alert';
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Dialog from '@mui/material/Dialog';
import IconButton from '@mui/material/IconButton';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import ToggleButton from '@mui/material/ToggleButton';
import ToggleButtonGroup from '@mui/material/ToggleButtonGroup';
import Typography from '@mui/material/Typography';
import ArrowBackIcon from '@mui/icons-material/ArrowBack';
import ArrowForwardIcon from '@mui/icons-material/ArrowForward';
import DiamondIcon from '@mui/icons-material/Diamond';
import MonetizationOnIcon from '@mui/icons-material/MonetizationOn';
import StarIcon from '@mui/icons-material/Star';

import { Wallet } from './AccountBar';
import { exchangeCurrency } from '../lib/api';
import { localized, t } from '../lib/i18n';

const CURRENCY = localized({
  STAR: { key: 'stars', label: '별', icon: <StarIcon fontSize="small" sx={{ color: '#f5b301' }} /> },
  GEM: { key: 'gems', label: '보석', icon: <DiamondIcon fontSize="small" sx={{ color: '#29b6f6' }} /> },
  COIN: { key: 'coins', label: '코인', icon: <MonetizationOnIcon fontSize="small" sx={{ color: '#ffa000' }} /> },
});

// 교환 비율 (0048 exchange_currency)
const RATES = [
  { kind: 'COIN_TO_STAR', pay: 'COIN', payAmount: 4, get: 'STAR', getAmount: 1 },
  { kind: 'STAR_TO_GEM', pay: 'STAR', payAmount: 25, get: 'GEM', getAmount: 1 },
  { kind: 'STAR_TO_COIN', pay: 'STAR', payAmount: 1, get: 'COIN', getAmount: 4 },
  { kind: 'GEM_TO_STAR', pay: 'GEM', payAmount: 1, get: 'STAR', getAmount: 25 },
];

const TIMES = [1, 5, 10, 50];

// 재화 하나 — 아이콘과 이름·개수
function Amount({ type, amount }) {
  const c = CURRENCY[type];
  return (
    <Stack direction="row" alignItems="center" spacing={0.5}>
      {c.icon}
      <Typography fontWeight={700} sx={{ fontVariantNumeric: 'tabular-nums' }}>
        {c.label} {amount.toLocaleString()}
      </Typography>
    </Stack>
  );
}

function RateCard({ rate, times, wallet, busy, disabled, onExchange }) {
  const pay = rate.payAmount * times;
  const enough = (wallet?.[CURRENCY[rate.pay].key] ?? 0) >= pay;
  return (
    <Paper sx={{ p: 2 }}>
      <Stack direction="row" alignItems="center" justifyContent="space-between" spacing={1}>
        <Stack direction="row" alignItems="center" spacing={1} sx={{ minWidth: 0, flexWrap: 'wrap' }}>
          <Amount type={rate.pay} amount={pay} />
          <ArrowForwardIcon fontSize="small" color="action" />
          <Amount type={rate.get} amount={rate.getAmount * times} />
        </Stack>
        <Button
          variant="contained"
          size="small"
          disabled={!enough || disabled}
          loading={busy}
          onClick={() => onExchange(rate)}
          sx={{ flexShrink: 0 }}
        >
          {t('교환')}
        </Button>
      </Stack>
    </Paper>
  );
}

// 퀘스트 아래 재화 교환소 버튼으로 여는 화면. 교환하면 onExchanged 로 재화를 다시 읽게 한다
// wallet = 내 재화 { stars, gems, coins } — 오른쪽 위에 보여준다
export default function ExchangeDialog({ open, onClose, onExchanged, wallet }) {
  // 한 번에 바꾸는 배수. 내고 받는 양이 함께 늘어난다
  const [times, setTimes] = useState(1);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(null);

  useEffect(() => {
    if (open) setError('');
  }, [open]);

  async function exchange(rate) {
    setBusy(rate.kind);
    setError('');
    try {
      await exchangeCurrency(rate.kind, times);
      await onExchanged?.();
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(null);
    }
  }

  return (
    <Dialog open={open} onClose={onClose} fullScreen>
      <Box sx={{ maxWidth: 480, width: '100%', mx: 'auto', px: 2, py: 2 }}>
        <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 2 }}>
          <IconButton onClick={onClose} aria-label={t('뒤로')}>
            <ArrowBackIcon />
          </IconButton>
          <Typography variant="h6" sx={{ flex: 1 }}>{t('재화 교환소')}</Typography>
          <Wallet {...wallet} />
        </Stack>

        {error && <Alert severity="error" sx={{ mb: 2 }}>{t(error)}</Alert>}

        <Stack spacing={1}>
          {RATES.map((rate) => (
            <RateCard
              key={rate.kind}
              rate={rate}
              times={times}
              wallet={wallet}
              busy={busy === rate.kind}
              disabled={busy !== null}
              onExchange={exchange}
            />
          ))}
        </Stack>

        <ToggleButtonGroup
          value={times}
          exclusive
          fullWidth
          color="primary"
          onChange={(_, v) => v && setTimes(v)}
          aria-label={t('교환 배수')}
          sx={{ mt: 2 }}
        >
          {TIMES.map((n) => (
            <ToggleButton key={n} value={n}>x{n}</ToggleButton>
          ))}
        </ToggleButtonGroup>
      </Box>
    </Dialog>
  );
}
