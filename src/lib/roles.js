// 직업 표시 정보. 서버의 role 코드와 1:1로 대응한다.
export const ROLES = {
  CITIZEN:   { name: '시민',   emoji: '🧑', desc: '특별한 능력이 없습니다. 토론과 투표로 마피아를 찾아내세요.' },
  MAFIA:     { name: '마피아', emoji: '🔪', desc: '밤마다 동료들과 함께 제거할 대상을 고릅니다.' },
  POLICE:    { name: '경찰',   emoji: '🔎', desc: '밤마다 한 명의 진영을 조사합니다.' },
  DOCTOR:    { name: '의사',   emoji: '💉', desc: '밤마다 한 명을 치료해 죽음을 막습니다.' },
  BODYGUARD: { name: '경호원', emoji: '🛡️', desc: '보호 대상이 공격받으면 대신 사망합니다.' },
  DETECTIVE: { name: '탐정',   emoji: '🕵️', desc: '한 명의 직업 후보를 알아냅니다. 그중 하나만 진짜입니다.' },
  REPORTER:  { name: '기자',   emoji: '📰', desc: '단 한 번, 한 사람의 진영을 모두에게 공개합니다. 성공률은 절반입니다.' },
  MEDIUM:    { name: '영매',   emoji: '🔮', desc: '밤마다 사망자 한 명의 직업을 확인합니다.' },
  SPY:       { name: '스파이', emoji: '🎭', desc: '마피아 진영입니다. 낮에 투표한 사람의 직업을 반드시 알아냅니다.' },
  JESTER:    { name: '광대',   emoji: '🤡', desc: '낮에 처형당하면 당신 혼자 승리합니다.' },
  ASSASSIN:  { name: '암살자', emoji: '🎯', desc: '마피아 진영입니다. 상대의 직업을 맞히면 즉사시키고, 틀리면 당신이 죽습니다.' },
  KILLER:    { name: '살인자', emoji: '🪓', desc: '중립 진영입니다. 밤마다 혼자 한 명을 제거합니다. 누구와든 1:1이 되면 당신 혼자 승리합니다.' },
  VIGILANTE: { name: '자경단', emoji: '🤠', desc: '시민 진영입니다. 게임 중 단 한 번, 밤에 한 명을 제거할 수 있습니다.' },
};

export const TEAMS = {
  CITIZEN: { name: '시민 진영', color: 'info' },
  MAFIA:   { name: '마피아 진영', color: 'error' },
  NEUTRAL: { name: '중립 진영', color: 'warning' },
};

export const WINNERS = {
  CITIZEN: { title: '시민 진영 승리', emoji: '🎉', color: 'info.main' },
  MAFIA:   { title: '마피아 진영 승리', emoji: '🔪', color: 'error.main' },
  JESTER:  { title: '광대 단독 승리', emoji: '🤡', color: 'warning.main' },
  KILLER:  { title: '살인자 단독 승리', emoji: '🪓', color: 'warning.main' },
  DRAW:    { title: '무승부', emoji: '🤝', color: 'text.secondary' },
};

export const roleInfo = (code) => ROLES[code] ?? { name: code, emoji: '❓', desc: '' };

// 능력이 구현된 직업 (§8.2 순서로 하나씩 열린다)
export const ABILITY_READY = new Set([
  'MAFIA', 'SPY', 'ASSASSIN', 'POLICE', 'DOCTOR', 'BODYGUARD',
  'DETECTIVE', 'REPORTER', 'MEDIUM', 'KILLER', 'VIGILANTE',
]);

// 암살자가 찍을 수 있는 직업 (전부)
export const ALL_ROLES = [
  'MAFIA', 'SPY', 'ASSASSIN', 'POLICE', 'DOCTOR', 'BODYGUARD',
  'DETECTIVE', 'REPORTER', 'MEDIUM', 'JESTER', 'KILLER', 'VIGILANTE', 'CITIZEN',
];

// 밤에 행동하는 직업 -> 서버가 받는 action 코드
export const NIGHT_ACTION = {
  MAFIA: 'MAFIA_VOTE',
  SPY: 'MAFIA_VOTE',
  ASSASSIN: 'MAFIA_VOTE',
  POLICE: 'POLICE',
  DOCTOR: 'DOCTOR',
  BODYGUARD: 'BODYGUARD',
  DETECTIVE: 'DETECTIVE',
  REPORTER: 'REPORTER',
  MEDIUM: 'MEDIUM',
  KILLER: 'KILLER',
  VIGILANTE: 'VIGILANTE',
};

// 밤 화면에서 보여줄 안내 문구
export const NIGHT_PROMPT = {
  MAFIA: '제거할 대상을 고르세요',
  SPY: '제거할 대상을 고르세요',
  ASSASSIN: '제거할 대상을 고르세요',
  POLICE: '진영을 조사할 사람을 고르세요',
  DOCTOR: '치료할 사람을 고르세요',
  BODYGUARD: '보호할 사람을 고르세요',
  DETECTIVE: '직업을 추리할 사람을 고르세요',
  REPORTER: '취재할 사람을 고르세요',
  MEDIUM: '직업을 확인할 사망자를 고르세요',
  KILLER: '제거할 대상을 고르세요',
  VIGILANTE: '제거할 대상을 고르세요 (게임 중 한 번)',
};

// 확정 버튼 문구
export const SUBMIT_LABEL = {
  MAFIA: '공격 확정',
  SPY: '공격 확정',
  ASSASSIN: '공격 확정',
  POLICE: '조사 확정',
  DOCTOR: '치료 확정',
  BODYGUARD: '보호 확정',
  DETECTIVE: '추리 확정',
  REPORTER: '취재 확정',
  MEDIUM: '교신 확정',
  KILLER: '제거 확정',
  VIGILANTE: '제거 확정',
};

// 제출 후 안내
export const SUBMITTED_NOTE = {
  MAFIA: ' 동료들을 기다리는 중입니다.',
  SPY: ' 동료들을 기다리는 중입니다.',
  ASSASSIN: ' 동료들을 기다리는 중입니다.',
  POLICE: ' 아침에 결과를 알려드립니다.',
  DOCTOR: ' 오늘 밤 공격을 막을 수 있습니다.',
  BODYGUARD: ' 공격받으면 당신이 대신 죽습니다.',
  DETECTIVE: ' 아침에 직업 후보를 알려드립니다.',
  REPORTER: ' 아침에 취재 결과가 나옵니다.',
  MEDIUM: ' 아침에 직업을 알려드립니다.',
  KILLER: ' 아침에 결과가 드러납니다.',
  VIGILANTE: ' 아침에 결과가 드러납니다. 이제 제거는 다시 할 수 없습니다.',
};

// 대기실에서 끌 수 있는 직업. 서버 toggleable_roles() 와 일치해야 한다.
// 시민은 끌 수 없다 — 끈 직업을 대체하는 자리다.
// 마피아는 끌 수 있지만 꺼져 있으면 게임을 시작할 수 없다.
export const TOGGLEABLE = [
  'MAFIA', 'POLICE', 'DOCTOR', 'BODYGUARD', 'DETECTIVE', 'REPORTER', 'MEDIUM',
  'SPY', 'JESTER', 'ASSASSIN', 'KILLER', 'VIGILANTE',
];

// 살아 있는 사람이 아니라 사망자를 지목하는 직업
export const TARGETS_DEAD = new Set(['MEDIUM']);

// 게임 중 한 번만 쓸 수 있는 직업
export const ONE_SHOT = new Set(['REPORTER', 'VIGILANTE']);

// 1회용 능력을 다 쓴 뒤 밤마다 보여줄 문구
export const SPENT_NOTE = {
  VIGILANTE: '당신은 제거를 이미 했습니다.',
};

// 자신을 지목할 수 없는 직업
export const NO_SELF_TARGET = new Set(['MAFIA', 'SPY', 'ASSASSIN', 'BODYGUARD', 'KILLER', 'VIGILANTE']);

// 같은 사람을 연속으로 지목할 수 없는 직업 -> 화면에 표시할 사유
export const REPEAT_BLOCKED = {
  DOCTOR: '어젯밤에 치료함',
  BODYGUARD: '어젯밤에 보호함',
};

// 경찰 조사 결과 표시
export const TEAM_RESULT = {
  CITIZEN: { label: '시민 진영', color: 'info' },
  MAFIA: { label: '마피아 진영', color: 'error' },
  NEUTRAL: { label: '중립 진영', color: 'warning' },
};
