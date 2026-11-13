import { roleInfo } from '../lib/roles';

// 글자마다 색이 다른 직업 이름. 산타는 '산' 흰색, '타' 빨간색 (다른 언어는 앞 절반 / 뒤 절반)
const SPLIT_COLOR = {
  SANTA: ['#FFFFFF', '#E53935'],
};

// 색을 나눠 칠하는 직업이면 이름을 두 색으로, 아니면 그냥 이름을 돌려준다
export default function RoleName({ code }) {
  const name = roleInfo(code).name;
  const colors = SPLIT_COLOR[code];
  if (!colors) return name;
  const chars = Array.from(name);
  const half = Math.ceil(chars.length / 2);
  return (
    <>
      <span style={{ color: colors[0] }}>{chars.slice(0, half).join('')}</span>
      <span style={{ color: colors[1] }}>{chars.slice(half).join('')}</span>
    </>
  );
}

// 두 색으로 칠하는 직업인지
export const hasSplitColor = (code) => Boolean(SPLIT_COLOR[code]);
