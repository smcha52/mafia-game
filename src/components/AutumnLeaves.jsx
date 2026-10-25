import { useEffect, useState } from 'react';
import Box from '@mui/material/Box';
import { keyframes } from '@mui/material/styles';

// 단풍잎 모양 (24 x 24, 아래가 잎자루). 가을 프로필(ProfileAvatar)도 쓴다
export const MAPLE_LEAF = 'M12 1 L13.6 5 L15.5 4 L15 9 L18.5 6.5 L19.2 8.5 L23 8 L21.5 11.5 L23 12.5'
  + ' L18 16 L18.8 18 L13 17 L12.6 21 L12.6 23 L11.4 23 L11.4 21 L11 17 L5.2 18 L6 16'
  + ' L1 12.5 L2.5 11.5 L1 8 L4.8 8.5 L5.5 6.5 L9 9 L8.5 4 L10.4 5 Z';

const COLORS = ['#c62828', '#e53935', '#d84315', '#ef6c00', '#ff8f00', '#f9a825'];

// 새 잎을 띄우는 간격과 화면에 동시에 있을 수 있는 최대 개수
const EVERY = 700;
const MAX = 40;
// 바닥에 떨어진 뒤 사라질 때까지
const REST = 5;
const FADE = 0.6;

// 위에서 바닥까지 좌우로 흔들리며 돌면서 떨어진다. 잎마다 흔들림·회전을 변수로 준다
const fall = keyframes`
  0%   { transform: translate(0, -40px) rotate(0deg); }
  25%  { transform: translate(var(--sway), 25vh) rotate(calc(var(--spin) * 0.25)); }
  50%  { transform: translate(calc(var(--sway) * -1), 50vh) rotate(calc(var(--spin) * 0.5)); }
  75%  { transform: translate(var(--sway), 75vh) rotate(calc(var(--spin) * 0.75)); }
  100% { transform: translate(0, calc(100vh - var(--size))) rotate(var(--spin)); }
`;

const vanish = keyframes`
  to { opacity: 0; }
`;

let nextId = 0;

function makeLeaf() {
  const size = 14 + Math.random() * 12;
  return {
    id: nextId++,
    left: Math.random() * 100,
    size,
    color: COLORS[Math.floor(Math.random() * COLORS.length)],
    // 떨어지는 데 걸리는 시간 (초)
    duration: 7 + Math.random() * 5,
    sway: 20 + Math.random() * 40,
    spin: (Math.random() < 0.5 ? -1 : 1) * (180 + Math.random() * 360),
  };
}

function Leaf({ leaf }) {
  return (
    <Box
      component="svg"
      viewBox="0 0 24 24"
      sx={{
        position: 'absolute',
        top: 0,
        left: `${leaf.left}%`,
        width: leaf.size,
        height: leaf.size,
        opacity: 0.9,
        '--size': `${leaf.size}px`,
        '--sway': `${leaf.sway}px`,
        '--spin': `${leaf.spin}deg`,
        // 바닥에 닿으면 그대로 멈춰 있다가 REST 초 뒤에 흐려지며 사라진다
        animation: `${fall} ${leaf.duration}s ease-in forwards, `
          + `${vanish} ${FADE}s ease-in ${leaf.duration + REST}s forwards`,
      }}
    >
      <path d={MAPLE_LEAF} fill={leaf.color} />
    </Box>
  );
}

// 가을 배경 위로 단풍잎이 계속 떨어진다. 창 위에도 보이지만 누르는 것은 막지 않는다
export default function AutumnLeaves() {
  const [leaves, setLeaves] = useState([]);

  useEffect(() => {
    const timers = new Set();
    const spawn = setInterval(() => {
      // 백그라운드 탭에서는 쌓이기만 하므로 띄우지 않는다
      if (document.visibilityState !== 'visible') return;
      const leaf = makeLeaf();
      setLeaves((list) => (list.length >= MAX ? list : [...list, leaf]));
      const done = setTimeout(() => {
        timers.delete(done);
        setLeaves((list) => list.filter((l) => l.id !== leaf.id));
      }, (leaf.duration + REST + FADE) * 1000);
      timers.add(done);
    }, EVERY);

    return () => {
      clearInterval(spawn);
      timers.forEach(clearTimeout);
    };
  }, []);

  return (
    <Box
      aria-hidden="true"
      sx={{ position: 'fixed', inset: 0, zIndex: 'tooltip', pointerEvents: 'none', overflow: 'hidden' }}
    >
      {leaves.map((leaf) => <Leaf key={leaf.id} leaf={leaf} />)}
    </Box>
  );
}
