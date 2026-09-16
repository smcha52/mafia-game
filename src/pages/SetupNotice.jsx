import Alert from '@mui/material/Alert';
import AlertTitle from '@mui/material/AlertTitle';
import Box from '@mui/material/Box';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import Typography from '@mui/material/Typography';

// .env 가 비어 있을 때 흰 화면 대신 설정 방법을 보여준다
export default function SetupNotice() {
  return (
    <Stack sx={{ minHeight: '100dvh', p: 3 }} alignItems="center" justifyContent="center">
      <Paper sx={{ p: 3, maxWidth: 520 }}>
        <Stack spacing={2}>
          <Typography variant="h6">Supabase 설정이 필요합니다</Typography>

          <Alert severity="warning">
            <AlertTitle>환경변수가 비어 있습니다</AlertTitle>
            프로젝트 루트에 <code>.env</code> 파일을 만들고 아래 두 값을 채워 주세요.
          </Alert>

          <Box
            component="pre"
            sx={{
              m: 0,
              p: 2,
              borderRadius: 1,
              bgcolor: 'background.default',
              overflowX: 'auto',
              fontSize: 13,
            }}
          >
{`VITE_SUPABASE_URL=https://xxxx.supabase.co
VITE_SUPABASE_ANON_KEY=eyJhbGci...`}
          </Box>

          <Typography variant="body2" color="text.secondary">
            값은 Supabase 대시보드 → Project Settings → API 에서 확인할 수 있습니다.
            수정 후 개발 서버를 다시 시작해 주세요.
          </Typography>
        </Stack>
      </Paper>
    </Stack>
  );
}
