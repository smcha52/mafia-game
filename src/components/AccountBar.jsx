import { useState } from 'react';
import Avatar from '@mui/material/Avatar';
import Button from '@mui/material/Button';
import Chip from '@mui/material/Chip';
import LinearProgress from '@mui/material/LinearProgress';
import Stack from '@mui/material/Stack';
import Typography from '@mui/material/Typography';
import AssignmentIcon from '@mui/icons-material/Assignment';
import DiamondIcon from '@mui/icons-material/Diamond';
import LogoutIcon from '@mui/icons-material/Logout';
import MonetizationOnIcon from '@mui/icons-material/MonetizationOn';
import StarIcon from '@mui/icons-material/Star';

import { levelInfo } from '../lib/level';
import { signOut } from '../lib/supabase';

// 재화 하나 — 아이콘과 개수
function Currency({ icon, label, value, color }) {
  return (
    <Stack direction="row" alignItems="center" spacing={0.25} aria-label={`${label} ${value}개`}>
      {icon}
      <Typography variant="body2" fontWeight={700} sx={{ fontVariantNumeric: 'tabular-nums', color }}>
        {value.toLocaleString()}
      </Typography>
    </Stack>
  );
}

// 별·보석·코인 개수. 계정 줄과 퀘스트 화면에서 함께 쓴다
export function Wallet({ stars = 0, gems = 0, coins = 0 }) {
  return (
    <Stack direction="row" alignItems="center" spacing={1.25}>
      <Currency label="별" value={stars} icon={<StarIcon fontSize="small" sx={{ color: '#f5b301' }} />} />
      <Currency label="보석" value={gems} icon={<DiamondIcon fontSize="small" sx={{ color: '#29b6f6' }} />} />
      <Currency label="코인" value={coins} icon={<MonetizationOnIcon fontSize="small" sx={{ color: '#ffa000' }} />} />
    </Stack>
  );
}

// 로그인한 뒤 화면 맨 위. 왼쪽에 프로필(닉네임 첫 글자)과 닉네임·레벨,
// 오른쪽 위에 재화(별·보석·코인), 그 아래 로그아웃, 그 아래 퀘스트
export default function AccountBar({ nickname, xp = 0, stars = 0, gems = 0, coins = 0, onQuest }) {
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
          <Avatar sx={{ bgcolor: 'primary.main', width: 36, height: 36, fontSize: 16, fontWeight: 700 }}>
            {Array.from(nickname)[0]}
          </Avatar>
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
            aria-label="다음 레벨까지 진행"
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
          로그아웃
        </Button>
        <Button
          variant="outlined"
          size="small"
          startIcon={<AssignmentIcon />}
          onClick={onQuest}
        >
          퀘스트
        </Button>
      </Stack>
    </Stack>
  );
}
