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

// 15명이 안 된 대기실 방에 바로 입장한다
export async function quickJoin(nickname) {
  return unwrap(await supabase.rpc('quick_join', { p_nickname: nickname }));
}

// 들어갈 수 있는 대기실 10개. exclude 에 넣은 방은 빼고 준다
export async function listRooms(exclude = []) {
  return unwrap(await supabase.rpc('list_rooms', { p_exclude: exclude })) ?? [];
}

// 화면이 열려 있음을 알린다. 60초 넘게 오지 않으면 서버가 나간 것으로 처리한다
export async function heartbeat(roomId) {
  unwrap(await supabase.rpc('heartbeat', { p_room_id: roomId }));
}

export async function setReady(roomId, ready) {
  unwrap(await supabase.rpc('set_ready', { p_room_id: roomId, p_ready: ready }));
}

export async function leaveRoom(roomId) {
  unwrap(await supabase.rpc('leave_room', { p_room_id: roomId }));
}

// 방장이 대기실에서 참가자를 추방한다
export async function kickPlayer(roomId, targetUid) {
  unwrap(await supabase.rpc('kick_player', { p_room_id: roomId, p_target_uid: targetUid }));
}

// 방에서 빠졌을 때 추방당한 것인지 확인한다 (한 번만 true)
export async function takeKickNotice(roomId) {
  return unwrap(await supabase.rpc('take_kick_notice', { p_room_id: roomId }));
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

// 기자가 오늘 밤은 능력을 쓰지 않고 넘긴다 (대상 없이 제출)
export async function skipNightAction(roomId, action) {
  return unwrap(
    await supabase.rpc('submit_night_action', {
      p_room_id: roomId,
      p_action: action,
      p_target_uid: null,
    }),
  );
}

// 방장이 대기실에서 진행 설정을 바꾼다
export async function setTimers(roomId, night, day, maxDays) {
  return unwrap(
    await supabase.rpc('set_timers', {
      p_room_id: roomId,
      p_night: night,
      p_day: day,
      p_max_days: maxDays,
    }),
  );
}

// --- 채팅 ---

export async function sendChat(roomId, body) {
  return unwrap(await supabase.rpc('send_chat', { p_room_id: roomId, p_body: body }));
}

// RLS 가 걸러 준다. 밤 마피아 채팅은 마피아 진영에게만 내려온다.
export async function fetchChat(roomId) {
  return unwrap(
    await supabase
      .from('chat_messages')
      .select('*')
      .eq('room_id', roomId)
      .order('id', { ascending: true })
      .limit(200),
  );
}

// 종료된 방을 대기실로 되돌린다 (방장만)
export async function restartGame(roomId) {
  unwrap(await supabase.rpc('restart_game', { p_room_id: roomId }));
}

// --- 직업 켜기/끄기 ---

export async function setDisabledRoles(roomId, disabled) {
  unwrap(await supabase.rpc('set_disabled_roles', {
    p_room_id: roomId,
    p_disabled: disabled,
  }));
}

// 랜덤 구성 켜기/끄기 (방장만)
export async function setRandomRoles(roomId, on) {
  unwrap(await supabase.rpc('set_random_roles', {
    p_room_id: roomId,
    p_on: on,
  }));
}

// 랜덤 구성일 때 진영별 인원을 서버에 물어본다. max = 직업별 최대 인원 (0041)
export async function teamComposition(count, disabled, max = {}) {
  return unwrap(await supabase.rpc('team_composition', {
    p_count: count,
    p_disabled: disabled,
    p_max: max,
  }));
}

// 랜덤 구성에서 특수 직업의 최대 인원(1~3)을 정한다 (방장만)
export async function setRoleMax(roomId, role, max) {
  unwrap(await supabase.rpc('set_role_max', {
    p_room_id: roomId,
    p_role: role,
    p_max: max,
  }));
}

// 지금 인원과 설정으로 나오는 구성을 서버에 물어본다.
// 구성표를 화면에 또 적어두면 서버와 어긋날 수 있다.
export async function roleComposition(count, disabled) {
  return unwrap(await supabase.rpc('role_composition', {
    p_count: count,
    p_disabled: disabled,
  }));
}

// 암살 — 대상과 찍은 직업을 함께 보낸다
export async function submitAssassination(roomId, targetUid, guess) {
  return unwrap(await supabase.rpc('submit_assassination', {
    p_room_id: roomId,
    p_target_uid: targetUid,
    p_guess: guess,
  }));
}
