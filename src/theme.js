import { createTheme } from '@mui/material/styles';

// 할로윈 배경 — 해마다 10월 5일부터 11월 1일이 끝날 때까지 (한국 시간)
// 상점의 할로윈 프로필과 같은 기간이다 (0054)
// 할로윈에만 보여주는 화면은 모두 이 값을 쓴다. 서버는 is_halloween() 이 같은 기간을 본다
const korea = new Date(Date.now() + 9 * 60 * 60 * 1000);
const month = korea.getUTCMonth() + 1;
const day = korea.getUTCDate();
export const halloween = (month === 10 && day >= 5) || (month === 11 && day === 1);

// 가을 배경 — 해마다 9월 15일부터 11월 15일이 끝날 때까지 (한국 시간). 할로윈과 겹치는
// 날은 할로윈이 나오므로 실제로는 9월 15일 ~ 10월 4일, 11월 2일 ~ 11월 15일이다.
// 상점의 가을 프로필은 할로윈 기간에도 9월 15일 ~ 11월 15일 내내 판다 (0070)
const autumnSeason = (month === 9 && day >= 15) || month === 10 || (month === 11 && day <= 15);
export const autumn = autumnSeason && !halloween;

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

// 호박 한 개. (x, 바닥) 에 놓고 k 배로 그린다
function pumpkin(x, k) {
  return `<g transform="translate(${x} 70) scale(${k})" stroke="#5a2500" stroke-width="1">`
    + '<rect x="-2" y="-34" width="4" height="7" rx="1.5" fill="#558b2f"/>'
    + '<ellipse cx="0" cy="-14" rx="19" ry="14" fill="#f57c00"/>'
    + '<ellipse cx="0" cy="-14" rx="9.5" ry="14" fill="#fb8c00" stroke-opacity="0.35"/>'
    + '<g fill="#3e1c00" stroke="none">'
    + '<path d="M-12 -17L-6 -17L-9 -22ZM6 -17L12 -17L9 -22Z"/>'
    + '<path d="M-12 -11L-8 -8L-4 -10.5L0 -7.5L4 -10.5L8 -8L12 -11L9 -4L-9 -4Z"/>'
    + '</g></g>';
}

// 아래 구석에 놓는 호박 무더기. 왼쪽용을 뒤집어 오른쪽에 쓴다
function pumpkins(mirror) {
  const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="150" height="72" viewBox="0 0 150 72">'
    + `<g${mirror ? ' transform="translate(150 0) scale(-1 1)"' : ''}>`
    + `${pumpkin(118, 0.6)}${pumpkin(84, 0.85)}${pumpkin(36, 1.3)}${pumpkin(64, 0.5)}`
    + '</g></svg>';
  return `url("data:image/svg+xml,${encodeURIComponent(svg)}")`;
}

// 단풍나무 한 그루. 줄기와 가지 위에 붉고 노란 잎 덩어리를 겹친다
function mapleTree(mirror) {
  const crown = [
    [60, 62, 34, '#b71c1c'], [34, 78, 26, '#d84315'], [88, 76, 28, '#c62828'],
    [52, 40, 26, '#e65100'], [80, 46, 24, '#ef6c00'], [64, 86, 24, '#e53935'],
    [26, 56, 18, '#f9a825'], [100, 58, 18, '#ff8f00'], [44, 64, 16, '#fbc02d'],
    [76, 66, 14, '#ffb300'],
  ].map(([cx, cy, r, c]) => `<circle cx="${cx}" cy="${cy}" r="${r}" fill="${c}"/>`).join('');
  const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="130" height="180" viewBox="0 0 130 180">'
    + `<g${mirror ? ' transform="translate(130 0) scale(-1 1)"' : ''}>`
    + '<g fill="none" stroke="#3e2112" stroke-linecap="round">'
    + '<path d="M62 180 C64 150 60 130 62 96" stroke-width="12"/>'
    + '<path d="M62 120 C50 108 40 98 34 82 M62 108 C74 98 84 90 90 78 M62 100 C60 80 54 60 52 44" stroke-width="5"/>'
    + '</g>'
    + `<g fill-opacity="0.92">${crown}</g>`
    + '</g></svg>';
  return `url("data:image/svg+xml,${encodeURIComponent(svg)}")`;
}

// 아래 좌우에 단풍나무를 세우는 가을 배경
const MAPLES = {
  backgroundImage: [mapleTree(false), mapleTree(true)].join(', '),
  backgroundPosition: 'left -10px bottom, right -10px bottom',
  backgroundRepeat: 'no-repeat',
  backgroundAttachment: 'fixed',
};

// 네 구석에 거미줄을, 아래 좌우에 호박을 붙이는 배경
const COBWEBS = {
  backgroundImage: [
    pumpkins(false),
    pumpkins(true),
    cobweb(''),
    cobweb('translate(120 0) scale(-1 1)'),
    cobweb('translate(0 120) scale(1 -1)'),
    cobweb('translate(120 120) scale(-1 -1)'),
  ].join(', '),
  backgroundPosition: 'left 6px bottom, right 6px bottom, left top, right top, left bottom, right bottom',
  backgroundRepeat: 'no-repeat',
  backgroundAttachment: 'fixed',
};

const theme = createTheme({
  palette: {
    mode: 'dark',
    background: {
      default: halloween ? '#AD4B0A' : autumn ? '#3B2416' : '#14131A',
      paper: '#1E1C26',
    },
    // 주황 배경과 어두운 카드 양쪽에서 읽히도록 할로윈 동안은 밝은 색을 쓴다
    primary: { main: halloween ? '#FFE7A8' : autumn ? '#FFB74D' : '#C8553D' },
    secondary: { main: '#6C7A9C' },
    success: { main: '#6FA96F' },
    text: { primary: '#F2F0E8', secondary: halloween ? '#FFE0B2' : autumn ? '#D7C3AE' : '#A29EAF' },
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
    : autumn
      ? {
        MuiCssBaseline: { styleOverrides: { body: MAPLES } },
        MuiDialog: { styleOverrides: { paperFullScreen: { backgroundColor: '#3B2416', ...MAPLES } } },
      }
      : {},
});

export default theme;
