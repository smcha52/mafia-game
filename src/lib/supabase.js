import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

// .env 가 비어 있으면 앱이 흰 화면으로 죽지 않고 안내 화면을 띄운다
export const isConfigured = Boolean(url && anonKey);

export const supabase = isConfigured
  ? createClient(url, anonKey, {
      auth: {
        // 새로고침·재접속 시 같은 uid 를 유지하기 위해 세션을 저장한다
        persistSession: true,
        autoRefreshToken: true,
      },
    })
  : null;

// 익명 로그인. 이미 세션이 있으면 그대로 재사용한다.
export async function ensureSession() {
  const { data } = await supabase.auth.getSession();
  if (data.session) return data.session;

  const { data: created, error } = await supabase.auth.signInAnonymously();
  if (error) throw error;
  return created.session;
}
