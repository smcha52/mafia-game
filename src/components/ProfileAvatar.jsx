import Avatar from '@mui/material/Avatar';
import { localized } from '../lib/i18n';

// 밤하늘과 성. 할로윈 프로필이 함께 쓴다
function Castle() {
  return (
    <>
      <defs>
        <linearGradient id="castle-sky" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#2a1b54" />
          <stop offset="1" stopColor="#7a3f93" />
        </linearGradient>
      </defs>
      <rect width="40" height="40" fill="url(#castle-sky)" />
      <circle cx="30" cy="9" r="4.5" fill="#fff3b0" />
      <g fill="#150d2b">
        {/* 지붕 */}
        <path d="M6 14 L10 6 L14 14 Z M16 10 L20 2 L24 10 Z M26 14 L30 6 L34 14 Z" />
        {/* 탑과 성벽 */}
        <rect x="7" y="14" width="6" height="26" />
        <rect x="27" y="14" width="6" height="26" />
        <rect x="17" y="10" width="6" height="30" />
        <rect x="11" y="21" width="18" height="19" />
        {/* 성벽 위 톱니 */}
        <path d="M11 21 V18 H13.5 V21 Z M14.5 21 V18 H16.5 V21 Z M23.5 21 V18 H25.5 V21 Z M26.5 21 V18 H29 V21 Z" />
      </g>
      <g fill="#ffd54f">
        <rect x="9" y="17" width="2" height="3" rx="1" />
        <rect x="29" y="17" width="2" height="3" rx="1" />
        <rect x="19" y="13" width="2" height="3.5" rx="1" />
      </g>
    </>
  );
}

function Pumpkin() {
  return (
    <>
      <rect x="19.2" y="21.5" width="1.6" height="3" rx="0.6" fill="#558b2f" />
      <ellipse cx="20" cy="30.5" rx="9" ry="7" fill="#f57c00" />
      <ellipse cx="20" cy="30.5" rx="4.5" ry="7" fill="#fb8c00" />
      <g fill="#3e1c00">
        <path d="M14 28 L16.5 28 L15.25 25.8 Z M23.5 28 L26 28 L24.75 25.8 Z" />
        <path d="M14 31.5 L16 33 L18 31.8 L20 33.4 L22 31.8 L24 33 L26 31.5 L24.5 35 L15.5 35 Z" />
      </g>
    </>
  );
}

function Ghost() {
  return (
    <>
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

// 상점에서 파는 프로필. id 는 서버 shop_items 와 1:1로 대응한다 (0051)
export const AVATARS = localized({
  CASTLE_PUMPKIN: { name: '호박 성', art: <Pumpkin /> },
  CASTLE_GHOST: { name: '유령 성', art: <Ghost /> },
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
        <Castle />
        {item.art}
      </svg>
    </Avatar>
  );
}
