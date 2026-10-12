import Box from '@mui/material/Box';
import { keyframes } from '@mui/material/styles';

const SIZE = 26;
// 거미줄 한가운데쯤. 화면 가장자리에서 거미까지의 거리
const EDGE = 28;
const FAR = `calc(100% - ${EDGE + SIZE}px)`;

// 네 구석의 거미줄을 시계 방향으로 돈다. 구석에서 몸을 돌린다 (그림은 위를 본다)
const crawl = keyframes`
  0%   { left: ${EDGE}px; top: ${EDGE}px; transform: rotate(90deg); }
  23%  { left: ${FAR}; top: ${EDGE}px; transform: rotate(90deg); }
  25%  { left: ${FAR}; top: ${EDGE}px; transform: rotate(180deg); }
  48%  { left: ${FAR}; top: ${FAR}; transform: rotate(180deg); }
  50%  { left: ${FAR}; top: ${FAR}; transform: rotate(270deg); }
  73%  { left: ${EDGE}px; top: ${FAR}; transform: rotate(270deg); }
  75%  { left: ${EDGE}px; top: ${FAR}; transform: rotate(360deg); }
  98%  { left: ${EDGE}px; top: ${EDGE}px; transform: rotate(360deg); }
  100% { left: ${EDGE}px; top: ${EDGE}px; transform: rotate(450deg); }
`;

const LAP = 48;

function Spider({ delay }) {
  return (
    <Box
      component="svg"
      viewBox="0 0 26 26"
      sx={{
        position: 'absolute',
        left: EDGE,
        top: EDGE,
        width: SIZE,
        height: SIZE,
        animation: `${crawl} ${LAP}s linear infinite`,
        animationDelay: `${delay}s`,
      }}
    >
      <g fill="none" stroke="#150d2b" strokeWidth="1.3" strokeLinecap="round">
        <path d="M11 10 L5 5 L3 1 M11 12 L4 10 L1 7 M11 14 L4 16 L1 20 M11 16 L6 21 L5 25" />
        <path d="M15 10 L21 5 L23 1 M15 12 L22 10 L25 7 M15 14 L22 16 L25 20 M15 16 L20 21 L21 25" />
      </g>
      <ellipse cx="13" cy="15.5" rx="4.6" ry="5.4" fill="#150d2b" />
      <circle cx="13" cy="8.8" r="2.9" fill="#150d2b" />
      <circle cx="11.9" cy="7.6" r="0.6" fill="#ffd54f" />
      <circle cx="14.1" cy="7.6" r="0.6" fill="#ffd54f" />
    </Box>
  );
}

const GHOST = 34;
const GHOST_FAR = `calc(100% - ${EDGE + GHOST}px)`;

// 대각선 하나를 오간다. 두 대각선이 X 모양이 된다
const driftDown = keyframes`
  from { left: ${EDGE}px; top: ${EDGE}px; }
  to   { left: ${GHOST_FAR}; top: ${GHOST_FAR}; }
`;
const driftUp = keyframes`
  from { left: ${GHOST_FAR}; top: ${EDGE}px; }
  to   { left: ${EDGE}px; top: ${GHOST_FAR}; }
`;

// 글씨를 가리지 않도록 반투명하게 그린다
function Ghost({ path }) {
  return (
    <Box
      component="svg"
      viewBox="0 0 34 34"
      sx={{
        position: 'absolute',
        width: GHOST,
        height: GHOST,
        opacity: 0.6,
        animation: `${path} 22s ease-in-out infinite alternate`,
      }}
    >
      <path
        d="M5 32 V15 a12 12 0 0 1 24 0 V32 l-4 -3.5 l-4 3.5 l-4 -3.5 l-4 3.5 l-4 -3.5 Z"
        fill="#f5f5f5"
      />
      <g fill="#1b1330">
        <ellipse cx="12.5" cy="14.5" rx="2.2" ry="3" />
        <ellipse cx="21.5" cy="14.5" rx="2.2" ry="3" />
        <ellipse cx="17" cy="21" rx="2.4" ry="1.8" />
      </g>
    </Box>
  );
}

// 할로윈 배경 위를 도는 거미 두 마리(서로 맞은편 구석에서 출발)와
// X 모양으로 오가는 유령 둘. 창 위에도 보이지만 누르는 것은 막지 않는다
export default function HalloweenSpiders() {
  return (
    <Box
      aria-hidden="true"
      sx={{ position: 'fixed', inset: 0, zIndex: 'tooltip', pointerEvents: 'none', overflow: 'hidden' }}
    >
      <Spider delay={0} />
      <Spider delay={-LAP / 2} />
      <Ghost path={driftDown} />
      <Ghost path={driftUp} />
    </Box>
  );
}
