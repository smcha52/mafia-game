// 직업 표시 정보. 서버의 role 코드와 1:1로 대응한다.
export const ROLES = {
  CITIZEN:   { name: '시민',   emoji: '🧑', desc: '특별한 능력이 없습니다. 토론과 투표로 마피아를 찾아내세요.' },
  MAFIA:     { name: '마피아', emoji: '🔪', desc: '밤마다 동료들과 함께 제거할 대상을 고릅니다.' },
  POLICE:    { name: '경찰',   emoji: '🔎', desc: '밤마다 한 명의 진영을 조사합니다.' },
  DOCTOR:    { name: '의사',   emoji: '💉', desc: '밤마다 한 명을 치료해 죽음을 막습니다.' },
  BODYGUARD: { name: '경호원', emoji: '🛡️', desc: '보호 대상이 공격받으면 대신 사망합니다.' },
  DETECTIVE: { name: '탐정',   emoji: '🕵️', desc: '두 사람이 같은 진영인지 확인합니다.' },
  REPORTER:  { name: '기자',   emoji: '📰', desc: '단 한 번, 한 사람의 직업을 모두에게 공개합니다.' },
  MEDIUM:    { name: '영매',   emoji: '🔮', desc: '밤마다 사망자 한 명의 직업을 확인합니다.' },
  SPY:       { name: '스파이', emoji: '🎭', desc: '마피아 진영입니다. 낮 투표로 상대의 직업을 알아냅니다.' },
  JESTER:    { name: '광대',   emoji: '🤡', desc: '낮에 처형당하면 당신 혼자 승리합니다.' },
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
};

export const roleInfo = (code) => ROLES[code] ?? { name: code, emoji: '❓', desc: '' };

// 아직 능력이 구현되지 않은 직업 (§8.2 순서로 하나씩 열린다)
export const ABILITY_READY = new Set(['MAFIA']);
