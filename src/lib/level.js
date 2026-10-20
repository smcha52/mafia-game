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

// 연승 보너스(%). 2연승 +10% … 11연승부터 +100%(2배). 서버 streak_bonus() 와 일치해야 한다 (0062_win_streak.sql)
export function streakBonus(streak = 0) {
  return streak >= 2 ? Math.min(100, (streak - 1) * 10) : 0;
}
