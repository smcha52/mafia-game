import { t } from './i18n';

// 방 설정(나이 · 레벨 제한)의 범위와 표시 문구. 서버 검사는 0044_room_options.sql
export const AGE_MIN = 0;
export const AGE_MAX = 25;
// 나이 범위 설정은 가입 화면 생년월일(1900-01-01~)로 나올 수 있는 나이까지 (0045)
export const AGE_RANGE_MAX = new Date().getFullYear() - 1900;
export const LEVEL_MIN = 5;
export const LEVEL_MAX = 50;

// 규칙을 짧은 문구로. 설정 안 함이면 빈 문자열
export function ruleLabel(mode, a, b, unit) {
  switch (mode) {
    case 'ALL':
      return t('전체');
    case 'PLUS':
      return t('{a}{unit} 이상', { a, unit: t(unit) });
    case 'MINUS':
      return t('{a}{unit} 미만', { a, unit: t(unit) });
    case 'RANGE':
      return t('{a}~{b}{unit}', { a, b, unit: t(unit) });
    default:
      return '';
  }
}
