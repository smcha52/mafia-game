import Chip from '@mui/material/Chip';
import Stack from '@mui/material/Stack';

// 승패 화면에서 한 사람의 생사와 승패. win 이 null 이면 무승부
export default function ResultChips({ alive, win }) {
  return (
    <Stack direction="row" spacing={0.5} sx={{ flexShrink: 0, ml: 1 }}>
      <Chip
        size="small"
        variant="outlined"
        color={alive ? 'success' : 'default'}
        label={alive ? '생존' : '사망'}
      />
      <Chip
        size="small"
        color={win === null ? 'default' : win ? 'primary' : 'default'}
        variant={win ? 'filled' : 'outlined'}
        label={win === null ? '무승부' : win ? '승리' : '패배'}
      />
    </Stack>
  );
}
