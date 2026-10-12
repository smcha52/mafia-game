import { createTheme } from '@mui/material/styles';

// 할로윈 배경 — 10월 12일부터 20일, 11월 1일이 끝날 때까지 (한국 시간)
const HALLOWEEN_UNTIL = new Date('2026-11-02T00:00:00+09:00').getTime();
export const halloween = Date.now() < HALLOWEEN_UNTIL;

// 왼쪽 위 구석의 거미줄. flip 으로 뒤집어 나머지 구석에 쓴다
function cobweb(flip) {
  const angles = [0, 22.5, 45, 67.5, 90].map((d) => (d * Math.PI) / 180);
  const at = (r, a) => `${(r * Math.cos(a)).toFixed(1)} ${(r * Math.sin(a)).toFixed(1)}`;
  const spokes = angles.map((a) => `M0 0L${at(130, a)}`).join('');
  // 살과 살 사이를 안쪽으로 처진 줄로 잇는다
  const threads = [30, 55, 80, 105]
    .map((r) => angles.slice(1).map((a, i) => {
      const mid = (a + angles[i]) / 2;
      return `M${at(r, angles[i])}Q${at(r * 0.82, mid)} ${at(r, a)}`;
    }).join(''))
    .join('');
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="120" height="120" viewBox="0 0 120 120">`
    + `<g transform="${flip}" fill="none" stroke="#fff" stroke-opacity="0.75" stroke-width="1.2">`
    + `<path d="${spokes}${threads}"/></g></svg>`;
  return `url("data:image/svg+xml,${encodeURIComponent(svg)}")`;
}

// 네 구석에 거미줄을 붙이는 배경
const COBWEBS = {
  backgroundImage: [
    cobweb(''),
    cobweb('translate(120 0) scale(-1 1)'),
    cobweb('translate(0 120) scale(1 -1)'),
    cobweb('translate(120 120) scale(-1 -1)'),
  ].join(', '),
  backgroundPosition: 'left top, right top, left bottom, right bottom',
  backgroundRepeat: 'no-repeat',
  backgroundAttachment: 'fixed',
};

const theme = createTheme({
  palette: {
    mode: 'dark',
    background: { default: halloween ? '#AD4B0A' : '#14131A', paper: '#1E1C26' },
    // 주황 배경과 어두운 카드 양쪽에서 읽히도록 할로윈 동안은 밝은 색을 쓴다
    primary: { main: halloween ? '#FFE7A8' : '#C8553D' },
    secondary: { main: '#6C7A9C' },
    success: { main: '#6FA96F' },
    text: { primary: '#F2F0E8', secondary: halloween ? '#FFE0B2' : '#A29EAF' },
  },
  typography: {
    fontFamily: '"Pretendard", "Noto Sans KR", system-ui, -apple-system, sans-serif',
    h5: { fontWeight: 700 },
    h6: { fontWeight: 700 },
  },
  shape: { borderRadius: 10 },
  components: halloween
    ? {
      MuiCssBaseline: { styleOverrides: { body: COBWEBS } },
      // 퀘스트·재화 교환소·상점·장착처럼 화면을 덮는 창도 같은 배경을 쓴다
      MuiDialog: { styleOverrides: { paperFullScreen: { backgroundColor: '#AD4B0A', ...COBWEBS } } },
    }
    : {},
});

export default theme;
