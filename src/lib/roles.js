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
  ASSASSIN:  { name: '저격수', emoji: '🎯', desc: '마피아 진영입니다. 상대의 직업을 맞히면 즉사시키고, 틀리면 당신이 죽습니다.' },
  KILLER:    { name: '살인자', emoji: '🪓', desc: '중립 진영입니다. 밤마다 혼자 한 명을 제거합니다. 누구와든 1:1이 되면 당신 혼자 승리합니다.' },
  VIGILANTE: { name: '자경단', emoji: '🏏', desc: '시민 진영입니다. 게임 중 단 한 번, 밤에 한 명을 제거할 수 있습니다.' },
  FORGER:    { name: '위조범', emoji: '🖋️', desc: '마피아 진영입니다. 동료와 함께 제거 대상을 고르고, 밤에 한 명을 위조하면 그 사람을 조사한 직업이 반대 진영으로 봅니다.' },
  SURVIVOR:  { name: '생존자', emoji: '🛟', desc: '중립 진영입니다. 능력은 없습니다. 목표 날의 낮이 끝날 때까지 살아 있으면 당신 혼자 승리합니다.' },
  SHERIFF:   { name: '보안관', emoji: '🤠', desc: '시민 진영입니다. 밤마다 한 명을 제거할 수 있습니다. 마피아·중립이면 대상만 죽지만, 시민을 쏘면 당신도 함께 죽습니다.' },
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
  SURVIVOR: { title: '생존자 단독 승리', emoji: '🛟', color: '#B388FF' },
  DRAW:    { title: '무승부', emoji: '🤝', color: 'text.secondary' },
};

// 게임 결과에서 이 사람이 이겼는지. 무승부면 null
// 시민·마피아 승리는 진영으로, 광대·살인자·생존자 단독 승리는 직업으로 판단한다
export function didWin(winner, role, team) {
  if (winner === 'DRAW') return null;
  if (winner === 'CITIZEN' || winner === 'MAFIA') return team === winner;
  return role === winner;
}

// 직업의 진영
export function roleTeam(code) {
  if (['MAFIA', 'SPY', 'ASSASSIN', 'FORGER'].includes(code)) return 'MAFIA';
  if (['JESTER', 'KILLER', 'SURVIVOR'].includes(code)) return 'NEUTRAL';
  return 'CITIZEN';
}

// 직업별 XP 얻는 법. 서버 base_xp() 와 일치해야 한다 (0038_levels.sql)
export const XP_RULES = {
  CITIZEN:   ['낮 투표가 끝날 때 살아 있으면 하루당 2 XP'],
  SURVIVOR:  ['낮 투표가 끝날 때 살아 있으면 하루당 2 XP'],
  POLICE:    ['조사한 사람이 시민 진영이면 1 XP', '중립이면 3 XP', '마피아 진영이면 5 XP'],
  DOCTOR:    ['공격받은 사람을 치료해 살리면 7 XP'],
  BODYGUARD: ['보호 대상 대신 죽어 공격을 막으면 5 XP', '그 밖에 보호할 때마다 1 XP'],
  DETECTIVE: ['조사할 때마다 3 XP'],
  REPORTER:  ['보도에 성공해 마피아 진영을 밝히면 5 XP', '그 밖의 보도 성공은 2 XP'],
  MEDIUM:    ['사망자를 조사할 때마다 2 XP', '자신이 죽으면 3 XP (한 번)'],
  VIGILANTE: ['쏜 대상이 그 밤에 죽으면 3 XP'],
  SHERIFF:   ['마피아·중립을 쏘면 10 XP', '시민 진영을 쏘면 1 XP'],
  MAFIA:     ['마피아 공격에 참여하고 대상이 죽으면 2 XP'],
  SPY:       ['마피아 공격에 참여하고 대상이 죽으면 2 XP', '투표로 직업을 알아낼 때마다 2 XP'],
  ASSASSIN:  ['저격에 성공하면 15 XP', '저격에 실패하면 2 XP'],
  FORGER:    ['다른 사람을 위조할 때마다 5 XP'],
  JESTER:    ['낮 투표에서 받은 1표당 2 XP'],
  KILLER:    ['쏜 대상이 그 밤에 죽으면 3 XP'],
};

export const roleInfo = (code) => ROLES[code] ?? { name: code, emoji: '❓', desc: '' };

// 능력이 구현된 직업 (§8.2 순서로 하나씩 열린다)
export const ABILITY_READY = new Set([
  'MAFIA', 'SPY', 'ASSASSIN', 'FORGER', 'POLICE', 'DOCTOR', 'BODYGUARD',
  'DETECTIVE', 'REPORTER', 'MEDIUM', 'KILLER', 'VIGILANTE', 'SHERIFF',
]);

// 저격수가 찍을 수 있는 직업 (전부)
export const ALL_ROLES = [
  'MAFIA', 'SPY', 'ASSASSIN', 'FORGER', 'POLICE', 'DOCTOR', 'BODYGUARD',
  'DETECTIVE', 'REPORTER', 'MEDIUM', 'JESTER', 'KILLER', 'SURVIVOR', 'VIGILANTE', 'SHERIFF', 'CITIZEN',
];

// 밤에 행동하는 직업 -> 서버가 받는 action 코드
export const NIGHT_ACTION = {
  MAFIA: 'MAFIA_VOTE',
  SPY: 'MAFIA_VOTE',
  ASSASSIN: 'MAFIA_VOTE',
  FORGER: 'MAFIA_VOTE',
  POLICE: 'POLICE',
  DOCTOR: 'DOCTOR',
  BODYGUARD: 'BODYGUARD',
  DETECTIVE: 'DETECTIVE',
  REPORTER: 'REPORTER',
  MEDIUM: 'MEDIUM',
  KILLER: 'KILLER',
  VIGILANTE: 'VIGILANTE',
  SHERIFF: 'SHERIFF',
};

// 밤 화면에서 보여줄 안내 문구
export const NIGHT_PROMPT = {
  MAFIA: '제거할 대상을 고르세요',
  SPY: '제거할 대상을 고르세요',
  ASSASSIN: '제거할 대상을 고르세요',
  FORGER: '제거할 대상을 고르세요',
  POLICE: '진영을 조사할 사람을 고르세요',
  DOCTOR: '치료할 사람을 고르세요',
  BODYGUARD: '보호할 사람을 고르세요',
  DETECTIVE: '직업을 추리할 사람을 고르세요',
  REPORTER: '취재할 사람을 고르세요',
  MEDIUM: '직업을 확인할 사망자를 고르세요',
  KILLER: '제거할 대상을 고르세요',
  VIGILANTE: '제거할 대상을 고르세요 (게임 중 한 번)',
  SHERIFF: '제거할 대상을 고르세요 (시민을 쏘면 함께 죽습니다)',
};

// 확정 버튼 문구
export const SUBMIT_LABEL = {
  MAFIA: '공격 확정',
  SPY: '공격 확정',
  ASSASSIN: '공격 확정',
  FORGER: '공격 확정',
  POLICE: '조사 확정',
  DOCTOR: '치료 확정',
  BODYGUARD: '보호 확정',
  DETECTIVE: '추리 확정',
  REPORTER: '취재 확정',
  MEDIUM: '교신 확정',
  KILLER: '제거 확정',
  VIGILANTE: '제거 확정',
  SHERIFF: '제거 확정',
};

// 제출 후 안내
export const SUBMITTED_NOTE = {
  MAFIA: ' 동료들을 기다리는 중입니다.',
  SPY: ' 동료들을 기다리는 중입니다.',
  ASSASSIN: ' 동료들을 기다리는 중입니다.',
  FORGER: ' 동료들을 기다리는 중입니다.',
  POLICE: ' 아침에 결과를 알려드립니다.',
  DOCTOR: ' 오늘 밤 공격을 막을 수 있습니다.',
  BODYGUARD: ' 공격받으면 당신이 대신 죽습니다.',
  DETECTIVE: ' 아침에 직업 후보를 알려드립니다.',
  REPORTER: ' 아침에 취재 결과가 나옵니다.',
  MEDIUM: ' 아침에 직업을 알려드립니다.',
  KILLER: ' 아침에 결과가 드러납니다.',
  VIGILANTE: ' 아침에 결과가 드러납니다. 이제 제거는 다시 할 수 없습니다.',
  SHERIFF: ' 아침에 결과가 드러납니다.',
};

// 대기실에서 끌 수 있는 직업. 서버 toggleable_roles() 와 일치해야 한다.
// 시민은 랜덤 구성에서만 끌 수 있다 (0040). 고정 구성에서는 끈 직업을 대체하는 자리다.
// 마피아는 끌 수 있다. 마피아 진영(마피아·스파이·저격수)이 0명이면 시작할 수 없다.
export const TOGGLEABLE = [
  'MAFIA', 'POLICE', 'DOCTOR', 'BODYGUARD', 'DETECTIVE', 'REPORTER', 'MEDIUM',
  'SPY', 'JESTER', 'ASSASSIN', 'KILLER', 'VIGILANTE', 'SHERIFF', 'FORGER', 'SURVIVOR', 'CITIZEN',
];

// 생존자의 목표 날. 서버 survivor_target() 과 일치해야 한다.
// 최대 일수가 2일 이하이면 null — 생존자를 넣을 수 없다.
export function survivorTarget(maxDays) {
  if (maxDays == null || maxDays < 3) return null;
  if (maxDays <= 4) return 2;
  return 4 + 2 * Math.floor((maxDays - 5) / 3);
}

// 살아 있는 사람이 아니라 사망자를 지목하는 직업
export const TARGETS_DEAD = new Set(['MEDIUM']);

// 게임 중 한 번만 쓸 수 있는 직업
export const ONE_SHOT = new Set(['REPORTER', 'VIGILANTE']);

// 대상 없이 "오늘은 사용하지 않기" 로 넘길 수 있는 직업
export const SKIPPABLE = new Set(['REPORTER', 'VIGILANTE', 'SHERIFF']);

// 1회용 능력을 다 쓴 뒤 밤마다 보여줄 문구
export const SPENT_NOTE = {
  VIGILANTE: '당신은 제거를 이미 했습니다.',
};

// 자신을 지목할 수 없는 직업
export const NO_SELF_TARGET = new Set(['MAFIA', 'SPY', 'ASSASSIN', 'FORGER', 'BODYGUARD', 'KILLER', 'VIGILANTE', 'SHERIFF']);

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
