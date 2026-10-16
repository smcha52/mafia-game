// 일일보상 상자 그림. box = TREASURE(보물상자) · PUMPKIN(호박상자, 할로윈) (0058)
// open 이면 뚜껑이 열린 모습

function Treasure({ open }) {
  return (
    <>
      {/* 몸통 */}
      <rect x="5" y="19" width="30" height="16" rx="2" fill="#8d5524" />
      <rect x="5" y="19" width="30" height="3" fill="#6d3f17" />
      <rect x="9" y="19" width="3" height="16" fill="#f5b301" />
      <rect x="28" y="19" width="3" height="16" fill="#f5b301" />
      <rect x="5" y="32" width="30" height="3" rx="1" fill="#f5b301" />
      {/* 뚜껑 */}
      {open ? (
        <>
          <path d="M5 19 L8 7 H32 L35 19 Z" fill="#6d3f17" />
          <ellipse cx="20" cy="19" rx="13" ry="3" fill="#ffe082" />
        </>
      ) : (
        <>
          <path d="M5 19 V14 a15 7 0 0 1 30 0 V19 Z" fill="#a0652e" />
          <rect x="9" y="8" width="3" height="11" fill="#f5b301" />
          <rect x="28" y="8" width="3" height="11" fill="#f5b301" />
        </>
      )}
      {/* 자물쇠 */}
      <rect x="17" y="17" width="6" height="7" rx="1.2" fill="#ffd54f" stroke="#8d6e00" strokeWidth="0.8" />
      <circle cx="20" cy="20.5" r="1" fill="#5d4037" />
    </>
  );
}

function PumpkinBox({ open }) {
  return (
    <>
      {/* 꼭지 */}
      {!open && <rect x="18.6" y="4" width="2.8" height="6" rx="1" fill="#558b2f" />}
      {/* 호박 몸통 */}
      <ellipse cx="20" cy="23" rx="16" ry="13" fill="#f57c00" />
      <ellipse cx="20" cy="23" rx="10" ry="13" fill="#fb8c00" />
      <ellipse cx="20" cy="23" rx="4" ry="13" fill="#ffa726" />
      {open ? (
        // 뚜껑이 열려 안이 빛난다
        <ellipse cx="20" cy="12" rx="10" ry="3.2" fill="#ffe082" />
      ) : (
        // 뚜껑 자리
        <path d="M11 13 Q20 17 29 13" stroke="#e65100" strokeWidth="1.2" fill="none" />
      )}
      {/* 얼굴 */}
      <g fill="#3e1c00">
        <path d="M11 22 L15 22 L13 18.5 Z M25 22 L29 22 L27 18.5 Z" />
        <path d="M10.5 26 L13.5 28.5 L17 26.5 L20 29 L23 26.5 L26.5 28.5 L29.5 26 L27 32 L13 32 Z" />
      </g>
    </>
  );
}

export const BOXES = {
  TREASURE: { name: '보물상자', Art: Treasure },
  PUMPKIN: { name: '호박상자', Art: PumpkinBox },
};

export default function BoxArt({ box, open = false, size = 32 }) {
  const item = BOXES[box] ?? BOXES.TREASURE;
  return (
    <svg viewBox="0 0 40 40" width={size} height={size} role="img" aria-label={item.name}>
      <item.Art open={open} />
    </svg>
  );
}
