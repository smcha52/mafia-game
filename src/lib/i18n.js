import { createElement, Fragment, useSyncExternalStore } from 'react';

import en from './locales/en';
import ja from './locales/ja';
import zh from './locales/zh';

// 화면 언어. 로그인(회원가입) 화면에서 고르고, 이 브라우저에 남겨 다음에도 쓴다.
// 문구는 한국어 원문을 그대로 키로 쓴다. 번역이 없으면 한국어가 나온다.
const LANG_KEY = 'mafia-game:lang';

export const LANGS = [
  { code: 'ko', label: '한국어' },
  { code: 'en', label: 'English' },
  { code: 'ja', label: '日本語' },
  { code: 'zh', label: '中文' },
];

// 언어별 { words: { 한국어: 번역 }, patterns: [[정규식, 번역]] }
// patterns 는 서버가 숫자 등을 넣어 보내는 오류 문구용이다
const DICTS = { en, ja, zh };

function loadLang() {
  try {
    const saved = localStorage.getItem(LANG_KEY);
    if (LANGS.some((l) => l.code === saved)) return saved;
  } catch {
    // 저장소를 쓸 수 없으면 한국어로 시작한다
  }
  return 'ko';
}

let current = loadLang();
const listeners = new Set();
document.documentElement.lang = current;

export function getLang() {
  return current;
}

export function setLang(code) {
  if (code === current) return;
  current = code;
  document.documentElement.lang = code;
  try {
    localStorage.setItem(LANG_KEY, code);
  } catch {
    // 저장하지 못하면 다음에 한국어로 시작할 뿐이다
  }
  listeners.forEach((fn) => fn());
}

function subscribe(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

// 지금 언어. 언어가 바뀌면 이 훅을 쓴 컴포넌트(와 그 아래 전부)가 다시 그려진다
export function useLang() {
  return useSyncExternalStore(subscribe, getLang, getLang);
}

function lookup(ko) {
  const dict = DICTS[current];
  if (!dict) return ko;
  if (Object.hasOwn(dict.words, ko)) return dict.words[ko];
  for (const [re, out] of dict.patterns ?? []) {
    if (re.test(ko)) return ko.replace(re, out);
  }
  return ko;
}

// 한국어 문구를 지금 언어로 바꾼다.
// {이름} 자리에 vars 값을 넣고, **굵게** 는 <strong> 으로 그린다.
// vars 에 화면 요소를 넣거나 **굵게** 가 있으면 화면에 바로 쓸 수 있는 배열을 돌려준다
export function t(ko, vars) {
  if (typeof ko !== 'string') return ko;
  const text = lookup(ko);
  const parts = text.split(/(\{\w+\}|\*\*[^*]+\*\*)/).filter((p) => p !== '');
  const filled = parts.map((p) => {
    const name = p.match(/^\{(\w+)\}$/)?.[1];
    if (name && vars && name in vars) return vars[name];
    if (p.startsWith('**') && p.endsWith('**')) return createElement('strong', null, p.slice(2, -2));
    return p;
  });
  if (filled.every((p) => typeof p === 'string' || typeof p === 'number')) return filled.join('');
  return filled.map((p, i) => createElement(Fragment, { key: i }, p));
}

// 문구 표(직업 이름 등)의 글자를 읽을 때마다 지금 언어로 바꿔 준다
export function localized(table) {
  return new Proxy(table, {
    get(target, key) {
      const value = target[key];
      if (typeof value === 'string') return t(value);
      // 화면 요소(아이콘 등)는 그대로 둔다
      if (value && typeof value === 'object' && !value.$$typeof) return localized(value);
      return value;
    },
  });
}
