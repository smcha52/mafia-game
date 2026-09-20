// 직업별 캐릭터. 64x64 기준으로 그리고 size 로 키운다.
// 이모지 대신 쓰면 어느 기기에서나 같은 모양으로 보인다.

const SKIN = '#E8B98F';
const SKIN_DARK = '#C99A72';

// 직업별 바탕색
const BG = {
  CITIZEN: '#5A6B8C', MAFIA: '#7A2E2E', POLICE: '#2E4A7A', DOCTOR: '#2E6B5E',
  BODYGUARD: '#4A4A52', DETECTIVE: '#6B5433', REPORTER: '#7A5A2E', MEDIUM: '#5A3A7A',
  SPY: '#3A3A4E', JESTER: '#8C4A7A', ASSASSIN: '#5A1E1E',
};

function Head({ y = 30 }) {
  return (
    <>
      <path d={`M22 ${y + 16} q10 -6 20 0 v8 h-20 z`} fill={SKIN_DARK} />
      <circle cx="32" cy={y} r="12" fill={SKIN} />
    </>
  );
}

const EYES = (
  <>
    <circle cx="27.5" cy="29" r="1.6" fill="#2B2B33" />
    <circle cx="36.5" cy="29" r="1.6" fill="#2B2B33" />
  </>
);

const SHADES = (
  <>
    <rect x="21" y="26.5" width="22" height="5.5" rx="2.5" fill="#15151C" />
    <rect x="20" y="27.5" width="24" height="1.4" fill="#15151C" />
  </>
);

// 각 직업의 모자·소품
const PARTS = {
  CITIZEN: (
    <>
      <path d="M20 26 q12 -14 24 0 q-12 -6 -24 0z" fill="#4A3A2E" />
      <Head />
      {EYES}
    </>
  ),

  MAFIA: (
    <>
      <Head />
      {SHADES}
      {/* 페도라 */}
      <ellipse cx="32" cy="22" rx="19" ry="4" fill="#1C1C22" />
      <path d="M22 22 q0 -12 10 -12 q10 0 10 12z" fill="#2A2A32" />
      <rect x="22" y="18" width="20" height="3.5" fill="#8C2B2B" />
      {/* 넥타이 */}
      <path d="M32 46 l3 4 -3 8 -3 -8z" fill="#8C2B2B" />
    </>
  ),

  POLICE: (
    <>
      <Head />
      {EYES}
      <ellipse cx="32" cy="23" rx="16" ry="3.5" fill="#16233C" />
      <path d="M23 23 q0 -11 9 -11 q9 0 9 11z" fill="#1E3054" />
      <path d="M32 14 l2.4 4.6 -2.4 1.4 -2.4 -1.4z" fill="#E8C35A" />
      <rect x="40" y="44" width="6" height="6" rx="1" fill="#E8C35A" />
    </>
  ),

  DOCTOR: (
    <>
      <path d="M20 26 q12 -12 24 0 q-12 -5 -24 0z" fill="#3A3A42" />
      <Head />
      {EYES}
      {/* 청진기 */}
      <path d="M25 46 q-4 10 5 12 q9 -2 5 -12" fill="none" stroke="#D8DDE4" strokeWidth="2.4" />
      <circle cx="35" cy="59" r="3.4" fill="#D8DDE4" />
      <rect x="27" y="44" width="10" height="4" fill="#F2F4F7" />
    </>
  ),

  BODYGUARD: (
    <>
      <path d="M21 25 q11 -11 22 0 q-11 -5 -22 0z" fill="#23232A" />
      <Head />
      {SHADES}
      {/* 이어피스 */}
      <path d="M43 30 q4 2 3 8" fill="none" stroke="#C8CCD4" strokeWidth="1.8" />
      <circle cx="43" cy="30" r="2" fill="#C8CCD4" />
      <path d="M40 44 l8 3 v6 q0 5 -8 8 q-8 -3 -8 -8z" fill="#5A7FA8" opacity="0.9" />
    </>
  ),

  DETECTIVE: (
    <>
      <Head />
      {EYES}
      {/* 디어스토커 */}
      <path d="M19 24 q13 -13 26 0 z" fill="#6B5433" />
      <path d="M19 24 q-4 2 -1 5 q5 -1 6 -5z" fill="#57462C" />
      <path d="M45 24 q4 2 1 5 q-5 -1 -6 -5z" fill="#57462C" />
      {/* 돋보기 */}
      <circle cx="44" cy="50" r="6" fill="none" stroke="#D8DDE4" strokeWidth="2.4" />
      <path d="M40 54 l-5 5" stroke="#8C6B3A" strokeWidth="3" strokeLinecap="round" />
    </>
  ),

  REPORTER: (
    <>
      <Head />
      {EYES}
      <path d="M20 25 q12 -11 24 0 q-12 -5 -24 0z" fill="#3A2E23" />
      {/* PRESS 카드 */}
      <rect x="20" y="46" width="13" height="9" rx="1.5" fill="#F2F4F7" />
      <rect x="22" y="49" width="9" height="1.6" fill="#7A5A2E" />
      <rect x="22" y="52" width="6" height="1.4" fill="#A89478" />
      {/* 마이크 */}
      <rect x="40" y="44" width="5" height="9" rx="2.5" fill="#D8DDE4" />
      <path d="M42.5 53 v5" stroke="#8A8F98" strokeWidth="2" />
    </>
  ),

  MEDIUM: (
    <>
      <Head />
      {EYES}
      {/* 두건 */}
      <path d="M18 32 q0 -18 14 -18 q14 0 14 18 q-6 -10 -14 -10 q-8 0 -14 10z" fill="#4A2E6B" />
      {/* 수정구 */}
      <circle cx="32" cy="53" r="7" fill="#9B7FD4" opacity="0.85" />
      <circle cx="29.5" cy="50.5" r="2.2" fill="#E4D8F7" opacity="0.9" />
    </>
  ),

  SPY: (
    <>
      <path d="M21 25 q11 -11 22 0 q-11 -5 -22 0z" fill="#2A2A33" />
      <Head />
      {SHADES}
      {/* 트렌치코트 깃 */}
      <path d="M22 46 l10 5 -4 11 h-8 z" fill="#4A4A58" />
      <path d="M42 46 l-10 5 4 11 h8 z" fill="#3A3A46" />
    </>
  ),

  ASSASSIN: (
    <>
      <Head />
      {SHADES}
      {/* 후드 */}
      <path d="M17 33 q0 -19 15 -19 q15 0 15 19 q-5 -11 -15 -11 q-10 0 -15 11z" fill="#241014" />
      <path d="M17 33 q3 6 6 8 l-2 -12z" fill="#1A0B0E" />
      <path d="M47 33 q-3 6 -6 8 l2 -12z" fill="#1A0B0E" />
      {/* 조준경 */}
      <circle cx="45" cy="47" r="7.5" fill="none" stroke="#D94A4A" strokeWidth="2" />
      <path d="M45 39.5 v15 M37.5 47 h15" stroke="#D94A4A" strokeWidth="1.4" />
      <circle cx="45" cy="47" r="1.6" fill="#D94A4A" />
    </>
  ),

  JESTER: (
    <>
      <Head />
      {EYES}
      <circle cx="32" cy="34" r="3" fill="#D94A4A" />
      {/* 광대 모자 */}
      <path d="M20 26 q12 -14 24 0 z" fill="#8C4A7A" />
      <path d="M20 26 q-8 -8 -6 -16 q6 4 9 10z" fill="#C4649B" />
      <path d="M44 26 q8 -8 6 -16 q-6 4 -9 10z" fill="#C4649B" />
      <circle cx="13" cy="9" r="3" fill="#E8C35A" />
      <circle cx="51" cy="9" r="3" fill="#E8C35A" />
    </>
  ),
};

export default function RoleAvatar({ role, size = 48, hidden = false }) {
  const bg = hidden ? '#3A3A44' : (BG[role] ?? '#4A4A55');

  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 64 64"
      role="img"
      aria-label={role ?? '알 수 없는 직업'}
      style={{ display: 'block', borderRadius: '50%' }}
    >
      <circle cx="32" cy="32" r="32" fill={bg} />
      {hidden || !PARTS[role] ? (
        <text
          x="32" y="44" textAnchor="middle"
          fontSize="30" fontWeight="700" fill="#9A9AA6"
        >
          ?
        </text>
      ) : (
        PARTS[role]
      )}
    </svg>
  );
}
