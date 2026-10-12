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
import DiamondIcon from '@mui/icons-material/Diamond';
import MonetizationOnIcon from '@mui/icons-material/MonetizationOn';
import StarIcon from '@mui/icons-material/Star';

import { Wallet } from './AccountBar';
import ProfileAvatar, { AVATARS } from './ProfileAvatar';
import { buyItem, myShop } from '../lib/api';

const PRICE = {
  STAR: { key: 'stars', label: '별', icon: <StarIcon fontSize="small" sx={{ color: '#f5b301' }} /> },
  GEM: { key: 'gems', label: '보석', icon: <DiamondIcon fontSize="small" sx={{ color: '#29b6f6' }} /> },
  COIN: { key: 'coins', label: '코인', icon: <MonetizationOnIcon fontSize="small" sx={{ color: '#ffa000' }} /> },
};

// 파는 기간이 끝날 때까지 남은 시간
function untilText(iso) {
  const ms = new Date(iso).getTime() - Date.now();
  if (!(ms > 0)) return '곧 종료';
  const min = Math.ceil(ms / 60000);
  const d = Math.floor(min / 1440);
  const h = Math.floor((min % 1440) / 60);
  if (d) return `${d}일 ${h}시간 남음`;
  if (h) return `${h}시간 ${min % 60}분 남음`;
  return `${min}분 남음`;
}

function ItemCard({ item, wallet, busy, disabled, onBuy }) {
  const price = PRICE[item.priceType];
  const enough = (wallet?.[price.key] ?? 0) >= item.price;
  return (
    <Paper sx={{ p: 2 }}>
      <Stack direction="row" alignItems="center" spacing={1.5}>
        <ProfileAvatar avatar={item.id} size={64} />
        <Stack spacing={0.5} sx={{ minWidth: 0, flex: 1 }}>
          <Typography fontWeight={700}>{AVATARS[item.id]?.name ?? item.id}</Typography>
          <Stack direction="row" alignItems="center" spacing={0.5}>
            {price.icon}
            <Typography variant="body2">
              {price.label} {item.price.toLocaleString()}
            </Typography>
          </Stack>
          {item.saleUntil && (
            <Typography variant="caption" color="text.secondary">
              {untilText(item.saleUntil)}
            </Typography>
          )}
        </Stack>
        {item.owned ? (
          <Chip label="보유 중" size="small" />
        ) : (
          <Button
            variant="contained"
            size="small"
            disabled={!enough || disabled}
            loading={busy}
            onClick={() => onBuy(item)}
            sx={{ flexShrink: 0 }}
          >
            구매
          </Button>
        )}
      </Stack>
    </Paper>
  );
}

// 재화 교환소 아래 상점 버튼으로 여는 화면. 사면 onBought 로 재화를 다시 읽게 한다
// wallet = 내 재화 { stars, gems, coins } — 오른쪽 위에 보여준다
export default function ShopDialog({ open, onClose, onBought, wallet }) {
  const [data, setData] = useState(null);
  const [error, setError] = useState('');
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

  async function buy(item) {
    setBusy(item.id);
    setError('');
    try {
      await buyItem(item.id);
      await load();
      await onBought?.();
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
          <IconButton onClick={onClose} aria-label="뒤로">
            <ArrowBackIcon />
          </IconButton>
          <Typography variant="h6" sx={{ flex: 1 }}>상점</Typography>
          <Wallet {...wallet} />
        </Stack>

        {error && <Alert severity="error" sx={{ mb: 2 }}>{error}</Alert>}

        {!data ? (
          !error && (
            <Stack alignItems="center" sx={{ py: 6 }}>
              <CircularProgress />
            </Stack>
          )
        ) : data.items.length === 0 ? (
          <Paper sx={{ p: 4, textAlign: 'center' }}>
            <Typography color="text.secondary">지금 파는 물건이 없습니다.</Typography>
          </Paper>
        ) : (
          <Stack spacing={1}>
            <Typography variant="caption" color="text.secondary">
              🎃 할로윈 프로필 · 산 프로필은 상점 아래 장착에서 바꿉니다.
            </Typography>
            {data.items.map((item) => (
              <ItemCard
                key={item.id}
                item={item}
                wallet={wallet}
                busy={busy === item.id}
                disabled={busy !== null}
                onBuy={buy}
              />
            ))}
          </Stack>
        )}
      </Box>
    </Dialog>
  );
}
