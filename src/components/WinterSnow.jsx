import { useEffect, useRef, useState } from 'react';
import Box from '@mui/material/Box';
import { keyframes } from '@mui/material/styles';

// 여섯 갈래 눈송이 (24 x 24)
const SNOWFLAKE = 'M12 1 V23 M2.5 6.5 L21.5 17.5 M2.5 17.5 L21.5 6.5'
  + ' M9.5 3 L12 5.5 L14.5 3 M9.5 21 L12 18.5 L14.5 21';

// 새 눈송이를 띄우는 간격과 한 번에 띄우는 개수(5 ~ 10개), 화면에 동시에 있을 수 있는 최대 개수
const EVERY = 700;
const BATCH_MIN = 5;
const BATCH_MAX = 10;
const MAX = 100;
// 최대 개수가 차면 모두 이만큼(초)에 걸쳐 흐려지며 사라지고, 그 뒤에 다시 내린다
const CLEAR = 5;

// 위에서 화면 아래 밖까지 좌우로 살랑이며 천천히 돈다
const fall = keyframes`
  0%   { transform: translate(0, -40px) rotate(0deg); }
  50%  { transform: translate(var(--sway), 50vh) rotate(calc(var(--spin) * 0.5)); }
  100% { transform: translate(0, calc(100vh + 40px)) rotate(var(--spin)); }
`;

let nextId = 0;

function makeFlake() {
  return {
    id: nextId++,
    left: Math.random() * 100,
    size: 12 + Math.random() * 12,
    // 떨어지는 데 걸리는 시간 (초)
    duration: 8 + Math.random() * 6,
    sway: (Math.random() < 0.5 ? -1 : 1) * (15 + Math.random() * 30),
    spin: (Math.random() < 0.5 ? -1 : 1) * (90 + Math.random() * 180),
  };
}

function Flake({ flake }) {
  return (
    <Box
      component="svg"
      viewBox="0 0 24 24"
      sx={{
        position: 'absolute',
        top: 0,
        left: `${flake.left}%`,
        width: flake.size,
        height: flake.size,
        opacity: 0.9,
        '--sway': `${flake.sway}px`,
        '--spin': `${flake.spin}deg`,
        animation: `${fall} ${flake.duration}s linear forwards`,
      }}
    >
      <path d={SNOWFLAKE} fill="none" stroke="#fff" strokeWidth="1.6" strokeLinecap="round" />
    </Box>
  );
}

// 겨울 배경 위로 눈송이가 떨어진다. 창 위에도 보이지만 누르는 것은 막지 않는다
export default function WinterSnow() {
  const [flakes, setFlakes] = useState([]);
  const [clearing, setClearing] = useState(false);
  const clearingRef = useRef(false);
  const resetRef = useRef(null);

  useEffect(() => {
    const timers = new Set();
    const spawn = setInterval(() => {
      // 백그라운드 탭에서는 쌓이기만 하므로, 사라지는 동안에는 다시 내리기 전이므로 띄우지 않는다
      if (document.visibilityState !== 'visible' || clearingRef.current) return;
      const count = BATCH_MIN + Math.floor(Math.random() * (BATCH_MAX - BATCH_MIN + 1));
      const batch = Array.from({ length: count }, makeFlake);
      setFlakes((list) => [...list, ...batch.slice(0, Math.max(0, MAX - list.length))]);
      batch.forEach((flake) => {
        const done = setTimeout(() => {
          timers.delete(done);
          setFlakes((list) => list.filter((f) => f.id !== flake.id));
        }, flake.duration * 1000);
        timers.add(done);
      });
    }, EVERY);

    return () => {
      clearInterval(spawn);
      timers.forEach(clearTimeout);
      clearTimeout(resetRef.current);
      clearingRef.current = false;
    };
  }, []);

  // 최대 개수가 차면 전부 흐리게 지운 뒤 처음부터 다시 내린다.
  // 흐려지는 동안 바닥에 닿은 눈송이가 빠져도 지우기가 끊기지 않도록 타이머는 ref 에 둔다
  useEffect(() => {
    if (flakes.length < MAX || clearingRef.current) return;
    clearingRef.current = true;
    setClearing(true);
    resetRef.current = setTimeout(() => {
      setFlakes([]);
      clearingRef.current = false;
      setClearing(false);
    }, CLEAR * 1000);
  }, [flakes.length]);

  return (
    <Box
      aria-hidden="true"
      sx={{
        position: 'fixed',
        inset: 0,
        zIndex: 'tooltip',
        pointerEvents: 'none',
        overflow: 'hidden',
        opacity: clearing ? 0 : 1,
        transition: clearing ? `opacity ${CLEAR}s linear` : 'none',
      }}
    >
      {flakes.map((flake) => <Flake key={flake.id} flake={flake} />)}
    </Box>
  );
}
