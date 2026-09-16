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

// --- 게임 진행 ---

// 내 직업과 내가 제출한 행동만 담긴 화면용 정보 (남의 정보는 포함되지 않는다)
export async function myGameView(roomId) {
  return unwrap(await supabase.rpc('my_game_view', { p_room_id: roomId }));
}

export async function submitNightAction(roomId, action, targetUid) {
  return unwrap(
    await supabase.rpc('submit_night_action', {
      p_room_id: roomId,
      p_action: action,
      p_target_uid: targetUid,
    }),
  );
}

export async function submitDayVote(roomId, targetUid) {
  return unwrap(
    await supabase.rpc('submit_day_vote', { p_room_id: roomId, p_target_uid: targetUid }),
  );
}

export async function finalRoles(roomId) {
  return unwrap(await supabase.rpc('final_roles', { p_room_id: roomId }));
}

export async function fetchResults(roomId) {
  return unwrap(
    await supabase
      .from('public_results')
      .select('*')
      .eq('room_id', roomId)
      .order('day_number', { ascending: true }),
  );
}

// 마감 시각이 지났는지 서버에 확인시킨다. 지났으면 서버가 페이즈를 넘긴다.
export async function tickPhase(roomId) {
  return unwrap(await supabase.rpc('tick_phase', { p_room_id: roomId }));
}
