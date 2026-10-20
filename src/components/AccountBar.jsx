import { useState } from 'react';
import Button from '@mui/material/Button';
import Chip from '@mui/material/Chip';
import LinearProgress from '@mui/material/LinearProgress';
import Stack from '@mui/material/Stack';
import Typography from '@mui/material/Typography';
import AssignmentIcon from '@mui/icons-material/Assignment';
import CheckroomIcon from '@mui/icons-material/Checkroom';
import CurrencyExchangeIcon from '@mui/icons-material/CurrencyExchange';
import DiamondIcon from '@mui/icons-material/Diamond';
import EventAvailableIcon from '@mui/icons-material/EventAvailable';
import LocalFireDepartmentIcon from '@mui/icons-material/LocalFireDepartment';
import LogoutIcon from '@mui/icons-material/Logout';
import MonetizationOnIcon from '@mui/icons-material/MonetizationOn';
import StarIcon from '@mui/icons-material/Star';
import StorefrontIcon from '@mui/icons-material/Storefront';

import ProfileAvatar from './ProfileAvatar';
import { levelInfo } from '../lib/level';
import { signOut } from '../lib/supabase';
import { halloween } from '../theme';
import { t } from '../lib/i18n';

// 재화 하나 — 아이콘과 개수
function Currency({ icon, label, value, color }) {
  return (
    <Stack direction="row" alignItems="center" spacing={0.25} aria-label={t('{label} {n}개', { label, n: value })}>
      {icon}
      <Typography variant="body2" fontWeight={700} sx={{ fontVariantNumeric: 'tabular-nums', color }}>
        {value.toLocaleString()}
      </Typography>
    </Stack>
  );
}

// 별·보석·코인 개수. 계정 줄과 퀘스트 화면에서 함께 쓴다
// 할로윈 주황 배경에서는 노란 아이콘이 묻혀서 어두운 바탕을 깐다
export function Wallet({ stars = 0, gems = 0, coins = 0 }) {
  return (
    <Stack
      direction="row"
      alignItems="center"
      spacing={1.25}
      sx={halloween ? { bgcolor: 'background.paper', borderRadius: 4, px: 1.25, py: 0.5 } : undefined}
    >
      <Currency label={t('별')} value={stars} icon={<StarIcon fontSize="small" sx={{ color: '#f5b301' }} />} />
      <Currency label={t('보석')} value={gems} icon={<DiamondIcon fontSize="small" sx={{ color: '#29b6f6' }} />} />
      <Currency label={t('코인')} value={coins} icon={<MonetizationOnIcon fontSize="small" sx={{ color: '#ffa000' }} />} />
    </Stack>
  );
}

// 로그인한 뒤 화면 맨 위. 왼쪽에 프로필(장착한 그림, 없으면 닉네임 첫 글자)과 닉네임·레벨,
// 오른쪽 위에 재화(별·보석·코인), 그 아래 로그아웃, 그 아래 퀘스트, 그 아래 재화 교환소, 그 아래 상점, 그 아래 장착,
// 그 아래 출석, 그 아래 연속 출석
export default function AccountBar({
  nickname, avatar = null, xp = 0, stars = 0, gems = 0, coins = 0,
  onQuest, onExchange, onShop, onEquip, onAttendance, onStreak,
}) {
  const lv = levelInfo(xp);

  const [busy, setBusy] = useState(false);

  async function logout() {
    setBusy(true);
    try {
      // 로그아웃되면 App 이 화면을 새로 불러 로그인 화면으로 돌아간다
      await signOut();
    } catch {
      setBusy(false);
    }
  }

  return (
    <Stack
      direction="row"
      alignItems="flex-start"
      justifyContent="space-between"
      spacing={2}
      sx={{ mb: 3 }}
    >
      {/* 프로필 줄 아래에 레벨 진행 상황 */}
      <Stack spacing={0.75} sx={{ minWidth: 0 }}>
        <Stack direction="row" alignItems="center" spacing={1.25} sx={{ minWidth: 0 }}>
          <ProfileAvatar avatar={avatar} nickname={nickname} size={36} />
          <Typography fontWeight={700} noWrap>
            {nickname}
          </Typography>
          <Chip size="small" color="primary" label={`Lv.${lv.level}`} sx={{ flexShrink: 0 }} />
        </Stack>
        <Stack direction="row" alignItems="center" spacing={0.75}>
          <LinearProgress
            variant="determinate"
            value={lv.max ? 100 : (lv.current / lv.need) * 100}
            sx={{ width: 120, height: 6, borderRadius: 3 }}
            aria-label={t('다음 레벨까지 진행')}
          />
          <Typography variant="caption" color="text.secondary" noWrap>
            {lv.max ? 'MAX' : `${lv.current} / ${lv.need} XP`}
          </Typography>
        </Stack>
      </Stack>

      <Stack alignItems="flex-end" spacing={0.75} sx={{ flexShrink: 0 }}>
        <Wallet stars={stars} gems={gems} coins={coins} />
        <Button
          variant="outlined"
          color="inherit"
          size="small"
          startIcon={<LogoutIcon />}
          onClick={logout}
          loading={busy}
        >
          {t('로그아웃')}
        </Button>
        <Button
          variant="outlined"
          size="small"
          startIcon={<AssignmentIcon />}
          onClick={onQuest}
        >
          {t('퀘스트')}
        </Button>
        <Button
          variant="outlined"
          size="small"
          startIcon={<CurrencyExchangeIcon />}
          onClick={onExchange}
        >
          {t('재화 교환소')}
        </Button>
        <Button
          variant="outlined"
          size="small"
          startIcon={<StorefrontIcon />}
          onClick={onShop}
        >
          {t('상점')}
        </Button>
        <Button
          variant="outlined"
          size="small"
          startIcon={<CheckroomIcon />}
          onClick={onEquip}
        >
          {t('장착')}
        </Button>
        <Button
          variant="outlined"
          size="small"
          startIcon={<EventAvailableIcon />}
          onClick={onAttendance}
        >
          {t('출석')}
        </Button>
        <Button
          variant="outlined"
          size="small"
          startIcon={<LocalFireDepartmentIcon />}
          onClick={onStreak}
        >
          {t('연속 출석')}
        </Button>
      </Stack>
    </Stack>
  );
}
