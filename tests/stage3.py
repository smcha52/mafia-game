"""
§8.2-10  전체 직업 조합과 승리 조건 테스트

개별 직업은 stage2 에서 검증했다. 여기서는 직업들이 서로 얽혔을 때를 본다.
  · 5~15명 11개 구성 전부에서 배정이 구성표와 일치하는가
  · 9개 능력이 같은 밤에 동시에 작동해도 §3 순서가 지켜지는가
  · 세 가지 승리 경로(시민·마피아·광대)에 모두 도달하는가
  · 게임이 무한히 이어지지 않고 끝나는가
"""

from harness import check, msg, req, rpc, user_pool
from stage2 import _pick, alive_uids, make_game, pass_day, pass_night, uid_map

# §5 인원별 기본 직업 구성. 서버의 role_composition() 과 일치해야 한다.
ROLE_TABLE = {
    5:  ['MAFIA', 'POLICE', 'DOCTOR', 'CITIZEN', 'CITIZEN'],
    6:  ['MAFIA', 'POLICE', 'DOCTOR', 'BODYGUARD', 'CITIZEN', 'CITIZEN'],
    7:  ['MAFIA', 'MAFIA', 'POLICE', 'DOCTOR', 'JESTER', 'CITIZEN', 'CITIZEN'],
    8:  ['MAFIA', 'MAFIA', 'POLICE', 'DOCTOR', 'BODYGUARD', 'JESTER',
         'CITIZEN', 'CITIZEN'],
    9:  ['MAFIA', 'MAFIA', 'SPY', 'POLICE', 'DOCTOR', 'DETECTIVE',
         'CITIZEN', 'CITIZEN', 'CITIZEN'],
    10: ['MAFIA', 'MAFIA', 'SPY', 'POLICE', 'DOCTOR', 'BODYGUARD', 'DETECTIVE',
         'CITIZEN', 'CITIZEN', 'CITIZEN'],
    11: ['MAFIA', 'MAFIA', 'SPY', 'POLICE', 'DOCTOR', 'BODYGUARD', 'DETECTIVE',
         'REPORTER', 'CITIZEN', 'CITIZEN', 'CITIZEN'],
    12: ['MAFIA', 'MAFIA', 'MAFIA', 'SPY', 'POLICE', 'DOCTOR', 'BODYGUARD',
         'DETECTIVE', 'REPORTER', 'JESTER', 'CITIZEN', 'CITIZEN'],
    13: ['MAFIA', 'MAFIA', 'MAFIA', 'SPY', 'POLICE', 'DOCTOR', 'BODYGUARD',
         'DETECTIVE', 'REPORTER', 'MEDIUM', 'JESTER', 'CITIZEN', 'CITIZEN'],
    14: ['MAFIA', 'MAFIA', 'MAFIA', 'SPY', 'POLICE', 'DOCTOR', 'BODYGUARD',
         'DETECTIVE', 'REPORTER', 'MEDIUM', 'JESTER',
         'CITIZEN', 'CITIZEN', 'CITIZEN'],
    15: ['MAFIA', 'MAFIA', 'MAFIA', 'SPY', 'POLICE', 'DOCTOR', 'BODYGUARD',
         'DETECTIVE', 'REPORTER', 'MEDIUM', 'JESTER',
         'CITIZEN', 'CITIZEN', 'CITIZEN', 'CITIZEN'],
}


def team_of(role):
    if role in ("MAFIA", "SPY"):
        return "MAFIA"
    if role == "JESTER":
        return "NEUTRAL"
    return "CITIZEN"


def pick_alive(roles, uids, alive, team):
    """살아 있는 사람 중 해당 진영 한 명의 uid"""
    for t, r in roles.items():
        if uids[t] in alive and team_of(r["role"]) == team:
            return uids[t]
    return None


# ------------------------------------------------------------------
# 1. 11개 구성 전부에서 배정이 구성표와 일치하는가 (§5)
# ------------------------------------------------------------------

def test_all_compositions():
    from collections import Counter

    bad = []
    for n in range(5, 16):
        toks, room_id, roles = make_game(n)
        if not room_id:
            bad.append("%d명: 방 생성 실패" % n)
            continue

        got = Counter(r["role"] for r in roles.values())
        want = Counter(ROLE_TABLE[n])
        if got != want:
            bad.append("%d명: %s" % (n, dict(got)))
        elif len(roles) != n:
            bad.append("%d명: %d명만 배정" % (n, len(roles)))

        rpc("leave_room", toks[0], {"p_room_id": room_id})

    check("5~15명 전 구성 배정 일치 (§5)", not bad, "; ".join(bad) if bad else "11개 구성 모두 일치")


# ------------------------------------------------------------------
# 2. 9개 능력이 같은 밤에 동시에 작동 (§3 순서)
# ------------------------------------------------------------------

def test_all_abilities_same_night():
    toks, room_id, roles = make_game(15)
    if not room_id:
        check("15명 동시 능력 준비", False, "방 생성 실패")
        return
    uids = uid_map(roles)

    mafias = [t for t, r in roles.items() if r["role"] == "MAFIA"]
    spy = _pick(roles, "SPY")
    police = _pick(roles, "POLICE")
    doctor = _pick(roles, "DOCTOR")
    guard = _pick(roles, "BODYGUARD")
    det = _pick(roles, "DETECTIVE")
    rep = _pick(roles, "REPORTER")
    med = _pick(roles, "MEDIUM")
    citizens = [t for t, r in roles.items() if r["role"] == "CITIZEN"]
    victim = citizens[0]

    # 영매는 사망자가 없어 제출할 수 없다 (§2.8).
    # 밤이 끝나기 전에 먼저 시도해야 올바른 오류를 확인할 수 있다.
    s, b = rpc("submit_night_action", med,
               {"p_room_id": room_id, "p_action": "MEDIUM", "p_target_uid": uids[citizens[1]]})
    check("15명 밤: 영매는 1일차에 못 쓴다",
          s >= 400 and "사망한 참가자만" in str(msg(b)), msg(b))

    # 마피아 3 + 스파이 1 이 같은 사람을 공격
    for t in mafias + [spy]:
        rpc("submit_night_action", t,
            {"p_room_id": room_id, "p_action": "MAFIA_VOTE", "p_target_uid": uids[victim]})

    # 의사와 경호원이 같은 대상에 겹친다 (§3.1)
    rpc("submit_night_action", doctor,
        {"p_room_id": room_id, "p_action": "DOCTOR", "p_target_uid": uids[victim]})
    rpc("submit_night_action", guard,
        {"p_room_id": room_id, "p_action": "BODYGUARD", "p_target_uid": uids[victim]})

    rpc("submit_night_action", police,
        {"p_room_id": room_id, "p_action": "POLICE", "p_target_uid": uids[mafias[0]]})
    rpc("submit_night_action", det,
        {"p_room_id": room_id, "p_action": "DETECTIVE", "p_target_uid": uids[spy]})
    s, last = rpc("submit_night_action", rep,
                  {"p_room_id": room_id, "p_action": "REPORTER", "p_target_uid": uids[mafias[1]]})

    s, r = req("/rest/v1/rooms?select=phase&id=eq." + room_id, police)
    check("8개 능력 제출로 밤 종료", bool(r) and r[0]["phase"] == "DAY",
          r[0]["phase"] if r else "?")

    # §3.1 — 치료가 우선이므로 대상도 경호원도 살아야 한다
    s, pl = req("/rest/v1/players?select=uid,alive&room_id=eq." + room_id, police)
    alive = {p["uid"]: p["alive"] for p in pl} if isinstance(pl, list) else {}
    check("§3.1 치료 우선: 대상 생존", alive.get(uids[victim]) is True,
          str(alive.get(uids[victim])))
    check("§3.1 치료 우선: 경호원 생존", alive.get(uids[guard]) is True,
          str(alive.get(uids[guard])))
    check("사망자 없음", sum(1 for a in alive.values() if not a) == 0,
          "사망 %d명" % sum(1 for a in alive.values() if not a))

    # 각 직업이 자기 결과만 받았는가
    def kinds(tok):
        s2, v = rpc("my_game_view", tok, {"p_room_id": room_id})
        return sorted({x["kind"] for x in (v.get("privateResults") or [])})

    check("경찰 결과만 경찰에게", kinds(police) == ["POLICE"], str(kinds(police)))
    check("의사 결과만 의사에게", kinds(doctor) == ["DOCTOR"], str(kinds(doctor)))
    check("경호원 결과만 경호원에게", kinds(guard) == ["BODYGUARD"], str(kinds(guard)))
    check("탐정 결과만 탐정에게", kinds(det) == ["DETECTIVE"], str(kinds(det)))
    check("기자 결과만 기자에게", kinds(rep) == ["REPORTER"], str(kinds(rep)))
    check("시민은 아무 결과도 없다", kinds(citizens[2]) == [], str(kinds(citizens[2])))

    # 15명이므로 탐정 후보는 3개
    s, v = rpc("my_game_view", det, {"p_room_id": room_id})
    dres = [x for x in (v.get("privateResults") or []) if x["kind"] == "DETECTIVE"]
    cands = dres[0]["payload"]["candidates"] if dres else []
    check("15명 탐정 후보 3개", len(cands) == 3, str(cands))
    check("15명 탐정 후보에 진짜 포함", "SPY" in cands, str(cands))

    rpc("leave_room", toks[0], {"p_room_id": room_id})


# ------------------------------------------------------------------
# 3. 게임을 끝까지 진행해 승리 경로에 도달하는가
# ------------------------------------------------------------------

def play_to_end(room_id, roles, uids, execute_team, max_rounds=30):
    """매 낮 execute_team 진영을 한 명씩 처형하며 끝까지 진행한다.
    돌려주는 값: 승자 문자열, 또는 'TIMEOUT'
    """
    any_tok = next(iter(roles))
    for _ in range(max_rounds):
        s, r = req("/rest/v1/rooms?select=phase,winner&id=eq." + room_id, any_tok)
        if not r:
            return "NO_ROOM"
        if r[0]["phase"] == "ENDED":
            return r[0]["winner"]

        alive = alive_uids(room_id, any_tok)
        if r[0]["phase"] == "NIGHT":
            victim = pick_alive(roles, uids, alive, "CITIZEN")
            # 의사·경호원이 공격 대상에 겹치지 않도록 마피아 쪽으로 돌린다
            aside = pick_alive(roles, uids, alive, "MAFIA")
            pass_night(room_id, roles, uids, victim_uid=victim,
                       doctor_uid=aside, guard_uid=aside)
        else:
            target = pick_alive(roles, uids, alive, execute_team)
            if target is None:
                return "NO_TARGET"
            pass_day(room_id, roles, uids, target)
    return "TIMEOUT"


def test_citizen_victory_path():
    """마피아 진영을 모두 처형하면 시민이 이긴다 (§4.2)"""
    toks, room_id, roles = make_game(15)
    if not room_id:
        check("시민 승리 경로 준비", False, "방 생성 실패")
        return
    uids = uid_map(roles)

    winner = play_to_end(room_id, roles, uids, execute_team="MAFIA")
    check("마피아 진영 전멸 -> 시민 승리 (§4.2)", winner == "CITIZEN", "winner=%s" % winner)

    if winner == "CITIZEN":
        s, pl = req("/rest/v1/players?select=team,alive&room_id=eq." + room_id, toks[0])
        mafia_alive = sum(1 for p in pl if p["team"] == "MAFIA" and p["alive"])
        check("승리 시점에 마피아 진영 0명", mafia_alive == 0, "%d명" % mafia_alive)

    rpc("leave_room", toks[0], {"p_room_id": room_id})


def test_mafia_victory_path():
    """시민을 계속 잃으면 마피아가 이긴다 (§4.3)"""
    toks, room_id, roles = make_game(15)
    if not room_id:
        check("마피아 승리 경로 준비", False, "방 생성 실패")
        return
    uids = uid_map(roles)

    winner = play_to_end(room_id, roles, uids, execute_team="CITIZEN")
    check("시민 감소 -> 마피아 승리 (§4.3)", winner == "MAFIA", "winner=%s" % winner)

    if winner == "MAFIA":
        s, pl = req("/rest/v1/players?select=team,alive&room_id=eq." + room_id, toks[0])
        m = sum(1 for p in pl if p["team"] == "MAFIA" and p["alive"])
        c = sum(1 for p in pl if p["team"] == "CITIZEN" and p["alive"])
        check("승리 시점에 마피아 >= 시민 (광대 제외)", m >= c, "마피아%d vs 시민%d" % (m, c))

    rpc("leave_room", toks[0], {"p_room_id": room_id})


def test_jester_victory_beats_others():
    """광대 처형은 다른 승리 조건보다 먼저 판정된다 (§4.1)"""
    toks, room_id, roles = make_game(12)
    if not room_id:
        check("광대 우선 판정 준비", False, "방 생성 실패")
        return
    uids = uid_map(roles)

    jester = _pick(roles, "JESTER")
    citizens = [t for t, r in roles.items() if r["role"] == "CITIZEN"]

    # 광대를 밤에 죽이면 안 된다 (§2.10) — 다른 사람을 공격
    pass_night(room_id, roles, uids, victim_uid=uids[citizens[0]],
               doctor_uid=uids[jester], guard_uid=uids[jester])
    pass_day(room_id, roles, uids, uids[jester])

    s, r = req("/rest/v1/rooms?select=phase,winner&id=eq." + room_id, jester)
    check("광대 처형 -> 광대 단독 승리 (§4.1)",
          bool(r) and r[0]["winner"] == "JESTER",
          "winner=%s" % (r[0]["winner"] if r else "?"))

    # 이 시점에 마피아도 시민도 살아 있는데 광대가 이겼어야 한다
    if r and r[0]["winner"] == "JESTER":
        s, pl = req("/rest/v1/players?select=team,alive&room_id=eq." + room_id, jester)
        m = sum(1 for p in pl if p["team"] == "MAFIA" and p["alive"])
        c = sum(1 for p in pl if p["team"] == "CITIZEN" and p["alive"])
        check("양 진영이 남아 있어도 광대가 우선",
              m > 0 and c > 0, "마피아%d 시민%d" % (m, c))

    rpc("leave_room", toks[0], {"p_room_id": room_id})


def test_jester_killed_at_night_does_not_win():
    """밤에 살해된 광대는 승리하지 못한다 (§2.10)"""
    toks, room_id, roles = make_game(12)
    if not room_id:
        check("광대 밤 사망 준비", False, "방 생성 실패")
        return
    uids = uid_map(roles)

    jester = _pick(roles, "JESTER")
    mafias = [t for t, r in roles.items() if r["role"] == "MAFIA"]

    # 광대를 밤에 공격한다. 의사·경호원이 막지 않도록 다른 쪽으로 돌린다
    pass_night(room_id, roles, uids, victim_uid=uids[jester],
               doctor_uid=uids[mafias[0]], guard_uid=uids[mafias[0]])

    s, pl = req("/rest/v1/players?select=uid,alive&room_id=eq." + room_id, jester)
    j_alive = next((p["alive"] for p in pl if p["uid"] == uids[jester]), None)
    s, r = req("/rest/v1/rooms?select=phase,winner&id=eq." + room_id, jester)

    check("밤에 죽은 광대는 승리하지 못한다 (§2.10)",
          j_alive is False and (not r or r[0]["winner"] != "JESTER"),
          "광대생존=%s winner=%s" % (j_alive, r[0]["winner"] if r else "?"))

    rpc("leave_room", toks[0], {"p_room_id": room_id})


ALL = [test_all_compositions, test_all_abilities_same_night,
       test_citizen_victory_path, test_mafia_victory_path,
       test_jester_victory_beats_others, test_jester_killed_at_night_does_not_win]


# ------------------------------------------------------------------
# 무승부 종료 (§4.4, 요구사항 외 추가)
# ------------------------------------------------------------------

def _game_with_max_days(n, max_days):
    """최대 일수를 정해 두고 시작한 게임"""
    from stage2 import make_room
    toks, room_id = make_room(n)
    if not room_id:
        return None, None, None, None
    rpc("set_timers", toks[0],
        {"p_room_id": room_id, "p_night": 30, "p_day": 60, "p_max_days": max_days})
    rpc("start_game", toks[0], {"p_room_id": room_id})

    roles = {}
    for t in toks:
        s, b = rpc("my_role", t, {"p_room_id": room_id})
        if s == 200:
            roles[t] = b
    return toks, room_id, roles, uid_map(roles)


def test_default_settings():
    """새 방의 기본값: 밤 30초 / 낮 60초 / 15일차"""
    from stage2 import make_room
    toks, room_id = make_room(5)
    if not room_id:
        check("기본 설정 준비", False, "방 생성 실패")
        return

    s, r = req("/rest/v1/rooms?select=night_seconds,day_seconds,max_days&id=eq." + room_id,
               toks[0])
    ok = bool(r) and r[0]["night_seconds"] == 30 and r[0]["day_seconds"] == 60 \
        and r[0]["max_days"] == 15
    check("기본값 밤30초/낮60초/15일차", ok, str(r[0]) if r else "?")

    rpc("leave_room", toks[0], {"p_room_id": room_id})


def test_draw_on_max_day():
    """최대 일수에 도달하면 무승부 (§4.4)"""
    toks, room_id, roles, uids = _game_with_max_days(7, 1)
    if not room_id:
        check("무승부 테스트 준비", False, "방 생성 실패")
        return

    citizens = [t for t, r in roles.items() if r["role"] == "CITIZEN"]

    # 1일차 밤: 의사가 공격 대상을 치료해 아무도 죽지 않게 한다.
    # 사망자가 생기면 인원이 줄어 마피아 승리로 끝날 수 있다.
    pass_night(room_id, roles, uids,
               victim_uid=uids[citizens[0]], doctor_uid=uids[citizens[0]])

    s, pl = req("/rest/v1/players?select=alive&room_id=eq." + room_id, toks[0])
    dead = sum(1 for p in pl if not p["alive"]) if isinstance(pl, list) else -1
    check("무승부 준비: 1일차 사망자 없음", dead == 0, "사망 %d명" % dead)

    # 1일차 낮: 시민을 처형해도 승부가 나지 않는다 (마피아2 vs 시민3)
    pass_day(room_id, roles, uids, uids[citizens[1]])

    s, r = req("/rest/v1/rooms?select=phase,winner,day_number&id=eq." + room_id, toks[0])
    check("최대 일수 도달 -> 무승부 (§4.4)",
          bool(r) and r[0]["phase"] == "ENDED" and r[0]["winner"] == "DRAW",
          "%s / %s" % (r[0]["phase"], r[0]["winner"]) if r else "?")

    # 무승부여도 전체 직업은 공개된다
    s, b = rpc("final_roles", toks[1], {"p_room_id": room_id})
    check("무승부 후에도 직업 공개", s == 200 and isinstance(b, list) and len(b) == 7,
          "%d명" % (len(b) if isinstance(b, list) else -1))

    rpc("leave_room", toks[0], {"p_room_id": room_id})


def test_victory_beats_draw():
    """마지막 날이어도 승리 조건이 먼저다 (§4.1 > §4.4)"""
    toks, room_id, roles, uids = _game_with_max_days(7, 1)
    if not room_id:
        check("승리 우선 준비", False, "방 생성 실패")
        return

    jester = _pick(roles, "JESTER")
    citizens = [t for t, r in roles.items() if r["role"] == "CITIZEN"]

    pass_night(room_id, roles, uids,
               victim_uid=uids[citizens[0]], doctor_uid=uids[citizens[0]])
    # 마지막 날에 광대를 처형한다 -> 무승부가 아니라 광대 승리여야 한다
    pass_day(room_id, roles, uids, uids[jester])

    s, r = req("/rest/v1/rooms?select=phase,winner&id=eq." + room_id, jester)
    check("마지막 날 광대 처형 -> 무승부 아닌 광대 승리",
          bool(r) and r[0]["winner"] == "JESTER",
          "winner=%s" % (r[0]["winner"] if r else "?"))

    rpc("leave_room", toks[0], {"p_room_id": room_id})


def test_max_days_permission():
    """최대 일수도 방장만, 대기실에서만 바꿀 수 있다"""
    from stage2 import make_room
    toks, room_id = make_room(5)
    if not room_id:
        check("최대 일수 권한 준비", False, "방 생성 실패")
        return

    s, b = rpc("set_timers", toks[1],
               {"p_room_id": room_id, "p_night": 30, "p_day": 60, "p_max_days": 3})
    check("비방장 최대 일수 변경 차단", s >= 400 and "방장만" in str(msg(b)), msg(b))

    s, b = rpc("set_timers", toks[0],
               {"p_room_id": room_id, "p_night": 30, "p_day": 60, "p_max_days": 3})
    check("방장 최대 일수 변경", s in (200, 204), "HTTP %d" % s)

    s, r = req("/rest/v1/rooms?select=max_days&id=eq." + room_id, toks[0])
    check("최대 일수 저장됨", bool(r) and r[0]["max_days"] == 3,
          str(r[0]["max_days"]) if r else "?")

    rpc("start_game", toks[0], {"p_room_id": room_id})
    s, b = rpc("set_timers", toks[0],
               {"p_room_id": room_id, "p_night": 30, "p_day": 60, "p_max_days": 9})
    check("진행 중 최대 일수 변경 차단", s >= 400 and "대기실에서만" in str(msg(b)), msg(b))

    rpc("leave_room", toks[0], {"p_room_id": room_id})


ALL.extend([test_default_settings, test_draw_on_max_day,
            test_victory_beats_draw, test_max_days_permission])


# ------------------------------------------------------------------
# 채팅 (요구사항 외 추가)
# ------------------------------------------------------------------

def _chat_of(token, room_id):
    s, b = req("/rest/v1/chat_messages?select=channel,body,sender_nickname&room_id=eq."
               + room_id + "&order=id", token)
    return b if isinstance(b, list) else []


def test_chat_lobby():
    """대기실에서는 전원이 대화할 수 있다"""
    from stage2 import make_room
    toks, room_id = make_room(5)
    if not room_id:
        check("대기실 채팅 준비", False, "방 생성 실패")
        return

    s, b = rpc("send_chat", toks[0], {"p_room_id": room_id, "p_body": "안녕하세요"})
    check("대기실 방장 전송", s == 200 and b.get("channel") == "PUBLIC", str(b))

    s, b = rpc("send_chat", toks[3], {"p_room_id": room_id, "p_body": "반갑습니다"})
    check("대기실 참가자 전송", s == 200 and b.get("channel") == "PUBLIC", str(b))

    msgs = _chat_of(toks[2], room_id)
    check("대기실 대화가 전원에게 보인다", len(msgs) == 2, "%d건" % len(msgs))

    s, b = rpc("send_chat", toks[0], {"p_room_id": room_id, "p_body": "   "})
    check("빈 내용 차단", s >= 400 and "내용을 입력" in str(msg(b)), msg(b))

    s, b = rpc("send_chat", toks[0], {"p_room_id": room_id, "p_body": "가" * 301})
    check("300자 초과 차단", s >= 400 and "300자" in str(msg(b)), msg(b))

    # 방에 없는 사람은 보낼 수 없다
    outsider = user_pool(7)[6]
    s, b = rpc("send_chat", outsider, {"p_room_id": room_id, "p_body": "끼어들기"})
    check("외부인 전송 차단", s >= 400 and "참가자가 아닙니다" in str(msg(b)), msg(b))

    check("외부인은 대화를 못 읽는다", _chat_of(outsider, room_id) == [], "")

    rpc("leave_room", toks[0], {"p_room_id": room_id})


def test_chat_night_mafia_only():
    """밤 채팅은 마피아 진영만 쓰고 읽는다 — 핵심 보안 검사"""
    toks, room_id, roles = make_game(9)
    if not room_id:
        check("밤 채팅 준비", False, "방 생성 실패")
        return
    uids = uid_map(roles)

    mafias = [t for t, r in roles.items() if r["role"] == "MAFIA"]
    spy = _pick(roles, "SPY")
    police = _pick(roles, "POLICE")
    citizens = [t for t, r in roles.items() if r["role"] == "CITIZEN"]

    # 시민은 밤에 쓸 수 없다
    s, b = rpc("send_chat", citizens[0], {"p_room_id": room_id, "p_body": "저 시민이에요"})
    check("밤: 시민 전송 차단",
          s >= 400 and "마피아 진영만" in str(msg(b)), msg(b))

    s, b = rpc("send_chat", police, {"p_room_id": room_id, "p_body": "조사했습니다"})
    check("밤: 경찰 전송 차단", s >= 400 and "마피아 진영만" in str(msg(b)), msg(b))

    # 마피아와 스파이는 쓸 수 있다
    s, b = rpc("send_chat", mafias[0], {"p_room_id": room_id, "p_body": "누구 칠까"})
    check("밤: 마피아 전송", s == 200 and b.get("channel") == "MAFIA", str(b))

    s, b = rpc("send_chat", spy, {"p_room_id": room_id, "p_body": "경찰부터"})
    check("밤: 스파이도 전송", s == 200 and b.get("channel") == "MAFIA", str(b))

    # 읽기 — 마피아 진영만 보인다
    m_msgs = _chat_of(mafias[1], room_id)
    check("마피아 동료가 읽는다", len(m_msgs) == 2, "%d건" % len(m_msgs))

    for label, tok in [("시민", citizens[0]), ("경찰", police)]:
        seen = _chat_of(tok, room_id)
        check("밤 대화를 %s은 못 읽는다 (RLS)" % label, seen == [], "%d건 %s" % (len(seen), seen))

    # 직접 INSERT 는 막혀 있다
    s, b = req("/rest/v1/chat_messages", citizens[0],
               body={"room_id": room_id, "channel": "MAFIA", "sender_uid": uids[citizens[0]],
                     "sender_nickname": "위조", "body": "몰래", "phase": "NIGHT"})
    check("직접 INSERT 차단", s >= 400, "HTTP %d" % s)

    rpc("leave_room", toks[0], {"p_room_id": room_id})


def test_chat_day_and_dead():
    """낮에는 생존자만 쓰고, 사망자는 읽기만 한다"""
    toks, room_id, roles = make_game(9)
    if not room_id:
        check("낮 채팅 준비", False, "방 생성 실패")
        return
    uids = uid_map(roles)

    citizens = [t for t, r in roles.items() if r["role"] == "CITIZEN"]
    police = _pick(roles, "POLICE")
    victim = citizens[0]

    pass_night(room_id, roles, uids, victim_uid=uids[victim], doctor_uid=uids[police])

    s, r = req("/rest/v1/rooms?select=phase&id=eq." + room_id, police)
    if not (r and r[0]["phase"] == "DAY"):
        check("낮 채팅: 생존자 전송", False, "낮 진입 실패")
        rpc("leave_room", toks[0], {"p_room_id": room_id})
        return

    s, b = rpc("send_chat", police, {"p_room_id": room_id, "p_body": "제가 경찰입니다"})
    check("낮: 생존자 전송", s == 200 and b.get("channel") == "PUBLIC", str(b))

    s, b = rpc("send_chat", victim, {"p_room_id": room_id, "p_body": "범인은..."})
    check("낮: 사망자 전송 차단",
          s >= 400 and "사망한 참가자는 낮에" in str(msg(b)), msg(b))

    seen = _chat_of(victim, room_id)
    check("사망자도 낮 대화는 읽는다", len(seen) == 1, "%d건" % len(seen))

    # 밤에 쓴 마피아 대화가 낮에도 시민에게 보이지 않아야 한다
    mafias = [t for t, r in roles.items() if r["role"] == "MAFIA"]
    rpc("send_chat", mafias[0], {"p_room_id": room_id, "p_body": "낮에도 공개 채널"})
    civ_seen = _chat_of(citizens[1], room_id)
    check("낮에는 마피아도 공개 채널", len(civ_seen) == 2, "%d건" % len(civ_seen))

    rpc("leave_room", toks[0], {"p_room_id": room_id})


def test_chat_after_end():
    """게임이 끝나면 사망자도 대화할 수 있다"""
    toks, room_id, roles, uids = _game_with_max_days(7, 1)
    if not room_id:
        check("종료 후 채팅 준비", False, "방 생성 실패")
        return

    citizens = [t for t, r in roles.items() if r["role"] == "CITIZEN"]
    pass_night(room_id, roles, uids,
               victim_uid=uids[citizens[0]], doctor_uid=uids[citizens[0]])
    pass_day(room_id, roles, uids, uids[citizens[1]])

    s, r = req("/rest/v1/rooms?select=phase,winner&id=eq." + room_id, toks[0])
    if not (r and r[0]["phase"] == "ENDED"):
        check("종료 후 사망자 전송 허용", False, "종료되지 않음")
        rpc("leave_room", toks[0], {"p_room_id": room_id})
        return

    s, b = rpc("send_chat", citizens[1], {"p_room_id": room_id, "p_body": "아 억울하다"})
    check("종료 후 사망자 전송 허용", s == 200 and b.get("channel") == "PUBLIC", str(b))

    rpc("leave_room", toks[0], {"p_room_id": room_id})


ALL.extend([test_chat_lobby, test_chat_night_mafia_only,
            test_chat_day_and_dead, test_chat_after_end])


def test_chat_revealed_only_after_end():
    """마피아 대화는 진행 중엔 막히고 종료 후에만 공개된다"""
    toks, room_id, roles, uids = _game_with_max_days(7, 1)
    if not room_id:
        check("종료 후 공개 준비", False, "방 생성 실패")
        return

    mafias = [t for t, r in roles.items() if r["role"] == "MAFIA"]
    citizens = [t for t, r in roles.items() if r["role"] == "CITIZEN"]
    police = _pick(roles, "POLICE")

    # 밤에 마피아가 대화한다
    s, b = rpc("send_chat", mafias[0], {"p_room_id": room_id, "p_body": "작전 회의"})
    check("밤 마피아 전송", s == 200 and b.get("channel") == "MAFIA", str(b))

    # 진행 중에는 시민·경찰이 못 읽는다
    def maf_count(tok):
        s2, m = req("/rest/v1/chat_messages?select=channel&room_id=eq." + room_id
                    + "&channel=eq.MAFIA", tok)
        return len(m) if isinstance(m, list) else -1

    check("진행 중: 시민은 못 읽는다", maf_count(citizens[0]) == 0,
          "%d건" % maf_count(citizens[0]))
    check("진행 중: 경찰은 못 읽는다", maf_count(police) == 0, "%d건" % maf_count(police))
    check("진행 중: 마피아는 읽는다", maf_count(mafias[0]) == 1, "%d건" % maf_count(mafias[0]))

    # 게임을 끝낸다 (max_days=1 이므로 낮 처리 후 무승부 또는 승부)
    pass_night(room_id, roles, uids,
               victim_uid=uids[citizens[0]], doctor_uid=uids[citizens[0]])
    pass_day(room_id, roles, uids, uids[citizens[1]])

    s, r = req("/rest/v1/rooms?select=phase&id=eq." + room_id, police)
    if not (r and r[0]["phase"] == "ENDED"):
        check("종료 후: 시민도 읽는다", False, "종료되지 않음")
        rpc("leave_room", toks[0], {"p_room_id": room_id})
        return

    check("종료 후: 시민도 읽는다", maf_count(citizens[0]) >= 1,
          "%d건" % maf_count(citizens[0]))
    check("종료 후: 경찰도 읽는다", maf_count(police) >= 1, "%d건" % maf_count(police))

    rpc("leave_room", toks[0], {"p_room_id": room_id})


ALL.append(test_chat_revealed_only_after_end)


# ------------------------------------------------------------------
# 다시하기 (요구사항 외 추가)
# ------------------------------------------------------------------

def test_restart_game():
    """종료된 방을 대기실로 되돌린다"""
    toks, room_id, roles, uids = _game_with_max_days(7, 1)
    if not room_id:
        check("다시하기 준비", False, "방 생성 실패")
        return

    citizens = [t for t, r in roles.items() if r["role"] == "CITIZEN"]
    mafias = [t for t, r in roles.items() if r["role"] == "MAFIA"]

    # 진행 중에는 다시하기를 쓸 수 없다
    s, b = rpc("restart_game", toks[0], {"p_room_id": room_id})
    check("진행 중 다시하기 차단",
          s >= 400 and "끝난 뒤에만" in str(msg(b)), msg(b))

    # 밤에 마피아 채팅을 남겨두고 게임을 끝낸다
    rpc("send_chat", mafias[0], {"p_room_id": room_id, "p_body": "지난 판 작전"})
    pass_night(room_id, roles, uids,
               victim_uid=uids[citizens[0]], doctor_uid=uids[citizens[0]])
    pass_day(room_id, roles, uids, uids[citizens[1]])

    s, r = req("/rest/v1/rooms?select=phase,winner&id=eq." + room_id, toks[0])
    if not (r and r[0]["phase"] == "ENDED"):
        check("종료 확인", False, "종료되지 않음")
        rpc("leave_room", toks[0], {"p_room_id": room_id})
        return
    check("종료 확인", True, "승자 %s" % r[0]["winner"])

    # 방장이 아니면 못 누른다
    s, b = rpc("restart_game", toks[1], {"p_room_id": room_id})
    check("비방장 다시하기 차단", s >= 400 and "방장만" in str(msg(b)), msg(b))

    # 방장이 다시하기
    s, b = rpc("restart_game", toks[0], {"p_room_id": room_id})
    check("방장 다시하기", s in (200, 204), "HTTP %d" % s)

    s, r = req("/rest/v1/rooms?select=phase,day_number,winner,phase_deadline,night_seconds&id=eq."
               + room_id, toks[0])
    ok = (bool(r) and r[0]["phase"] == "LOBBY" and r[0]["day_number"] == 0
          and r[0]["winner"] is None and r[0]["phase_deadline"] is None)
    check("대기실로 복귀", ok, str(r[0]) if r else "?")
    check("제한시간 설정은 유지", bool(r) and r[0]["night_seconds"] == 30,
          "night=%s" % (r[0]["night_seconds"] if r else "?"))

    # 참가자는 그대로, 상태는 초기화
    s, pl = req("/rest/v1/players?select=nickname,alive,is_ready,is_host,team,ability_used&room_id=eq."
                + room_id + "&order=joined_at", toks[0])
    check("참가자 유지", len(pl) == 7, "%d명" % len(pl))
    check("전원 생존 복구", all(p["alive"] for p in pl), str([p["nickname"] for p in pl if not p["alive"]]))
    check("진영 초기화", all(p["team"] is None for p in pl), str(set(p["team"] for p in pl)))
    check("능력 사용 초기화", all(not p["ability_used"] for p in pl), "")
    host_ready = [p["is_ready"] for p in pl if p["is_host"]]
    others = [p["is_ready"] for p in pl if not p["is_host"]]
    check("방장은 준비 유지, 나머지는 해제",
          host_ready == [True] and not any(others),
          "방장=%s 나머지준비=%d명" % (host_ready, sum(1 for x in others if x)))

    # 지난 판 기록 삭제
    s, ch = req("/rest/v1/chat_messages?select=id&room_id=eq." + room_id, toks[0])
    check("지난 판 채팅 삭제", ch == [], "%d건" % len(ch if isinstance(ch, list) else []))
    s, pub = req("/rest/v1/public_results?select=day_number&room_id=eq." + room_id, toks[0])
    check("지난 판 공개결과 삭제", pub == [], "%d건" % len(pub if isinstance(pub, list) else []))

    # 직업이 사라졌으므로 my_game_view 는 거부해야 한다
    s, b = rpc("my_game_view", toks[1], {"p_room_id": room_id})
    check("직업 배정 해제", s >= 400 and "배정되지" in str(msg(b)), msg(b))

    # 다시 시작할 수 있다
    for t in toks[1:]:
        rpc("set_ready", t, {"p_room_id": room_id, "p_ready": True})
    s, b = rpc("start_game", toks[0], {"p_room_id": room_id})
    check("다시 시작 가능", s in (200, 204), "HTTP %d %s" % (s, "" if s < 400 else msg(b)))

    s, r = req("/rest/v1/rooms?select=phase,day_number&id=eq." + room_id, toks[0])
    check("새 게임 1일차 밤", bool(r) and r[0]["phase"] == "NIGHT" and r[0]["day_number"] == 1,
          "%s %s일차" % (r[0]["phase"], r[0]["day_number"]) if r else "?")

    # 직업이 새로 배정됐는지
    got = 0
    for t in toks:
        s, v = rpc("my_game_view", t, {"p_room_id": room_id})
        if s == 200:
            got += 1
    check("직업 재배정", got == 7, "%d/7" % got)

    rpc("leave_room", toks[0], {"p_room_id": room_id})


ALL.append(test_restart_game)
