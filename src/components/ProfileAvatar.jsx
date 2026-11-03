import Avatar from '@mui/material/Avatar';
import { MAPLE_LEAF } from './AutumnLeaves';
import { localized } from '../lib/i18n';

// 프로필마다 다른 하늘색 [위, 아래]
const SKIES = {
  CASTLE_PUMPKIN: ['#bf360c', '#ff9800'],
  CASTLE_GHOST: ['#5c6bc0', '#b0b0b8'],
  CASTLE_MAPLE: ['#b71c1c', '#ef5350'],
  CASTLE_GINKGO: ['#f9a825', '#fff176'],
};

// 하늘과 달. 할로윈·가을 프로필이 함께 쓴다
function Sky({ id }) {
  const [top, bottom] = SKIES[id];
  const gradient = `castle-sky-${id}`;
  return (
    <>
      <defs>
        <linearGradient id={gradient} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={top} />
          <stop offset="1" stopColor={bottom} />
        </linearGradient>
      </defs>
      <rect width="40" height="40" fill={`url(#${gradient})`} />
      <circle cx="30" cy="9" r="4.5" fill="#fff3b0" />
    </>
  );
}

function Pumpkin() {
  return (
    <>
      <rect x="19.2" y="21.5" width="1.6" height="3" rx="0.6" fill="#558b2f" />
      <ellipse cx="20" cy="30.5" rx="9" ry="7" fill="#f57c00" stroke="#3e1c00" strokeWidth="0.6" />
      <ellipse cx="20" cy="30.5" rx="4.5" ry="7" fill="#fb8c00" />
      <g fill="#3e1c00">
        <path d="M14 28 L16.5 28 L15.25 25.8 Z M23.5 28 L26 28 L24.75 25.8 Z" />
        <path d="M14 31.5 L16 33 L18 31.8 L20 33.4 L22 31.8 L24 33 L26 31.5 L24.5 35 L15.5 35 Z" />
      </g>
    </>
  );
}

// 글자 없는 묘비 두 개를 유령 양옆에 세운다
function Ghost() {
  return (
    <>
      <path
        d="M1 40 V34 a2.75 2.75 0 0 1 5.5 0 V40 Z M33.5 40 V35 a2.75 2.75 0 0 1 5.5 0 V40 Z"
        fill="#8a8a8a"
        stroke="#4a4a4a"
        strokeWidth="0.6"
      />
      <path
        d="M12.5 38 V28 a7.5 7.5 0 0 1 15 0 V38 l-2.5 -2.2 l-2.5 2.2 l-2.5 -2.2 l-2.5 2.2 l-2.5 -2.2 Z"
        fill="#f5f5f5"
      />
      <g fill="#1b1330">
        <ellipse cx="17.3" cy="28" rx="1.4" ry="1.9" />
        <ellipse cx="22.7" cy="28" rx="1.4" ry="1.9" />
        <ellipse cx="20" cy="32" rx="1.5" ry="1.1" />
      </g>
    </>
  );
}

// 단풍잎 한 장 (가을 프로필, 0070)
function Maple() {
  return (
    <g transform="translate(10.4 20.6) scale(0.8)">
      <path d={MAPLE_LEAF} fill="#e53935" stroke="#7f1010" strokeWidth="0.6" strokeLinejoin="round" />
    </g>
  );
}

// 부채꼴 은행잎 한 장 (가을 프로필, 0070)
function Ginkgo() {
  return (
    <>
      <path d="M20 31 L20 38" stroke="#8d6e00" strokeWidth="1.3" strokeLinecap="round" />
      <path
        d="M20 31.5 L11 23.5 Q12.5 19.6 17.4 19 L20 22.4 L22.6 19 Q27.5 19.6 29 23.5 Z"
        fill="#fdd835"
        stroke="#9e7b00"
        strokeWidth="0.6"
        strokeLinejoin="round"
      />
      <path d="M20 31 L15 22.5 M20 31 L20 23 M20 31 L25 22.5" stroke="#c9a400" strokeWidth="0.4" />
    </>
  );
}

// 상점에서 파는 프로필. id 는 서버 shop_items 와 1:1로 대응한다 (0051, 0070)
export const AVATARS = localized({
  CASTLE_PUMPKIN: { name: '호박 성', art: <Pumpkin /> },
  CASTLE_GHOST: { name: '유령 성', art: <Ghost /> },
  CASTLE_MAPLE: { name: '단풍잎 성', art: <Maple /> },
  CASTLE_GINKGO: { name: '은행잎 성', art: <Ginkgo /> },
});

// 프로필 그림. avatar 가 없거나 모르는 id 면 기본(닉네임 첫 글자)을 보여준다
export default function ProfileAvatar({ avatar = null, nickname = '', size = 36 }) {
  const item = AVATARS[avatar];
  if (!item) {
    return (
      <Avatar sx={{ bgcolor: 'primary.main', width: size, height: size, fontSize: size * 0.45, fontWeight: 700 }}>
        {Array.from(nickname)[0]}
      </Avatar>
    );
  }
  return (
    <Avatar sx={{ width: size, height: size }} aria-label={item.name}>
      <svg viewBox="0 0 40 40" width="100%" height="100%" aria-hidden="true">
        <Sky id={avatar} />
        {item.art}
      </svg>
    </Avatar>
  );
}
