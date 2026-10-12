import Box from '@mui/material/Box';
import Dialog from '@mui/material/Dialog';
import IconButton from '@mui/material/IconButton';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import Typography from '@mui/material/Typography';
import ArrowBackIcon from '@mui/icons-material/ArrowBack';

import { Wallet } from './AccountBar';

// 재화 교환소 아래 상점 버튼으로 여는 화면. 아직 파는 물건은 없다
// wallet = 내 재화 { stars, gems, coins } — 오른쪽 위에 보여준다
export default function ShopDialog({ open, onClose, wallet }) {
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

        <Paper sx={{ p: 4, textAlign: 'center' }}>
          <Typography color="text.secondary">상점은 준비 중입니다.</Typography>
        </Paper>
      </Box>
    </Dialog>
  );
}
