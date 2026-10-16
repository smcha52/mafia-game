import { useEffect, useState } from 'react';
import Box from '@mui/material/Box';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import Typography from '@mui/material/Typography';
import EmojiEventsIcon from '@mui/icons-material/EmojiEvents';

import { REWARD, untilText } from './QuestDialog';
import { myDailyRewards } from '../lib/api';

// 등급 이름과 색
export const TIER = {
  NORMAL: { label: '일반', color: 'text.secondary' },
  LUCKY: { label: '럭키', color: '#2e7d32' },
  SUPER_LUCKY: { label: '슈퍼 럭키', color: '#d500f9' },
};

// 칸 하나 — 위에 등급, 아래에 보상. 아직 받지 않은 칸은 비워 둔다
function RewardCell({ item }) {
  const tier = item && TIER[item.tier];
  return (
    <Paper
      variant="outlined"
      sx={{
        p: 0.75,
        minHeight: 64,
        textAlign: 'center',
        borderColor: item && item.tier !== 'NORMAL' ? tier.color : undefined,
        borderWidth: item && item.tier !== 'NORMAL' ? 2 : 1,
      }}
    >
      <Typography
        variant="caption"
        fontWeight={700}
        sx={{ color: tier ? tier.color : 'text.disabled', display: 'block', whiteSpace: 'nowrap' }}
      >
        {tier ? tier.label : '?'}
      </Typography>
      {item ? (
        <Stack
          direction="row"
          alignItems="center"
          justifyContent="center"
          spacing={0.25}
          sx={{ mt: 0.5 }}
          aria-label={`${REWARD[item.type].label} ${item.amount}개`}
        >
          {REWARD[item.type].icon}
          <Typography variant="body2" fontWeight={700}>{item.amount}</Typography>
        </Stack>
      ) : (
        <EmojiEventsIcon fontSize="small" sx={{ mt: 0.5, color: 'text.disabled' }} aria-label="승리하면 받음" />
      )}
    </Paper>
  );
}

// 홈 화면 방 찾기 아래. 이길 때마다 보상 하나, 하루에 5개까지 (0057)
// 게임이 끝나 홈으로 돌아오면 다시 그려지므로 그때 새로 읽는다
export default function DailyRewards() {
  const [data, setData] = useState(null);

  useEffect(() => {
    myDailyRewards().then(setData).catch(() => setData(null));
  }, []);

  if (!data) return null;

  const done = data.items.length >= data.limit;
  return (
    <Box>
      <Stack direction="row" alignItems="baseline" justifyContent="space-between" sx={{ mb: 0.75 }}>
        <Typography variant="subtitle2" fontWeight={700}>
          일일보상 {data.items.length}/{data.limit}
        </Typography>
        <Typography variant="caption" color="text.secondary">
          {done ? `${untilText(data.next)} 뒤 다시 받을 수 있어요` : '승리하면 하나씩 받아요'}
        </Typography>
      </Stack>
      <Box sx={{ display: 'grid', gridTemplateColumns: `repeat(${data.limit}, 1fr)`, gap: 0.75 }}>
        {Array.from({ length: data.limit }, (_, i) => (
          <RewardCell key={i} item={data.items[i]} />
        ))}
      </Box>
    </Box>
  );
}
