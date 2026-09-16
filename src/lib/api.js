import { supabase } from './supabase';

// Postgres 함수가 raise 한 한국어 메시지를 그대로 사용자에게 보여준다
function unwrap({ data, error }) {
  if (error) throw new Error(error.message);
  return data;
}

export async function createRoom(nickname) {
  return unwrap(await supabase.rpc('create_room', { p_nickname: nickname }));
}

export async function joinRoom(code, nickname) {
  return unwrap(await supabase.rpc('join_room', { p_code: code, p_nickname: nickname }));
}

export async function setReady(roomId, ready) {
  unwrap(await supabase.rpc('set_ready', { p_room_id: roomId, p_ready: ready }));
}

export async function leaveRoom(roomId) {
  unwrap(await supabase.rpc('leave_room', { p_room_id: roomId }));
}

export async function startGame(roomId) {
  unwrap(await supabase.rpc('start_game', { p_room_id: roomId }));
}

// 재접속 시 내가 아직 참가 중인 방이 있는지 확인한다
export async function myActiveRoom() {
  return unwrap(await supabase.rpc('my_active_room')) ?? null;
}

export async function fetchRoom(roomId) {
  return unwrap(
    await supabase.from('rooms').select('*').eq('id', roomId).maybeSingle(),
  );
}

export async function fetchPlayers(roomId) {
  return unwrap(
    await supabase
      .from('players')
      .select('*')
      .eq('room_id', roomId)
      .order('joined_at', { ascending: true }),
  );
}
