import { createTheme } from '@mui/material/styles';

const theme = createTheme({
  palette: {
    mode: 'dark',
    background: { default: '#14131A', paper: '#1E1C26' },
    primary: { main: '#C8553D' },
    secondary: { main: '#6C7A9C' },
    success: { main: '#6FA96F' },
    text: { primary: '#F2F0E8', secondary: '#A29EAF' },
  },
  typography: {
    fontFamily: '"Pretendard", "Noto Sans KR", system-ui, -apple-system, sans-serif',
    h5: { fontWeight: 700 },
    h6: { fontWeight: 700 },
  },
  shape: { borderRadius: 10 },
});

export default theme;
