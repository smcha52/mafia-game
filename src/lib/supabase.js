import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

// .env 가 비어 있으면 앱이 흰 화면으로 죽지 않고 안내 화면을 띄운다
export const isConfigured = Boolean(url && anonKey);

export const supabase = isConfigured
  ? createClient(url, anonKey, {
      auth: {
        // 새로고침·재접속 시 로그인을 유지하기 위해 세션을 저장한다
        persistSession: true,
        autoRefreshToken: true,
      },
    })
  : null;

// 로그인 오류를 사용자에게 보여줄 한국어 문구로 바꾼다
function authMessage(error) {
  const m = error.message || '';
  if (m.includes('Invalid login credentials')) return '닉네임 또는 비밀번호가 맞지 않습니다.';
  if (m.includes('Password should be')) return '비밀번호는 6자 이상이어야 합니다.';
  if (m.includes('rate limit')) return '요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.';
  if (m.includes('Database error')) return '가입하지 못했습니다. 닉네임이 이미 쓰이고 있거나 생년월일이 올바르지 않습니다.';
  return m;
}

// 로그인한 사람의 프로필. 로그인하지 않았거나 프로필이 없으면 null
// tutorialDone 은 튜토리얼을 끝까지 한 번 마쳤는지 (계정 메타데이터)
export async function myProfile() {
  const { data } = await supabase.auth.getSession();
  const user = data.session?.user;
  if (!user || user.is_anonymous) return null;

  const { data: rows, error } = await supabase
    .from('profiles')
    // xp 는 0038 에서 생긴다. 적용 전이어도 로그인은 되도록 * 로 읽는다
    .select('*')
    .eq('uid', user.id);
  if (error) throw new Error(error.message);
  if (!rows[0]) return null;
  return { ...rows[0], xp: rows[0].xp ?? 0, tutorialDone: Boolean(user.user_metadata?.tutorial_done) };
}

// 튜토리얼을 끝까지 마쳤다고 계정에 남긴다. 다른 기기에서 로그인해도 유지된다
export async function markTutorialDone() {
  const { error } = await supabase.auth.updateUser({ data: { tutorial_done: true } });
  if (error) throw new Error(error.message);
}

// 닉네임·비밀번호·생년월일로 가입한다. 로그인용 이메일은 내부용으로 만든다 (0037)
export async function signUp(nickname, password, birth) {
  const { data: available, error: checkError } = await supabase.rpc('nickname_available', {
    p_nickname: nickname,
  });
  if (checkError) throw new Error(checkError.message);
  if (!available) throw new Error('이미 사용 중인 닉네임입니다.');

  const email = `${crypto.randomUUID().replaceAll('-', '')}@mafia-game.local`;
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: { data: { nickname, birth } },
  });
  if (error) throw new Error(authMessage(error));
  // 이메일 확인이 켜져 있으면 세션이 오지 않는다
  if (!data.session) throw new Error('가입은 됐지만 로그인하지 못했습니다. 이메일 확인 설정을 꺼 주세요.');
}

// 닉네임으로 로그인용 이메일을 찾아 로그인한다
export async function signIn(nickname, password) {
  const { data: email, error: findError } = await supabase.rpc('login_email', {
    p_nickname: nickname,
  });
  if (findError) throw new Error(findError.message);
  if (!email) throw new Error('닉네임 또는 비밀번호가 맞지 않습니다.');

  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw new Error(authMessage(error));
}

// --- 자동 로그아웃 ---
// 마지막 접속 시각을 이 브라우저에 남기고, 한 달(30일) 넘게 비어 있으면 로그아웃한다
const LAST_ACTIVE_KEY = 'mafia-game:lastActive';
const IDLE_LIMIT_MS = 30 * 24 * 60 * 60 * 1000;

// 지금 접속 중이라고 남긴다. 저장소를 쓸 수 없으면 자동 로그아웃만 되지 않는다
export function touchActive() {
  try {
    localStorage.setItem(LAST_ACTIVE_KEY, String(Date.now()));
  } catch {
    // 무시
  }
}

// 저장된 로그인이 한 달 넘게 쓰이지 않았으면 로그아웃한다. 로그아웃했으면 true
export async function expireIfIdle() {
  let last = null;
  try {
    last = Number(localStorage.getItem(LAST_ACTIVE_KEY)) || null;
  } catch {
    return false;
  }
  // 기록이 없으면(이 기능 이전 로그인) 지금부터 센다
  if (last === null || Date.now() - last <= IDLE_LIMIT_MS) return false;

  const { data } = await supabase.auth.getSession();
  if (!data.session) return false;
  await signOut();
  return true;
}

export async function signOut() {
  const { error } = await supabase.auth.signOut();
  if (error) throw new Error(error.message);
}
