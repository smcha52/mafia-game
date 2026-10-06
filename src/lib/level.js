// 레벨은 1~50. 레벨 n 에서 n+1 로 가려면 n×10 XP 가 필요하다 (0038_levels.sql)
export const MAX_LEVEL = 50;

// 레벨 L 이 되는 누적 XP
export const xpForLevel = (level) => 5 * level * (level - 1);

// 누적 XP -> 레벨과 이번 레벨 안에서의 진행
export function levelInfo(xp = 0) {
  let level = 1;
  while (level < MAX_LEVEL && xp >= xpForLevel(level + 1)) level += 1;

  if (level === MAX_LEVEL) return { level, current: 0, need: 0, max: true };
  return { level, current: xp - xpForLevel(level), need: level * 10, max: false };
}
