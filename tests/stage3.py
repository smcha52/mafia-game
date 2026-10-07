"""
§8.2-10  전체 직업 조합과 승리 조건 테스트

개별 직업은 stage2 에서 검증했다. 여기서는 직업들이 서로 얽혔을 때를 본다.
  · 5~15명 11개 구성 전부에서 배정이 구성표와 일치하는가
  · 9개 능력이 같은 밤에 동시에 작동해도 §3 순서가 지켜지는가
  · 세 가지 승리 경로(시민·마피아·광대)에 모두 도달하는가
  · 게임이 무한히 이어지지 않고 끝나는가
"""

from harness import check, close_room, msg, req, rpc, skip_vote_result, user_pool, start_game
from stage2 import _pick, alive_uids, make_game, pass_day, pass_night, uid_map

# §5 인원별 기본 직업 구성. 서버의 role_composition() 과 일치해야 한다.
ROLE_TABLE = {
    5:  ['MAFIA', 'POLICE', 'DOCTOR', 'CITIZEN', 'CITIZEN'],
    6:  ['MAFIA', 'POLICE', 'DOCTOR', 'BODYGUARD', 'CITIZEN', 'CITIZEN'],
    7:  ['MAFIA', 'ASSASSIN', 'POLICE', 'DOCTOR', 'JESTER', 'CITIZEN', 'CITIZEN'],
    8:  ['MAFIA', 'ASSASSIN', 'POLICE', 'DOCTOR', 'BODYGUARD', 'JESTER',
         'CITIZEN', 'CITIZEN'],
    9:  ['MAFIA', 'ASSASSIN', 'SPY', 'POLICE', 'DOCTOR', 'DETECTIVE',
         'KILLER', 'CITIZEN', 'CITIZEN'],
    10: ['MAFIA', 'ASSASSIN', 'SPY', 'POLICE', 'DOCTOR', 'BODYGUARD', 'DETECTIVE',
         'KILLER', 'VIGILANTE', 'CITIZEN'],
    11: ['MAFIA', 'ASSASSIN', 'SPY', 'POLICE', 'DOCTOR', 'BODYGUARD', 'DETECTIVE',
         'REPORTER', 'KILLER', 'VIGILANTE', 'CITIZEN'],
    12: ['MAFIA', 'MAFIA', 'ASSASSIN', 'SPY', 'POLICE', 'DOCTOR', 'BODYGUARD',
         'DETECTIVE', 'REPORTER', 'JESTER', 'KILLER', 'VIGILANTE'],
    13: ['MAFIA', 'MAFIA', 'ASSASSIN', 'SPY', 'POLICE', 'DOCTOR', 'BODYGUARD',
         'DETECTIVE', 'REPORTER', 'MEDIUM', 'JESTER', 'KILLER', 'VIGILANTE'],
    14: ['MAFIA', 'MAFIA', 'ASSASSIN', 'SPY', 'POLICE', 'DOCTOR', 'BODYGUARD',
         'DETECTIVE', 'REPORTER', 'MEDIUM', 'JESTER', 'KILLER', 'VIGILANTE',
         'CITIZEN'],
    15: ['MAFIA', 'MAFIA', 'ASSASSIN', 'SPY', 'POLICE', 'DOCTOR', 'BODYGUARD',
         'DETECTIVE', 'REPORTER', 'MEDIUM', 'JESTER', 'KILLER', 'VIGILANTE',
         'CITIZEN', 'CITIZEN'],
}


def team_of(role):
    if role in ("MAFIA", "SPY", "ASSASSIN", "FORGER"):
        return "MAFIA"
    if role in ("JESTER", "KILLER", "SURVIVOR"):
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
        toks, room_id, roles = make_game(n, disabled=())
        if not room_id:
            bad.append("%d명: 방 생성 실패" % n)
            continue

        got = Counter(r["role"] for r in roles.values())
        want = Counter(ROLE_TABLE[n])
        if got != want:
            bad.append("%d명: %s" % (n, dict(got)))
        elif len(roles) != n:
            bad.append("%d명: %d명만 배정" % (n, len(roles)))

        close_room(toks, room_id)

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

    # 마피아 2 + 암살자 1 + 스파이 1 이 같은 사람을 공격
    killer = _pick(roles, "ASSASSIN")
    for t in mafias + [spy, killer]:
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

    close_room(toks, room_id)


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

    close_room(toks, room_id)


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

    close_room(toks, room_id)


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

    close_room(toks, room_id)


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

    close_room(toks, room_id)


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
    start_game(toks[0], room_id)

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

    close_room(toks, room_id)


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

    close_room(toks, room_id)


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

    close_room(toks, room_id)


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

    start_game(toks[0], room_id)
    s, b = rpc("set_timers", toks[0],
               {"p_room_id": room_id, "p_night": 30, "p_day": 60, "p_max_days": 9})
    check("진행 중 최대 일수 변경 차단", s >= 400 and "대기실에서만" in str(msg(b)), msg(b))

    close_room(toks, room_id)


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

    close_room(toks, room_id)


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

    # 읽기 — 마피아 진영만 보인다 (동료는 암살자로 확인)
    m_msgs = _chat_of(_pick(roles, "ASSASSIN"), room_id)
    check("마피아 동료가 읽는다", len(m_msgs) == 2, "%d건" % len(m_msgs))

    for label, tok in [("시민", citizens[0]), ("경찰", police)]:
        seen = _chat_of(tok, room_id)
        check("밤 대화를 %s은 못 읽는다 (RLS)" % label, seen == [], "%d건 %s" % (len(seen), seen))

    # 직접 INSERT 는 막혀 있다
    s, b = req("/rest/v1/chat_messages", citizens[0],
               body={"room_id": room_id, "channel": "MAFIA", "sender_uid": uids[citizens[0]],
                     "sender_nickname": "위조", "body": "몰래", "phase": "NIGHT"})
    check("직접 INSERT 차단", s >= 400, "HTTP %d" % s)

    close_room(toks, room_id)


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
        close_room(toks, room_id)
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

    close_room(toks, room_id)


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
        close_room(toks, room_id)
        return

    s, b = rpc("send_chat", citizens[1], {"p_room_id": room_id, "p_body": "아 억울하다"})
    check("종료 후 사망자 전송 허용", s == 200 and b.get("channel") == "PUBLIC", str(b))

    close_room(toks, room_id)


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
        close_room(toks, room_id)
        return

    check("종료 후: 시민도 읽는다", maf_count(citizens[0]) >= 1,
          "%d건" % maf_count(citizens[0]))
    check("종료 후: 경찰도 읽는다", maf_count(police) >= 1, "%d건" % maf_count(police))

    close_room(toks, room_id)


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
        close_room(toks, room_id)
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
    s, b = start_game(toks[0], room_id)
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

    close_room(toks, room_id)


ALL.append(test_restart_game)


# ------------------------------------------------------------------
# 직업 켜기/끄기 (요구사항 외 추가)
# ------------------------------------------------------------------

def test_role_toggle_composition():
    """끈 직업은 시민으로 대체되고 인원수는 유지된다"""
    from collections import Counter
    from harness import KEY

    # 기본 (아무것도 끄지 않음)
    s, base = rpc("role_composition", KEY, {"p_count": 13, "p_disabled": []})
    check("끄지 않으면 기존 구성", s == 200 and Counter(base) == Counter(ROLE_TABLE[13]),
          str(Counter(base)) if s == 200 else str(base))

    # 광대·기자를 끄면 그 자리가 시민이 된다
    s, off = rpc("role_composition", KEY,
                 {"p_count": 13, "p_disabled": ["JESTER", "REPORTER"]})
    c = Counter(off) if s == 200 else Counter()
    check("끈 직업은 사라진다", "JESTER" not in c and "REPORTER" not in c, str(dict(c)))
    check("끈 자리는 시민이 채운다",
          c.get("CITIZEN") == Counter(ROLE_TABLE[13]).get("CITIZEN", 0) + 2,
          "시민 %s명 (원래 %s명)"
          % (c.get("CITIZEN"), Counter(ROLE_TABLE[13]).get("CITIZEN", 0)))
    check("인원수 유지 (§5.1)", len(off or []) == 13, "%d개" % len(off or []))

    # 8개 전부 끄면 마피아 + 시민만 남는다
    s, all_off = rpc("role_composition", KEY,
                     {"p_count": 15, "p_disabled": ["POLICE", "DOCTOR", "BODYGUARD",
                                                    "DETECTIVE", "REPORTER", "MEDIUM",
                                                    "SPY", "JESTER", "ASSASSIN",
                                                    "KILLER", "VIGILANTE"]})
    c2 = Counter(all_off) if s == 200 else Counter()
    check("전부 끄면 마피아+시민만",
          set(c2.keys()) == {"MAFIA", "CITIZEN"} and len(all_off) == 15,
          str(dict(c2)))
    check("마피아는 남는다", c2.get("MAFIA", 0) >= 1, "마피아 %d명" % c2.get("MAFIA", 0))


def test_role_toggle_permission():
    """방장만, 대기실에서만, 끌 수 있는 직업만"""
    from stage2 import make_room
    toks, room_id = make_room(5)
    if not room_id:
        check("직업 설정 권한 준비", False, "방 생성 실패")
        return

    s, b = rpc("set_disabled_roles", toks[1],
               {"p_room_id": room_id, "p_disabled": ["POLICE"]})
    check("비방장 직업 변경 차단", s >= 400 and "방장만" in str(msg(b)), msg(b))

    # 마피아는 끌 수 있다(0030). 5명 고정 구성은 마피아 진영이 마피아뿐이라
    # 끄면 마피아 진영이 0명이 되어 시작할 수 없다(0031).
    s, b = rpc("set_disabled_roles", toks[0],
               {"p_room_id": room_id, "p_disabled": ["MAFIA"]})
    check("마피아도 끌 수 있다", s in (200, 204), msg(b))
    s, b = start_game(toks[0], room_id)
    check("마피아 진영 0명이면 시작 차단",
          s >= 400 and "마피아 진영 직업이 하나도 없어" in str(msg(b)), msg(b))
    s, r = req("/rest/v1/rooms?select=phase&id=eq." + room_id, toks[0])
    check("시작이 취소되어 대기실 유지",
          bool(r) and r[0]["phase"] == "LOBBY", str(r))

    s, b = rpc("set_disabled_roles", toks[0],
               {"p_room_id": room_id, "p_disabled": ["CITIZEN"]})
    check("시민은 끌 수 없다", s >= 400 and "끌 수 없는" in str(msg(b)), msg(b))

    s, b = rpc("set_disabled_roles", toks[0],
               {"p_room_id": room_id, "p_disabled": ["POLICE", "DOCTOR"]})
    check("방장 직업 변경", s in (200, 204), "HTTP %d" % s)

    s, r = req("/rest/v1/rooms?select=disabled_roles&id=eq." + room_id, toks[0])
    check("설정 저장됨",
          bool(r) and sorted(r[0]["disabled_roles"]) == ["DOCTOR", "POLICE"],
          str(r[0]["disabled_roles"]) if r else "?")

    start_game(toks[0], room_id)
    s, b = rpc("set_disabled_roles", toks[0],
               {"p_room_id": room_id, "p_disabled": ["POLICE"]})
    check("진행 중 직업 변경 차단", s >= 400 and "대기실에서만" in str(msg(b)), msg(b))

    close_room(toks, room_id)


def test_role_toggle_applies_to_game():
    """끈 직업이 실제 배정에서 빠진다"""
    from collections import Counter
    from stage2 import make_room

    toks, room_id = make_room(7)
    if not room_id:
        check("직업 끄기 적용 준비", False, "방 생성 실패")
        return

    # 7명 기본 구성: MAFIA2 POLICE DOCTOR JESTER CITIZEN2
    # 광대와 의사를 끄면 -> MAFIA2 POLICE CITIZEN4
    rpc("set_disabled_roles", toks[0],
        {"p_room_id": room_id, "p_disabled": ["JESTER", "DOCTOR"]})
    start_game(toks[0], room_id)

    roles = {}
    for t in toks:
        s, v = rpc("my_role", t, {"p_room_id": room_id})
        if s == 200:
            roles[t] = v["role"]

    c = Counter(roles.values())
    check("배정에 광대가 없다", "JESTER" not in c, str(dict(c)))
    check("배정에 의사가 없다", "DOCTOR" not in c, str(dict(c)))
    check("대신 시민이 늘었다", c.get("CITIZEN") == 4, "시민 %s명" % c.get("CITIZEN"))
    check("마피아 진영은 그대로 2명",
          c.get("MAFIA", 0) + c.get("ASSASSIN", 0) == 2,
          "마피아 %s + 암살자 %s" % (c.get("MAFIA"), c.get("ASSASSIN")))
    check("전원 배정", len(roles) == 7, "%d/7" % len(roles))

    # 광대가 없으니 jester_uid 도 비어 있어야 한다
    s, r = req("/rest/v1/rooms?select=jester_uid&id=eq." + room_id, toks[0])
    check("광대 없으면 jester_uid 비어 있음", bool(r) and r[0]["jester_uid"] is None,
          str(r[0]["jester_uid"]) if r else "?")

    close_room(toks, room_id)


def test_role_toggle_survives_restart():
    """다시하기 후에도 직업 설정이 유지된다"""
    toks, room_id, roles, uids = _game_with_max_days(7, 1)
    if not room_id:
        check("다시하기 후 설정 유지 준비", False, "방 생성 실패")
        return

    citizens = [t for t, r in roles.items() if r["role"] == "CITIZEN"]
    pass_night(room_id, roles, uids,
               victim_uid=uids[citizens[0]], doctor_uid=uids[citizens[0]])
    pass_day(room_id, roles, uids, uids[citizens[1]])

    s, r = req("/rest/v1/rooms?select=phase&id=eq." + room_id, toks[0])
    if not (r and r[0]["phase"] == "ENDED"):
        check("다시하기 후 설정 유지", False, "종료되지 않음")
        close_room(toks, room_id)
        return

    rpc("restart_game", toks[0], {"p_room_id": room_id})
    rpc("set_disabled_roles", toks[0], {"p_room_id": room_id, "p_disabled": ["JESTER"]})

    # 한 판 더 돌린 뒤 설정이 남아 있는지
    for t in toks[1:]:
        rpc("set_ready", t, {"p_room_id": room_id, "p_ready": True})
    start_game(toks[0], room_id)

    s, r = req("/rest/v1/rooms?select=disabled_roles&id=eq." + room_id, toks[0])
    check("다시하기 후 설정 유지", bool(r) and r[0]["disabled_roles"] == ["JESTER"],
          str(r[0]["disabled_roles"]) if r else "?")

    close_room(toks, room_id)


ALL.extend([test_role_toggle_composition, test_role_toggle_permission,
            test_role_toggle_applies_to_game, test_role_toggle_survives_restart])


# ------------------------------------------------------------------
# 암살자 (요구사항 외 추가)
# ------------------------------------------------------------------

def test_assassin_composition():
    """구성표에 암살자가 들어가고, 끄면 마피아로 돌아간다"""
    from collections import Counter
    from harness import KEY

    # 5~6명에는 없다
    for n in (5, 6):
        s, c = rpc("role_composition", KEY, {"p_count": n, "p_disabled": []})
        check("%d명엔 암살자 없음" % n, s == 200 and "ASSASSIN" not in c, str(c))

    # 7명 이상에는 마피아 1명이 암살자로 바뀐다
    s, c7 = rpc("role_composition", KEY, {"p_count": 7, "p_disabled": []})
    cc = Counter(c7)
    check("7명: 마피아1 + 암살자1",
          cc.get("MAFIA") == 1 and cc.get("ASSASSIN") == 1, str(dict(cc)))

    s, c13 = rpc("role_composition", KEY, {"p_count": 13, "p_disabled": []})
    cc13 = Counter(c13)
    check("13명: 마피아2 + 암살자1",
          cc13.get("MAFIA") == 2 and cc13.get("ASSASSIN") == 1, str(dict(cc13)))

    # 끄면 시민이 아니라 마피아로 돌아간다
    s, off = rpc("role_composition", KEY,
                 {"p_count": 13, "p_disabled": ["ASSASSIN"]})
    co = Counter(off)
    check("암살자를 끄면 마피아로 복귀",
          "ASSASSIN" not in co and co.get("MAFIA") == 3, str(dict(co)))
    check("끄더라도 인원수 유지", len(off or []) == 13, "%d개" % len(off or []))


def _assassin_game(n=7):
    """암살자가 있는 게임. (토큰맵, room_id, 직업맵, uid맵) 반환"""
    toks, room_id, roles = make_game(n)
    if not room_id:
        return None, None, None, None
    return toks, room_id, roles, uid_map(roles)


def test_assassin_hit_and_miss():
    """맞히면 대상이 죽고, 틀리면 암살자가 죽는다"""
    # --- 성공 ---
    toks, room_id, roles, uids = _assassin_game(7)
    if not room_id:
        check("암살 성공 준비", False, "방 생성 실패")
        return

    killer = _pick(roles, "ASSASSIN")
    police = _pick(roles, "POLICE")
    citizens = [t for t, r in roles.items() if r["role"] == "CITIZEN"]

    s, v = rpc("my_game_view", killer, {"p_room_id": room_id})
    check("암살자는 마피아 진영", v.get("team") == "MAFIA", str(v.get("team")))
    check("저격 가능 여부 제공", v.get("canAssassinate") is True, str(v.get("canAssassinate")))

    # 경찰을 경찰로 찍는다 -> 성공
    s, b = rpc("submit_assassination", killer,
               {"p_room_id": room_id, "p_target_uid": uids[police], "p_guess": "POLICE"})
    check("밤 저격 제출", s == 200 and b.get("resolved") is False, str(b))

    # 같은 밤에 두 번은 못 한다
    s, b2 = rpc("submit_assassination", killer,
                {"p_room_id": room_id, "p_target_uid": uids[citizens[0]], "p_guess": "CITIZEN"})
    check("같은 밤 재저격 차단", s >= 400 and "이미 저격" in str(msg(b2)), msg(b2))

    # 일반 공격도 함께 할 수 있다
    s, b3 = rpc("submit_night_action", killer,
                {"p_room_id": room_id, "p_action": "MAFIA_VOTE",
                 "p_target_uid": uids[citizens[0]]})
    check("저격과 일반 공격 동시 가능", s == 200, str(b3)[:40])

    pass_night(room_id, roles, uids, victim_uid=uids[citizens[0]], doctor_uid=uids[killer])

    s, pl = req("/rest/v1/players?select=uid,alive&room_id=eq." + room_id, killer)
    alive = {p["uid"]: p["alive"] for p in pl} if isinstance(pl, list) else {}
    check("저격 성공 -> 대상 사망", alive.get(uids[police]) is False,
          "경찰 생존=%s" % alive.get(uids[police]))
    check("저격 성공 -> 암살자 생존", alive.get(uids[killer]) is True,
          "암살자 생존=%s" % alive.get(uids[killer]))

    s, v = rpc("my_game_view", killer, {"p_room_id": room_id})
    res = [x for x in (v.get("privateResults") or []) if x["kind"] == "ASSASSIN"]
    check("암살자만 결과를 받는다",
          len(res) == 1 and res[0]["payload"]["success"] is True,
          str(res[0]["payload"]) if res else "없음")

    s, v2 = rpc("my_game_view", citizens[1], {"p_room_id": room_id})
    check("다른 사람은 저격 결과 없음",
          not [x for x in (v2.get("privateResults") or []) if x["kind"] == "ASSASSIN"], "")

    close_room(toks, room_id)

    # --- 실패 ---
    toks, room_id, roles, uids = _assassin_game(7)
    if not room_id:
        check("암살 실패 준비", False, "방 생성 실패")
        return
    killer = _pick(roles, "ASSASSIN")
    police = _pick(roles, "POLICE")
    citizens = [t for t, r in roles.items() if r["role"] == "CITIZEN"]

    # 경찰을 의사로 찍는다 -> 실패
    rpc("submit_assassination", killer,
        {"p_room_id": room_id, "p_target_uid": uids[police], "p_guess": "DOCTOR"})
    pass_night(room_id, roles, uids, victim_uid=uids[citizens[0]], doctor_uid=uids[killer])

    s, pl = req("/rest/v1/players?select=uid,alive&room_id=eq." + room_id, citizens[1])
    alive = {p["uid"]: p["alive"] for p in pl} if isinstance(pl, list) else {}
    check("저격 실패 -> 암살자 사망", alive.get(uids[killer]) is False,
          "암살자 생존=%s" % alive.get(uids[killer]))
    check("저격 실패 -> 대상 생존", alive.get(uids[police]) is True,
          "경찰 생존=%s" % alive.get(uids[police]))

    close_room(toks, room_id)


def test_assassin_day_immediate():
    """낮 저격은 즉시 처리된다"""
    toks, room_id, roles, uids = _assassin_game(9)
    if not room_id:
        check("낮 저격 준비", False, "방 생성 실패")
        return

    killer = _pick(roles, "ASSASSIN")
    doctor = _pick(roles, "DOCTOR")
    citizens = [t for t, r in roles.items() if r["role"] == "CITIZEN"]

    # 밤을 넘긴다
    pass_night(room_id, roles, uids, victim_uid=uids[citizens[0]], doctor_uid=uids[killer])
    s, r = req("/rest/v1/rooms?select=phase&id=eq." + room_id, killer)
    if not (r and r[0]["phase"] == "DAY"):
        check("낮 저격 즉시 처리", False, "낮 진입 실패")
        close_room(toks, room_id)
        return

    # 낮에 의사를 의사로 찍는다 -> 즉시 사망
    s, b = rpc("submit_assassination", killer,
               {"p_room_id": room_id, "p_target_uid": uids[doctor], "p_guess": "DOCTOR"})
    check("낮 저격 즉시 처리", s == 200 and b.get("resolved") is True, str(b))

    s, pl = req("/rest/v1/players?select=uid,alive&room_id=eq." + room_id, killer)
    alive = {p["uid"]: p["alive"] for p in pl} if isinstance(pl, list) else {}
    check("낮 저격으로 즉시 사망", alive.get(uids[doctor]) is False,
          "의사 생존=%s" % alive.get(uids[doctor]))

    s, pub = req("/rest/v1/public_results?select=payload&room_id=eq." + room_id
                 + "&kind=eq.DAY", citizens[1])
    dd = pub[0]["payload"].get("dayDeaths") if pub else None
    check("낮 사망자가 공개된다", dd == [uids[doctor]], str(dd))

    # 밤과 낮은 따로 센다 — 낮에 또 하려면 막힌다
    s, b2 = rpc("submit_assassination", killer,
                {"p_room_id": room_id, "p_target_uid": uids[citizens[1]], "p_guess": "CITIZEN"})
    check("같은 낮 재저격 차단", s >= 400 and "이미 저격" in str(msg(b2)), msg(b2))

    close_room(toks, room_id)


def test_assassin_rules():
    """권한과 제한"""
    toks, room_id, roles, uids = _assassin_game(7)
    if not room_id:
        check("암살 규칙 준비", False, "방 생성 실패")
        return

    killer = _pick(roles, "ASSASSIN")
    police = _pick(roles, "POLICE")
    citizens = [t for t, r in roles.items() if r["role"] == "CITIZEN"]

    s, b = rpc("submit_assassination", police,
               {"p_room_id": room_id, "p_target_uid": uids[citizens[0]], "p_guess": "CITIZEN"})
    check("비암살자 저격 차단", s >= 400 and "저격수만" in str(msg(b)), msg(b))

    s, b = rpc("submit_assassination", killer,
               {"p_room_id": room_id, "p_target_uid": uids[killer], "p_guess": "ASSASSIN"})
    check("자기 저격 차단", s >= 400 and "자신을 지목" in str(msg(b)), msg(b))

    s, b = rpc("submit_assassination", killer,
               {"p_room_id": room_id, "p_target_uid": uids[police], "p_guess": "NOPE"})
    check("없는 직업 차단", s >= 400 and "직업을 선택" in str(msg(b)), msg(b))

    close_room(toks, room_id)




def test_assassin_all_citizens_blocked():
    """같은 편을 뺀 상대가 전부 시민이면 저격할 수 없다 (0021)

    암살자는 mafiaMembers 로 같은 편을 전부 안다. 팀원이 살아 있다는 이유로
    판정을 통과시키면, 남은 대상이 전원 시민이어도 "시민"이라고만 찍어서
    무위험 저격을 반복할 수 있다. 실제 판(YUX83H)에서 이렇게 끝났다.
    """
    from harness import user_pool

    n = 7
    toks = user_pool(n)
    s, b = rpc("create_room", toks[0], {"p_nickname": "P1"})
    if s != 200:
        check("전원시민 저격차단 준비", False, "방 생성 실패")
        return
    room_id, code = b["room_id"], b["room_code"]
    for i, t in enumerate(toks[1:], start=2):
        rpc("join_room", t, {"p_code": code, "p_nickname": "P%d" % i})
        rpc("set_ready", t, {"p_room_id": room_id, "p_ready": True})

    # 암살자만 남기고 전부 끈다 -> 마피아1 + 암살자1 + 시민5
    off = ["POLICE", "DOCTOR", "BODYGUARD", "DETECTIVE",
           "REPORTER", "MEDIUM", "SPY", "JESTER"]
    s, b = rpc("set_disabled_roles", toks[0],
               {"p_room_id": room_id, "p_disabled": off})
    check("직업 끄기 성공", s in (200, 204), str(b)[:60])

    start_game(toks[0], room_id)

    roles = {}
    for t in toks:
        s, b = rpc("my_role", t, {"p_room_id": room_id})
        if s == 200:
            roles[t] = b
    uids = uid_map(roles)

    from collections import Counter
    cc = Counter(r["role"] for r in roles.values())
    check("구성: 마피아1 + 암살자1 + 시민5",
          cc.get("MAFIA") == 1 and cc.get("ASSASSIN") == 1 and cc.get("CITIZEN") == 5,
          str(dict(cc)))

    killer = _pick(roles, "ASSASSIN")
    citizens = [t for t, r in roles.items() if r["role"] == "CITIZEN"]

    # 팀원(마피아)이 살아 있어도, 상대가 전원 시민이므로 막혀야 한다
    s, v = rpc("my_game_view", killer, {"p_room_id": room_id})
    check("전원 시민이면 canAssassinate=false",
          v.get("canAssassinate") is False, str(v.get("canAssassinate")))

    s, b = rpc("submit_assassination", killer,
               {"p_room_id": room_id, "p_target_uid": uids[citizens[0]],
                "p_guess": "CITIZEN"})
    check("전원 시민이면 저격 제출 차단",
          s >= 400 and "모두 시민" in str(msg(b)), msg(b))

    close_room(toks, room_id)


def test_assassin_guard_allows_real_target():
    """시민팀 능력자가 한 명이라도 살아 있으면 저격할 수 있다 (0021)"""
    toks, room_id, roles, uids = _assassin_game(7)
    if not room_id:
        check("저격 허용 준비", False, "방 생성 실패")
        return

    killer = _pick(roles, "ASSASSIN")
    s, v = rpc("my_game_view", killer, {"p_room_id": room_id})
    check("경찰·의사가 살아 있으면 canAssassinate=true",
          v.get("canAssassinate") is True, str(v.get("canAssassinate")))

    close_room(toks, room_id)




def test_d3_reporter_on_jester():
    """D-3: 기자가 광대를 취재하면 '시민 진영' 으로 위장 공개된다 (0022)

    광대의 team 은 NEUTRAL 이고 중립 직업은 광대뿐이다. 그대로 공개하면
    광대가 완벽하게 특정돼 승리 경로(처형당하기)가 사라진다.

    기자 성공률이 50% 라 성공할 때까지 판을 다시 만든다. 12인 게임은 비싸므로
    경찰 검증(비공개는 그대로 NEUTRAL)도 같은 밤에 끼워 한 판을 아낀다.
    """
    got_success = False
    police_checked = False

    for attempt in range(8):
        toks, room_id, roles = make_game(12)
        if not room_id:
            continue
        uids = uid_map(roles)
        rep = _pick(roles, "REPORTER")
        jester = _pick(roles, "JESTER")
        police = _pick(roles, "POLICE")
        if not rep or not jester:
            close_room(toks, room_id)
            continue

        rpc("submit_night_action", rep,
            {"p_room_id": room_id, "p_action": "REPORTER",
             "p_target_uid": uids[jester]})
        # 경찰도 같은 광대를 조사시킨다 — 판 하나를 아낀다
        if police:
            rpc("submit_night_action", police,
                {"p_room_id": room_id, "p_action": "POLICE",
                 "p_target_uid": uids[jester]})
        # 광대와 기자는 살려 둔다
        pass_night(room_id, roles, uids,
                   victim_uid=uids[_pick(roles, "CITIZEN")], doctor_uid=uids[rep])

        # 경찰은 바꾸지 않았으므로 광대를 그대로 중립으로 봐야 한다
        if police and not police_checked:
            s, pv = rpc("my_game_view", police, {"p_room_id": room_id})
            pres = [r for r in (pv.get("privateResults") or []) if r["kind"] == "POLICE"]
            if pres:
                police_checked = True
                check("경찰은 광대를 중립으로 본다 (비공개라 유지)",
                      pres[0]["payload"].get("team") == "NEUTRAL",
                      "team=%s" % pres[0]["payload"].get("team"))

        s, v = rpc("my_game_view", rep, {"p_room_id": room_id})
        res = [r for r in (v.get("privateResults") or []) if r["kind"] == "REPORTER"]
        pay = res[0]["payload"] if res else {}

        if pay.get("success"):
            got_success = True
            check("기자 비공개 결과도 시민으로 위장",
                  pay.get("team") == "CITIZEN", "team=%s" % pay.get("team"))
            check("기자에게 NEUTRAL 을 주지 않는다",
                  pay.get("team") != "NEUTRAL", "team=%s" % pay.get("team"))

            s, pubs = req("/rest/v1/public_results?select=payload&room_id=eq." + room_id
                          + "&kind=eq.NIGHT&day_number=eq.1", toks[0])
            reveal = pubs[0]["payload"].get("reporterReveal") if pubs else None
            one = reveal[0] if isinstance(reveal, list) and reveal else {}
            check("공개 결과도 시민으로 위장",
                  one.get("team") == "CITIZEN", str(reveal))
            check("공개 결과에 중립이 새지 않는다",
                  "NEUTRAL" not in str(reveal), str(reveal))
            close_room(toks, room_id)
            break

        close_room(toks, room_id)

    if not got_success:
        check("D-3 검증", False, "8번 시도했지만 기자가 한 번도 성공하지 못했다")
    if not police_checked:
        check("경찰 판정 검증", False, "경찰 조사 결과를 받지 못했다")


ALL.extend([test_assassin_composition, test_assassin_hit_and_miss,
            test_assassin_day_immediate, test_assassin_rules,
            test_assassin_all_citizens_blocked,
            test_assassin_guard_allows_real_target,
            test_d3_reporter_on_jester])


# ------------------------------------------------------------------
# 0023  밤에 낮 투표 결과 공개 — 동점 여부, 처형자 진영
# ------------------------------------------------------------------

def _day_payload(room_id, token, day):
    s, b = req("/rest/v1/public_results?select=payload&room_id=eq." + room_id
               + "&kind=eq.DAY&day_number=eq.%d" % day, token)
    return b[0]["payload"] if s == 200 and b else {}


def _split_votes(room_id, roles, uids, a, b, c):
    """최다 득표가 a, b 로 갈리도록 투표시킨다. 인원이 홀수면 한 표는 c 로 보낸다."""
    alive = alive_uids(room_id, next(iter(roles)))
    voters = [t for t in roles if uids[t] in alive]
    n = len(voters)
    quota = {a: n // 2, b: n // 2, c: n % 2}
    # 대상 본인이 먼저 표를 고르게 해 몫이 자기 자신에게만 남는 일을 막는다
    voters.sort(key=lambda t: uids[t] not in (a, b, c))
    last = None
    for t in voters:
        opts = [u for u in (a, b, c) if u != uids[t] and quota[u] > 0]
        tgt = max(opts, key=lambda u: quota[u])
        quota[tgt] -= 1
        s, last = rpc("submit_day_vote", t, {"p_room_id": room_id, "p_target_uid": tgt})
    skip_vote_result(room_id, voters[0])
    return last


def test_day_tie_and_citizen_reveal():
    """동점이면 아무도 처형하지 않고 tie=true 를 공개한다 (D-2, 0023)
    시민 진영 처형자는 진영만 공개하고 직업은 숨긴다."""
    toks, room_id, roles = make_game(7)
    if not room_id:
        check("낮 결과 공개 준비", False, "방 생성 실패")
        return
    uids = uid_map(roles)
    citizens = [t for t, r in roles.items() if r["role"] == "CITIZEN"]
    police = _pick(roles, "POLICE")
    doctor = _pick(roles, "DOCTOR")
    jester = _pick(roles, "JESTER")

    pass_night(room_id, roles, uids, victim_uid=uids[citizens[0]],
               doctor_uid=uids[_pick(roles, "MAFIA")])

    # --- 1일차 낮: 경찰과 의사가 동점 ---
    before = alive_uids(room_id, toks[0])
    b = _split_votes(room_id, roles, uids, uids[police], uids[doctor], uids[jester])
    check("동점 투표 후 자동 처리",
          isinstance(b, dict) and b.get("resolved") is True, str(b))
    check("낮 동점 -> 아무도 처형되지 않는다 (D-2)",
          alive_uids(room_id, toks[0]) == before, "")

    pay = _day_payload(room_id, citizens[1], 1)
    check("동점 공개: tie=true", pay.get("tie") is True, str(pay))
    check("동점 공개: 처형자·진영·직업 비어 있음",
          pay.get("executed") is None and pay.get("executedTeam") is None
          and pay.get("executedRole") is None, str(pay))

    s, rm = req("/rest/v1/rooms?select=phase,day_number&id=eq." + room_id, toks[0])
    check("동점 후 2일차 밤으로 진행",
          bool(rm) and rm[0]["phase"] == "NIGHT" and rm[0]["day_number"] == 2,
          str(rm))

    # --- 2일차: 경찰 처형 -> 시민 진영, 직업은 숨긴다 ---
    # 밤에 시민이 또 죽으면 마피아2 : 시민2 로 밤에 게임이 끝나므로 의사가 살린다
    pass_night(room_id, roles, uids, victim_uid=uids[citizens[1]],
               doctor_uid=uids[citizens[1]])
    pass_day(room_id, roles, uids, uids[police])

    pay = _day_payload(room_id, toks[0], 2)
    check("시민 처형 공개: executedTeam=CITIZEN",
          pay.get("executedTeam") == "CITIZEN", str(pay))
    check("시민 처형 공개: 직업은 숨긴다",
          pay.get("executedRole") is None and "POLICE" not in str(pay), str(pay))
    check("처형 시 tie=false",
          pay.get("tie") is False and pay.get("executed") == uids[police], str(pay))

    close_room(toks, room_id)


def test_day_reveal_mafia_and_jester():
    """마피아 진영 처형자는 진영만, 중립(광대)은 직업을 그대로 공개한다 (0023)"""
    toks, room_id, roles = make_game(7)
    if not room_id:
        check("낮 결과 공개 준비", False, "방 생성 실패")
        return
    uids = uid_map(roles)
    citizens = [t for t, r in roles.items() if r["role"] == "CITIZEN"]
    assassin = _pick(roles, "ASSASSIN")
    jester = _pick(roles, "JESTER")

    pass_night(room_id, roles, uids, victim_uid=uids[citizens[0]],
               doctor_uid=uids[_pick(roles, "MAFIA")])

    # --- 1일차: 암살자 처형 -> 마피아 진영, 직업은 숨긴다 ---
    pass_day(room_id, roles, uids, uids[assassin])
    pay = _day_payload(room_id, citizens[1], 1)
    check("마피아 처형 공개: executedTeam=MAFIA",
          pay.get("executedTeam") == "MAFIA", str(pay))
    check("마피아 처형 공개: 암살자 직업은 숨긴다",
          pay.get("executedRole") is None and "ASSASSIN" not in str(pay), str(pay))

    s, rm = req("/rest/v1/rooms?select=phase,day_number&id=eq." + room_id, toks[0])
    check("마피아 처형 후 2일차 밤으로 진행",
          bool(rm) and rm[0]["phase"] == "NIGHT" and rm[0]["day_number"] == 2,
          str(rm))

    # --- 2일차: 광대 처형 -> 직업을 그대로 공개, 진영은 비운다 ---
    pass_night(room_id, roles, uids, victim_uid=uids[citizens[1]],
               doctor_uid=uids[_pick(roles, "POLICE")])
    pass_day(room_id, roles, uids, uids[jester])

    pay = _day_payload(room_id, toks[0], 2)
    check("광대 처형 공개: executedRole=JESTER",
          pay.get("executedRole") == "JESTER", str(pay))
    check("광대 처형 공개: 진영(NEUTRAL)은 비운다",
          pay.get("executedTeam") is None and "NEUTRAL" not in str(pay), str(pay))

    s, rm = req("/rest/v1/rooms?select=phase,winner&id=eq." + room_id, toks[0])
    check("공개 후에도 광대 단독 승리 유지",
          bool(rm) and rm[0]["winner"] == "JESTER", str(rm))

    close_room(toks, room_id)


ALL.extend([test_day_tie_and_citizen_reveal, test_day_reveal_mafia_and_jester])


# ------------------------------------------------------------------
# 새 직업: 살인자 (0028) — 중립, 밤마다 혼자 제거, 누구와든 1:1 이면 단독 승리
# ------------------------------------------------------------------

def _killer_game(n, off):
    """off 직업을 끈 n명 게임. (토큰들, room_id, 직업맵, uid맵) 반환"""
    toks = user_pool(n)
    s, b = rpc("create_room", toks[0], {"p_nickname": "P1"})
    if s != 200:
        return None, None, None, None
    room_id, code = b["room_id"], b["room_code"]
    for i, t in enumerate(toks[1:], start=2):
        rpc("join_room", t, {"p_code": code, "p_nickname": "P%d" % i})
        rpc("set_ready", t, {"p_room_id": room_id, "p_ready": True})
    rpc("set_disabled_roles", toks[0], {"p_room_id": room_id, "p_disabled": off})
    start_game(toks[0], room_id)

    roles = {}
    for t in toks:
        s, b = rpc("my_role", t, {"p_room_id": room_id})
        if s == 200:
            roles[t] = b
    return toks, room_id, roles, uid_map(roles)


# 살인자만 남기고 전부 끈다 -> 9명: 마피아2(암살자 자리 포함) + 살인자1 + 시민6
ALL_BUT_KILLER = ["POLICE", "DOCTOR", "BODYGUARD", "DETECTIVE",
                  "REPORTER", "MEDIUM", "SPY", "JESTER", "ASSASSIN", "VIGILANTE"]


def _phase(room_id, token):
    s, b = req("/rest/v1/rooms?select=phase,winner,day_number&id=eq." + room_id, token)
    return b[0] if s == 200 and b else {}


def test_killer_composition():
    from collections import Counter
    from harness import KEY

    s, c8 = rpc("role_composition", KEY, {"p_count": 8, "p_disabled": []})
    check("8명엔 살인자 없음", s == 200 and "KILLER" not in c8, str(c8))

    bad = []
    for n in range(9, 16):
        s, c = rpc("role_composition", KEY, {"p_count": n, "p_disabled": []})
        if not (s == 200 and Counter(c).get("KILLER") == 1):
            bad.append("%d명: %s" % (n, c))
    check("9명 이상 살인자 1명", not bad, "; ".join(bad) if bad else "9~15명")

    s, base = rpc("role_composition", KEY, {"p_count": 9, "p_disabled": []})
    s, off = rpc("role_composition", KEY, {"p_count": 9, "p_disabled": ["KILLER"]})
    check("살인자를 끄면 시민으로 복귀",
          "KILLER" not in off
          and Counter(off).get("CITIZEN") == Counter(base).get("CITIZEN") + 1,
          str(dict(Counter(off))))


def test_killer_night_rules():
    """살인자 제출·차단·치료·경호·경찰 판정 (11명 기본 구성)"""
    toks, room_id, roles, uids = _killer_game(11, ["VIGILANTE"])
    if not room_id:
        check("살인자 밤 테스트 준비", False, "방 생성 실패")
        return

    killer = _pick(roles, "KILLER")
    police = _pick(roles, "POLICE")
    guard = _pick(roles, "BODYGUARD")
    citizens = [t for t, r in roles.items() if r["role"] == "CITIZEN"]
    m_target, k_target = citizens[0], citizens[1]

    s, v = rpc("my_game_view", killer, {"p_room_id": room_id})
    check("살인자는 중립 진영", v.get("team") == "NEUTRAL", str(v.get("team")))

    s, b = rpc("submit_night_action", killer,
               {"p_room_id": room_id, "p_action": "KILLER", "p_target_uid": uids[killer]})
    check("살인자 자기 지목 차단", s >= 400 and "자신" in str(msg(b)), msg(b))

    s, b = rpc("submit_night_action", police,
               {"p_room_id": room_id, "p_action": "KILLER", "p_target_uid": uids[k_target]})
    check("살인자가 아니면 제거 차단", s >= 400 and "사용할 수 없는" in str(msg(b)), msg(b))

    # 살인자를 뺀 전원이 먼저 제출한다
    # 마피아 -> 시민A (경호원이 막고 대신 죽음), 살인자 -> 시민B (의사가 치료)
    others = {t: r for t, r in roles.items() if r["role"] != "KILLER"}
    b = pass_night(room_id, others, uids, victim_uid=uids[m_target],
                   doctor_uid=uids[k_target], guard_uid=uids[m_target],
                   police_uid=uids[killer])
    check("살인자가 내기 전엔 밤이 끝나지 않는다",
          _phase(room_id, toks[0]).get("phase") == "NIGHT", str(b))

    s, b = rpc("submit_night_action", killer,
               {"p_room_id": room_id, "p_action": "KILLER", "p_target_uid": uids[k_target]})
    check("살인자 제출로 밤 종료", s == 200 and b.get("resolved") is True, str(b))

    alive = alive_uids(room_id, toks[0])
    check("의사가 살인자의 공격을 막는다", uids[k_target] in alive, "")
    check("경호원이 마피아 공격을 막고 대신 죽는다",
          uids[m_target] in alive and uids[guard] not in alive, "")

    s, dv = rpc("my_game_view", _pick(roles, "DOCTOR"), {"p_room_id": room_id})
    doc = [r for r in (dv.get("privateResults") or []) if r["kind"] == "DOCTOR"]
    check("의사 결과: 살인자 대상을 살렸다",
          bool(doc) and doc[0]["payload"].get("savedUid") == uids[k_target], str(doc)[:60])

    s, pv = rpc("my_game_view", police, {"p_room_id": room_id})
    pres = [r for r in (pv.get("privateResults") or []) if r["kind"] == "POLICE"]
    check("경찰은 살인자를 중립으로 본다",
          bool(pres) and pres[0]["payload"].get("team") == "NEUTRAL", str(pres)[:60])

    close_room(toks, room_id)


def test_killer_kills_separately():
    """마피아와 살인자가 다른 사람을 노리면 둘 다 죽는다. 누구든 노릴 수 있다."""
    toks, room_id, roles, uids = _killer_game(9, ALL_BUT_KILLER)
    if not room_id:
        check("살인자 제거 테스트 준비", False, "방 생성 실패")
        return
    from collections import Counter
    cc = Counter(r["role"] for r in roles.values())
    check("구성: 마피아2 + 살인자1 + 시민6",
          cc.get("MAFIA") == 2 and cc.get("KILLER") == 1 and cc.get("CITIZEN") == 6,
          str(dict(cc)))

    mafia = [t for t, r in roles.items() if r["role"] == "MAFIA"]
    citizens = [t for t, r in roles.items() if r["role"] == "CITIZEN"]

    # 살인자는 마피아도 노릴 수 있다
    pass_night(room_id, roles, uids, victim_uid=uids[citizens[0]], killer_uid=uids[mafia[0]])
    alive = alive_uids(room_id, toks[0])
    check("마피아 대상과 살인자 대상이 모두 죽는다",
          uids[citizens[0]] not in alive and uids[mafia[0]] not in alive, "")
    s, pub = req("/rest/v1/public_results?select=payload&room_id=eq." + room_id
                 + "&kind=eq.NIGHT&day_number=eq.1", toks[0])
    deaths = pub[0]["payload"].get("nightDeaths") if pub else None
    check("밤 사망자 2명 공개", isinstance(deaths, list) and len(deaths) == 2, str(deaths))

    close_room(toks, room_id)


def test_killer_blocks_other_wins():
    """살인자가 살아 있으면 시민은 이기지 못하고, 살인자까지 잡아야 이긴다"""
    toks, room_id, roles, uids = _killer_game(9, ALL_BUT_KILLER)
    if not room_id:
        check("살인자 승리조건 준비", False, "방 생성 실패")
        return
    killer = _pick(roles, "KILLER")
    mafia = [t for t, r in roles.items() if r["role"] == "MAFIA"]
    cz = [t for t, r in roles.items() if r["role"] == "CITIZEN"]

    # 1밤: 둘이 같은 시민을 노린다 -> 1명 사망 (8명)
    pass_night(room_id, roles, uids, victim_uid=uids[cz[0]], killer_uid=uids[cz[0]])
    # 1낮: 마피아 1 처형 (7명: 마피아1 살인자1 시민5)
    pass_day(room_id, roles, uids, uids[mafia[0]])
    # 2밤: 마피아는 시민, 살인자는 남은 마피아 -> 마피아 전멸 (5명: 살인자1 시민4)
    pass_night(room_id, roles, uids, victim_uid=uids[cz[1]], killer_uid=uids[mafia[1]])

    st = _phase(room_id, toks[0])
    check("마피아 전멸이어도 살인자가 살아 있으면 시민 승리 아님",
          st.get("phase") == "DAY" and st.get("winner") is None, str(st))

    # 2낮: 살인자 처형 -> 이제 시민 승리
    pass_day(room_id, roles, uids, uids[killer])
    st = _phase(room_id, toks[0])
    check("살인자까지 잡으면 시민 승리",
          st.get("phase") == "ENDED" and st.get("winner") == "CITIZEN", str(st))

    s, b = req("/rest/v1/public_results?select=payload&room_id=eq." + room_id
               + "&kind=eq.DAY&day_number=eq.2", toks[0])
    pay = b[0]["payload"] if b else {}
    check("살인자 처형은 직업으로 공개 (중립)",
          pay.get("executedRole") == "KILLER" and pay.get("executedTeam") is None, str(pay))

    close_room(toks, room_id)


def test_killer_wins_one_on_one():
    """마피아가 시민보다 많아도 살인자가 살아 있으면 마피아 승리가 아니고,
    마피아와 1:1 이 되면 살인자가 이긴다"""
    toks, room_id, roles, uids = _killer_game(9, ALL_BUT_KILLER)
    if not room_id:
        check("살인자 1:1 준비", False, "방 생성 실패")
        return
    mafia = [t for t, r in roles.items() if r["role"] == "MAFIA"]
    cz = [t for t, r in roles.items() if r["role"] == "CITIZEN"]

    # 1밤 (7명) -> 1낮 시민 처형 (6명: 마피아2 살인자1 시민3)
    pass_night(room_id, roles, uids, victim_uid=uids[cz[0]], killer_uid=uids[cz[1]])
    pass_day(room_id, roles, uids, uids[cz[2]])
    # 2밤 (4명: 마피아2 살인자1 시민1) — 살인자가 없으면 마피아 승리 조건이다
    pass_night(room_id, roles, uids, victim_uid=uids[cz[3]], killer_uid=uids[cz[4]])
    st = _phase(room_id, toks[0])
    check("살인자 생존 시 마피아 승리 없음 (마피아2 vs 시민1)",
          st.get("phase") == "DAY" and st.get("winner") is None, str(st))

    # 2낮: 마피아 1 처형 (3명: 마피아1 살인자1 시민1)
    pass_day(room_id, roles, uids, uids[mafia[0]])
    # 3밤: 마피아와 살인자가 마지막 시민을 노린다 -> 마피아1 vs 살인자1
    pass_night(room_id, roles, uids, victim_uid=uids[cz[5]], killer_uid=uids[cz[5]])
    st = _phase(room_id, toks[0])
    check("마피아와 1:1 -> 살인자 단독 승리",
          st.get("phase") == "ENDED" and st.get("winner") == "KILLER", str(st))

    close_room(toks, room_id)


def test_killer_reporter_disguise():
    """기자가 살인자를 취재하면 광대처럼 시민 진영으로 공개된다"""
    got = False
    for attempt in range(8):
        toks, room_id, roles, uids = _killer_game(11, ["VIGILANTE"])
        if not room_id:
            continue
        rep, killer = _pick(roles, "REPORTER"), _pick(roles, "KILLER")
        rpc("submit_night_action", rep,
            {"p_room_id": room_id, "p_action": "REPORTER", "p_target_uid": uids[killer]})
        # 기자와 살인자는 살려 둔다
        pass_night(room_id, roles, uids, victim_uid=uids[_pick(roles, "CITIZEN")],
                   doctor_uid=uids[rep])

        s, v = rpc("my_game_view", rep, {"p_room_id": room_id})
        res = [r for r in (v.get("privateResults") or []) if r["kind"] == "REPORTER"]
        pay = res[0]["payload"] if res else {}
        if pay.get("success"):
            got = True
            check("기자 결과: 살인자는 시민 진영", pay.get("team") == "CITIZEN", str(pay)[:60])
            s, pubs = req("/rest/v1/public_results?select=payload&room_id=eq." + room_id
                          + "&kind=eq.NIGHT&day_number=eq.1", toks[0])
            reveal = pubs[0]["payload"].get("reporterReveal") if pubs else None
            check("공개 결과도 시민, 중립이 새지 않는다",
                  "CITIZEN" in str(reveal) and "NEUTRAL" not in str(reveal), str(reveal))
            close_room(toks, room_id)
            break
        close_room(toks, room_id)

    if not got:
        check("살인자 취재 검증", False, "8번 시도했지만 기자가 한 번도 성공하지 못했다")


ALL.extend([test_killer_composition, test_killer_night_rules,
            test_killer_kills_separately, test_killer_blocks_other_wins,
            test_killer_wins_one_on_one, test_killer_reporter_disguise])


# ------------------------------------------------------------------
# 자경단 (0029)
# ------------------------------------------------------------------

# 자경단만 남기고 전부 끈다 -> 10명: 마피아2(암살자 자리 포함) + 자경단1 + 시민7
ALL_BUT_VIGILANTE = ["POLICE", "DOCTOR", "BODYGUARD", "DETECTIVE", "REPORTER",
                     "MEDIUM", "SPY", "JESTER", "ASSASSIN", "KILLER"]


def test_vigilante_composition():
    from collections import Counter
    from harness import KEY

    s, c9 = rpc("role_composition", KEY, {"p_count": 9, "p_disabled": []})
    check("9명엔 자경단 없음", s == 200 and "VIGILANTE" not in c9, str(c9))

    bad = []
    for n in range(10, 16):
        s, c = rpc("role_composition", KEY, {"p_count": n, "p_disabled": []})
        if not (s == 200 and Counter(c).get("VIGILANTE") == 1):
            bad.append("%d명: %s" % (n, c))
    check("10명 이상 자경단 1명", not bad, "; ".join(bad) if bad else "10~15명")

    s, base = rpc("role_composition", KEY, {"p_count": 10, "p_disabled": []})
    s, off = rpc("role_composition", KEY, {"p_count": 10, "p_disabled": ["VIGILANTE"]})
    check("자경단을 끄면 시민으로 복귀",
          "VIGILANTE" not in off
          and Counter(off).get("CITIZEN", 0) == Counter(base).get("CITIZEN", 0) + 1,
          str(dict(Counter(off))))


def test_vigilante_one_shot():
    """건너뛰기, 한 번 제거, 이후 차단, 밤 진행 인원에서 빠지기"""
    toks, room_id, roles, uids = _killer_game(10, ALL_BUT_VIGILANTE)
    if not room_id:
        check("자경단 테스트 준비", False, "방 생성 실패")
        return
    from collections import Counter
    cc = Counter(r["role"] for r in roles.values())
    check("구성: 마피아2 + 자경단1 + 시민7",
          cc.get("MAFIA") == 2 and cc.get("VIGILANTE") == 1 and cc.get("CITIZEN") == 7,
          str(dict(cc)))

    vig = _pick(roles, "VIGILANTE")
    mafias = [t for t, r in roles.items() if r["role"] == "MAFIA"]
    citizens = [t for t, r in roles.items() if r["role"] == "CITIZEN"]

    s, v = rpc("my_game_view", vig, {"p_room_id": room_id})
    check("자경단은 시민 진영", v.get("team") == "CITIZEN", str(v.get("team")))

    s, b = rpc("submit_night_action", vig,
               {"p_room_id": room_id, "p_action": "VIGILANTE", "p_target_uid": uids[vig]})
    check("자경단 자기 지목 차단", s >= 400 and "자신" in str(msg(b)), msg(b))

    s, b = rpc("submit_night_action", mafias[0],
               {"p_room_id": room_id, "p_action": "VIGILANTE", "p_target_uid": uids[citizens[0]]})
    check("자경단이 아니면 제거 차단", s >= 400 and "사용할 수 없는" in str(msg(b)), msg(b))

    # 1일차 밤: 자경단은 건너뛴다. 마피아만 내면 밤이 끝난다.
    s, b = rpc("submit_night_action", vig,
               {"p_room_id": room_id, "p_action": "VIGILANTE", "p_target_uid": None})
    check("자경단 건너뛰기 허용", s == 200, str(b))
    check("건너뛰기만으로는 밤이 끝나지 않는다",
          _phase(room_id, toks[0]).get("phase") == "NIGHT", "")
    pass_night(room_id, roles, uids, victim_uid=uids[citizens[0]])
    s, v = rpc("my_game_view", vig, {"p_room_id": room_id})
    check("건너뛰면 기회가 남는다", v.get("abilityUsed") is False, str(v.get("abilityUsed")))

    pass_day(room_id, roles, uids, uids[citizens[1]])
    check("2일차 밤으로", _phase(room_id, toks[0]).get("phase") == "NIGHT",
          str(_phase(room_id, toks[0])))

    # 2일차 밤: 자경단 -> 마피아1, 마피아 -> 시민. 둘 다 죽는다.
    s, b = rpc("submit_night_action", vig,
               {"p_room_id": room_id, "p_action": "VIGILANTE", "p_target_uid": uids[mafias[0]]})
    check("자경단 제거 제출", s == 200, str(b))
    b = pass_night(room_id, roles, uids, victim_uid=uids[citizens[2]])
    check("2일차 밤 종료", isinstance(b, dict) and b.get("resolved") is True, str(b))

    alive = alive_uids(room_id, toks[0])
    check("자경단의 대상이 죽는다", uids[mafias[0]] not in alive, "")
    check("마피아 공격도 따로 처리된다", uids[citizens[2]] not in alive, "")

    s, v = rpc("my_game_view", vig, {"p_room_id": room_id})
    check("제거 후 기회 소진", v.get("abilityUsed") is True, str(v.get("abilityUsed")))

    pass_day(room_id, roles, uids, uids[citizens[3]])
    check("3일차 밤으로", _phase(room_id, toks[0]).get("phase") == "NIGHT",
          str(_phase(room_id, toks[0])))

    # 3일차 밤: 다시 제거도, 건너뛰기도 막힌다
    s, b = rpc("submit_night_action", vig,
               {"p_room_id": room_id, "p_action": "VIGILANTE", "p_target_uid": uids[mafias[1]]})
    check("두 번째 제거 차단", s >= 400 and "당신은 제거를 이미 했습니다" in str(msg(b)), msg(b))
    s, b = rpc("submit_night_action", vig,
               {"p_room_id": room_id, "p_action": "VIGILANTE", "p_target_uid": None})
    check("소진 후 건너뛰기도 차단",
          s >= 400 and "당신은 제거를 이미 했습니다" in str(msg(b)), msg(b))

    # 자경단을 기다리지 않고 마피아 제출만으로 밤이 끝난다
    s, b = rpc("submit_night_action", mafias[1],
               {"p_room_id": room_id, "p_action": "MAFIA_VOTE", "p_target_uid": uids[citizens[4]]})
    check("소진한 자경단은 밤 진행 인원에서 빠진다",
          s == 200 and b.get("resolved") is True, str(b))

    close_room(toks, room_id)


def test_vigilante_blocked_by_doctor():
    """의사가 막아도 기회는 사라진다"""
    off = [r for r in ALL_BUT_VIGILANTE if r != "DOCTOR"]
    toks, room_id, roles, uids = _killer_game(10, off)
    if not room_id:
        check("자경단·의사 테스트 준비", False, "방 생성 실패")
        return

    vig, doctor = _pick(roles, "VIGILANTE"), _pick(roles, "DOCTOR")
    mafia = _pick(roles, "MAFIA")
    citizens = [t for t, r in roles.items() if r["role"] == "CITIZEN"]

    rpc("submit_night_action", vig,
        {"p_room_id": room_id, "p_action": "VIGILANTE", "p_target_uid": uids[mafia]})
    pass_night(room_id, roles, uids, victim_uid=uids[citizens[0]], doctor_uid=uids[mafia])

    alive = alive_uids(room_id, toks[0])
    check("의사가 자경단의 공격을 막는다", uids[mafia] in alive, "")
    s, v = rpc("my_game_view", vig, {"p_room_id": room_id})
    check("막혀도 기회는 소진", v.get("abilityUsed") is True, str(v.get("abilityUsed")))

    s, dv = rpc("my_game_view", doctor, {"p_room_id": room_id})
    doc = [r for r in (dv.get("privateResults") or []) if r["kind"] == "DOCTOR"]
    check("의사 결과: 자경단 대상을 살렸다",
          bool(doc) and doc[0]["payload"].get("savedUid") == uids[mafia], str(doc)[:60])

    close_room(toks, room_id)


ALL.extend([test_vigilante_composition, test_vigilante_one_shot,
            test_vigilante_blocked_by_doctor])


# ------------------------------------------------------------------
# 랜덤 구성 (0030)
# ------------------------------------------------------------------

# 진영별 인원: 마피아 진영은 기존 구성표 합계, 중립은 9명부터 2명, 나머지는 시민 진영
TEAM_TABLE = {n: (m, 1 if n < 9 else 2) for n, m in
              [(5, 1), (6, 1), (7, 2), (8, 2), (9, 3), (10, 3), (11, 3),
               (12, 4), (13, 4), (14, 4), (15, 4)]}

SPECIALS = ("POLICE", "DOCTOR", "BODYGUARD", "DETECTIVE", "REPORTER", "MEDIUM",
            "VIGILANTE", "SHERIFF", "SPY", "ASSASSIN", "FORGER", "JESTER", "KILLER", "SURVIVOR")


def _random_game(n, off=()):
    """랜덤 구성(기본값)으로 시작한 n명 게임. (토큰들, room_id, 직업맵) 반환"""
    from stage2 import make_room
    toks, room_id = make_room(n)
    if not room_id:
        return None, None, None
    if off:
        rpc("set_disabled_roles", toks[0], {"p_room_id": room_id, "p_disabled": list(off)})
    rpc("start_game", toks[0], {"p_room_id": room_id})
    roles = {}
    for t in toks:
        s, b = rpc("my_role", t, {"p_room_id": room_id})
        if s == 200:
            roles[t] = b
    return toks, room_id, roles


def test_team_composition():
    from harness import KEY

    bad = []
    for n, (m, ne) in TEAM_TABLE.items():
        s, c = rpc("team_composition", KEY, {"p_count": n, "p_disabled": []})
        want = {"mafia": m, "neutral": ne, "citizen": n - m - ne}
        if s != 200 or c != want:
            bad.append("%d명: %s" % (n, c))
    check("진영별 인원 (5명 = 시민3·중립1·마피아1 ...)", not bad,
          "; ".join(bad) if bad else "5~15명")

    s, c = rpc("team_composition", KEY, {"p_count": 9, "p_disabled": ["KILLER", "SURVIVOR"]})
    check("꺼진 중립 자리는 시민 진영으로",
          s == 200 and c == {"mafia": 3, "neutral": 1, "citizen": 5}, str(c))


def test_random_room_setting():
    from stage2 import make_room
    toks, room_id = make_room(5)
    if not room_id:
        check("랜덤 구성 설정 준비", False, "방 생성 실패")
        return

    s, r = req("/rest/v1/rooms?select=random_roles&id=eq." + room_id, toks[0])
    check("랜덤 구성 기본값 켜짐", bool(r) and r[0]["random_roles"] is True, str(r))

    s, b = rpc("set_random_roles", toks[1], {"p_room_id": room_id, "p_on": False})
    check("비방장 랜덤 구성 변경 차단", s >= 400 and "방장만" in str(msg(b)), msg(b))

    s, b = rpc("set_random_roles", toks[0], {"p_room_id": room_id, "p_on": False})
    s, r = req("/rest/v1/rooms?select=random_roles&id=eq." + room_id, toks[0])
    check("방장 랜덤 구성 끄기", bool(r) and r[0]["random_roles"] is False, str(r))

    close_room(toks, room_id)


def test_random_assignment():
    """랜덤 배정이 진영 인원·중복 금지·마피아 1명 이상을 지키는가"""
    from collections import Counter

    bad = []
    seen = set()
    for n in (5, 7, 9, 12, 15):
        for _ in range(2):
            toks, room_id, roles = _random_game(n)
            if not room_id:
                bad.append("%d명: 방 생성 실패" % n)
                continue
            got = [r["role"] for r in roles.values()]
            seen.update(got)
            cc = Counter(got)
            teams = Counter(team_of(x) for x in got)
            m, ne = TEAM_TABLE[n]
            dup = [x for x in SPECIALS if cc.get(x, 0) > 1]
            if len(got) != n:
                bad.append("%d명: %d명만 배정" % (n, len(got)))
            elif teams.get("MAFIA", 0) != m or teams.get("NEUTRAL", 0) != ne:
                bad.append("%d명 진영 인원: %s" % (n, dict(teams)))
            elif cc.get("MAFIA", 0) < 1:
                bad.append("%d명 마피아 없음: %s" % (n, dict(cc)))
            elif dup:
                bad.append("%d명 특수 직업 중복: %s" % (n, dup))
            close_room(toks, room_id)
    check("랜덤 배정: 진영 인원·마피아 1명 이상·특수 직업 중복 없음",
          not bad, "; ".join(bad) if bad else "10판")
    check("랜덤 배정: 여러 직업이 실제로 나온다", len(seen) >= 6, str(sorted(seen)))


def test_random_respects_disabled():
    """꺼진 직업은 랜덤에서도 나오지 않고, 중립을 다 끄면 그 자리는 시민 진영이 된다"""
    from collections import Counter
    off = ["POLICE", "DOCTOR", "JESTER", "KILLER", "SURVIVOR", "SPY"]
    toks, room_id, roles = _random_game(9, off)
    if not room_id:
        check("랜덤 끄기 테스트 준비", False, "방 생성 실패")
        return
    got = [r["role"] for r in roles.values()]
    check("꺼진 직업은 배정되지 않는다", not (set(got) & set(off)), str(sorted(got)))
    teams = Counter(team_of(x) for x in got)
    check("중립을 다 끄면 시민 진영 6 · 마피아 진영 3",
          teams.get("NEUTRAL", 0) == 0 and teams.get("CITIZEN") == 6
          and teams.get("MAFIA") == 3, str(dict(teams)))
    close_room(toks, room_id)


def test_mafia_team_without_mafia():
    """마피아를 꺼도 스파이·암살자가 있으면 시작할 수 있다 (0031)"""
    from collections import Counter
    from harness import KEY

    s, c = rpc("team_composition", KEY,
               {"p_count": 9, "p_disabled": ["MAFIA", "FORGER"]})
    check("마피아를 끄면 마피아 진영은 켜진 스파이·암살자·위조범 수까지",
          s == 200 and c == {"mafia": 2, "neutral": 2, "citizen": 5}, str(c))
    s, c = rpc("team_composition", KEY,
               {"p_count": 9, "p_disabled": ["MAFIA", "SPY", "ASSASSIN", "FORGER"]})
    check("마피아 진영을 다 끄면 0명", s == 200 and c.get("mafia") == 0, str(c))

    # 랜덤 구성: 마피아 없이 스파이·암살자로 시작
    toks, room_id, roles = _random_game(9, ["MAFIA", "FORGER"])
    if not room_id:
        check("마피아 없는 랜덤 게임 준비", False, "방 생성 실패")
        return
    cc = Counter(r["role"] for r in roles.values())
    check("랜덤: 마피아 없이 스파이+암살자로 시작",
          len(roles) == 9 and "MAFIA" not in cc
          and cc.get("SPY") == 1 and cc.get("ASSASSIN") == 1, str(dict(cc)))
    close_room(toks, room_id)

    # 고정 구성: 7명 구성표의 암살자가 마피아 진영을 맡는다
    from stage2 import make_room
    toks, room_id = make_room(7)
    rpc("set_disabled_roles", toks[0], {"p_room_id": room_id, "p_disabled": ["MAFIA"]})
    s, b = start_game(toks[0], room_id)
    check("고정: 마피아를 꺼도 암살자가 있으면 시작", s in (200, 204), msg(b))
    close_room(toks, room_id)

    # 마피아 진영을 다 끄면 시작할 수 없다
    toks, room_id = make_room(9)
    rpc("set_disabled_roles", toks[0],
        {"p_room_id": room_id, "p_disabled": ["MAFIA", "SPY", "ASSASSIN", "FORGER"]})
    s, b = rpc("start_game", toks[0], {"p_room_id": room_id})
    check("마피아 진영을 다 끄면 시작 차단",
          s >= 400 and "마피아 진영 직업이 하나도 없어" in str(msg(b)), msg(b))
    close_room(toks, room_id)


ALL.extend([test_team_composition, test_random_room_setting,
            test_random_assignment, test_random_respects_disabled,
            test_mafia_team_without_mafia])


# ------------------------------------------------------------------
# 보안관 (0032) — 랜덤 구성에서만 나온다
# ------------------------------------------------------------------

CITIZEN_SPECIALS = ["POLICE", "DOCTOR", "BODYGUARD", "DETECTIVE", "REPORTER",
                    "MEDIUM", "VIGILANTE", "SHERIFF"]
OTHER_SPECIALS = ["SPY", "ASSASSIN", "FORGER", "JESTER", "KILLER", "SURVIVOR"]


def _sheriff_game(n, keep, tries=10):
    """keep 직업만 켠 랜덤 게임을, keep 이 모두 배정될 때까지 다시 만든다."""
    off = [r for r in CITIZEN_SPECIALS + OTHER_SPECIALS if r not in keep]
    for _ in range(tries):
        toks, room_id, roles = _random_game(n, off)
        if not room_id:
            continue
        got = {r["role"] for r in roles.values()}
        if all(k in got for k in keep):
            return toks, room_id, roles, uid_map(roles)
        close_room(toks, room_id)
    return None, None, None, None


def test_sheriff_rules():
    """중립·마피아는 대상만, 시민은 함께 죽는다. 치료가 대상을 살려도 오인 사격 대가는 그대로."""
    toks, room_id, roles, uids = _sheriff_game(15, ["SHERIFF", "DOCTOR", "JESTER"])
    if not room_id:
        check("보안관 테스트 준비", False, "보안관·의사·광대가 함께 나오지 않았다")
        return

    sheriff, doctor, jester = (_pick(roles, "SHERIFF"), _pick(roles, "DOCTOR"),
                               _pick(roles, "JESTER"))
    mafias = [t for t, r in roles.items() if r["role"] == "MAFIA"]
    cits = [t for t, r in roles.items() if r["role"] == "CITIZEN"]

    s, v = rpc("my_game_view", sheriff, {"p_room_id": room_id})
    check("보안관은 시민 진영", v.get("team") == "CITIZEN", str(v.get("team")))

    s, b = rpc("submit_night_action", sheriff,
               {"p_room_id": room_id, "p_action": "SHERIFF", "p_target_uid": uids[sheriff]})
    check("보안관 자기 지목 차단", s >= 400 and "자신" in str(msg(b)), msg(b))
    s, b = rpc("submit_night_action", doctor,
               {"p_room_id": room_id, "p_action": "SHERIFF", "p_target_uid": uids[jester]})
    check("보안관이 아니면 제거 차단", s >= 400 and "사용할 수 없는" in str(msg(b)), msg(b))

    # 1일차 밤: 보안관 -> 광대(중립), 마피아 -> 시민0, 의사 -> 시민1
    s, b = rpc("submit_night_action", sheriff,
               {"p_room_id": room_id, "p_action": "SHERIFF", "p_target_uid": uids[jester]})
    check("보안관 제거 제출", s == 200, str(b))
    pass_night(room_id, roles, uids, victim_uid=uids[cits[0]], doctor_uid=uids[cits[1]])
    alive = alive_uids(room_id, toks[0])
    check("중립을 쏘면 대상만 죽는다",
          uids[jester] not in alive and uids[sheriff] in alive, "")
    check("밤에 죽은 광대는 이기지 않는다",
          _phase(room_id, toks[0]).get("phase") == "DAY", str(_phase(room_id, toks[0])))

    pass_day(room_id, roles, uids, uids[cits[2]])

    # 2일차 밤: 보안관 -> 마피아0, 마피아 -> 시민3, 의사 -> 시민4
    rpc("submit_night_action", sheriff,
        {"p_room_id": room_id, "p_action": "SHERIFF", "p_target_uid": uids[mafias[0]]})
    pass_night(room_id, roles, uids, victim_uid=uids[cits[3]], doctor_uid=uids[cits[4]])
    alive = alive_uids(room_id, toks[0])
    check("마피아를 쏘면 대상만 죽는다",
          uids[mafias[0]] not in alive and uids[sheriff] in alive, "")

    pass_day(room_id, roles, uids, uids[cits[5]])

    # 3일차 밤: 보안관 -> 시민6, 의사도 시민6 을 치료. 마피아 -> 시민7
    rpc("submit_night_action", sheriff,
        {"p_room_id": room_id, "p_action": "SHERIFF", "p_target_uid": uids[cits[6]]})
    pass_night(room_id, roles, uids, victim_uid=uids[cits[7]], doctor_uid=uids[cits[6]])
    alive = alive_uids(room_id, toks[0])
    check("의사가 보안관의 공격을 막는다", uids[cits[6]] in alive, "")
    check("시민을 쐈으면 대상이 살아도 보안관은 죽는다", uids[sheriff] not in alive, "")

    close_room(toks, room_id)


def test_sheriff_shoots_citizen():
    """시민을 쏘면 대상과 보안관이 함께 죽는다. 건너뛰기도 된다."""
    toks, room_id, roles, uids = _sheriff_game(8, ["SHERIFF"])
    if not room_id:
        check("보안관 오인 사격 준비", False, "보안관이 나오지 않았다")
        return
    sheriff = _pick(roles, "SHERIFF")
    cits = [t for t, r in roles.items() if r["role"] == "CITIZEN"]

    # 1일차 밤은 건너뛴다
    s, b = rpc("submit_night_action", sheriff,
               {"p_room_id": room_id, "p_action": "SHERIFF", "p_target_uid": None})
    check("보안관 건너뛰기 허용", s == 200, str(b))
    pass_night(room_id, roles, uids, victim_uid=uids[cits[0]])
    check("건너뛴 보안관은 살아 있다", uids[sheriff] in alive_uids(room_id, toks[0]), "")

    pass_day(room_id, roles, uids, uids[cits[1]])

    # 2일차 밤: 보안관 -> 시민2, 마피아 -> 시민3
    rpc("submit_night_action", sheriff,
        {"p_room_id": room_id, "p_action": "SHERIFF", "p_target_uid": uids[cits[2]]})
    pass_night(room_id, roles, uids, victim_uid=uids[cits[3]])
    alive = alive_uids(room_id, toks[0])
    check("시민을 쏘면 대상과 보안관이 함께 죽는다",
          uids[cits[2]] not in alive and uids[sheriff] not in alive, "")

    s, pubs = req("/rest/v1/public_results?select=payload&room_id=eq." + room_id
                  + "&kind=eq.NIGHT&day_number=eq.2", toks[0])
    deaths = (pubs[0]["payload"].get("nightDeaths") if pubs else None) or []
    check("보안관도 밤 사망자 목록에 나온다", uids[sheriff] in deaths, str(deaths)[:60])

    close_room(toks, room_id)


ALL.extend([test_sheriff_rules, test_sheriff_shoots_citizen])


# ------------------------------------------------------------------
# 위조범 (0033) — 랜덤 구성에서만 나온다
# ------------------------------------------------------------------

def _result(token, room_id, kind, day):
    s, v = rpc("my_game_view", token, {"p_room_id": room_id})
    for r in (v.get("privateResults") or []):
        if r["kind"] == kind and r["day"] == day:
            return r["payload"]
    return {}


def test_forger_police_detective():
    """위조한 사람을 조사하면 경찰은 반대 진영, 탐정은 진짜 직업이 빠진 후보를 받는다"""
    toks, room_id, roles, uids = _sheriff_game(15, ["FORGER", "POLICE", "DETECTIVE"])
    if not room_id:
        check("위조범 테스트 준비", False, "위조범·경찰·탐정이 함께 나오지 않았다")
        return

    forger, police, detective = (_pick(roles, "FORGER"), _pick(roles, "POLICE"),
                                 _pick(roles, "DETECTIVE"))
    mafia = _pick(roles, "MAFIA")
    cits = [t for t, r in roles.items() if r["role"] == "CITIZEN"]

    s, v = rpc("my_game_view", forger, {"p_room_id": room_id})
    check("위조범은 마피아 진영", v.get("team") == "MAFIA", str(v.get("team")))
    fs = v.get("forger") or {}
    check("15명 위조 횟수 3번", fs.get("limit") == 3 and fs.get("used") == 0, str(fs))
    check("위조범도 마피아 동료 목록을 본다",
          len(v.get("mafiaMembers") or []) == 4, str(len(v.get("mafiaMembers") or [])))

    s, b = rpc("submit_night_action", police,
               {"p_room_id": room_id, "p_action": "FORGE", "p_target_uid": uids[cits[0]]})
    check("위조범이 아니면 위조 차단", s >= 400 and "사용할 수 없는" in str(msg(b)), msg(b))

    # 1일차 밤: 시민0 위조. 경찰 -> 시민0, 탐정 -> 마피아(위조 안 함)
    s, b = rpc("submit_night_action", forger,
               {"p_room_id": room_id, "p_action": "FORGE", "p_target_uid": uids[cits[0]]})
    check("위조 제출", s == 200 and b.get("resolved") is False, str(b))
    s, v = rpc("my_game_view", forger, {"p_room_id": room_id})
    check("위조만으로는 마피아 투표를 낸 것이 아니다",
          v.get("nightActed") is False and (v.get("forger") or {}).get("tonight") == uids[cits[0]],
          str(v.get("forger")))

    pass_night(room_id, roles, uids, victim_uid=uids[cits[1]],
               police_uid=uids[cits[0]], detective_uid=uids[mafia])
    check("위조범 투표까지 내야 밤이 끝난다",
          _phase(room_id, toks[0]).get("phase") == "DAY", str(_phase(room_id, toks[0])))
    pay = _result(police, room_id, "POLICE", 1)
    check("위조된 시민을 경찰이 조사 -> 마피아 진영", pay.get("team") == "MAFIA", str(pay))
    pay = _result(detective, room_id, "DETECTIVE", 1)
    check("위조 안 된 마피아를 탐정이 조사 -> 후보에 마피아 있음",
          "MAFIA" in (pay.get("candidates") or []), str(pay))

    pass_day(room_id, roles, uids, uids[cits[2]])

    # 2일차 밤: 마피아 위조. 경찰·탐정 모두 그 마피아를 조사
    rpc("submit_night_action", forger,
        {"p_room_id": room_id, "p_action": "FORGE", "p_target_uid": uids[mafia]})
    pass_night(room_id, roles, uids, victim_uid=uids[cits[3]],
               police_uid=uids[mafia], detective_uid=uids[mafia])
    pay = _result(police, room_id, "POLICE", 2)
    check("위조된 마피아를 경찰이 조사 -> 시민 진영", pay.get("team") == "CITIZEN", str(pay))
    pay = _result(detective, room_id, "DETECTIVE", 2)
    cand = pay.get("candidates") or []
    check("위조된 마피아를 탐정이 조사 -> 진짜 직업이 빠진 후보 3개",
          "MAFIA" not in cand and len(cand) == 3, str(cand))

    s, v = rpc("my_game_view", forger, {"p_room_id": room_id})
    check("위조 2번 사용으로 기록", (v.get("forger") or {}).get("used") == 2, str(v.get("forger")))

    close_room(toks, room_id)


def test_forger_medium_and_limit():
    """사망자를 위조하면 영매가 오답을 받는다. 8명은 위조 1번뿐이다."""
    toks, room_id, roles, uids = _sheriff_game(8, ["FORGER", "MEDIUM"])
    if not room_id:
        check("위조범·영매 테스트 준비", False, "위조범·영매가 함께 나오지 않았다")
        return

    forger, medium, mafia = _pick(roles, "FORGER"), _pick(roles, "MEDIUM"), _pick(roles, "MAFIA")
    cits = [t for t, r in roles.items() if r["role"] == "CITIZEN"]

    s, v = rpc("my_game_view", forger, {"p_room_id": room_id})
    check("8명 위조 횟수 1번", (v.get("forger") or {}).get("limit") == 1, str(v.get("forger")))

    pass_night(room_id, roles, uids, victim_uid=uids[cits[0]])
    pass_day(room_id, roles, uids, uids[cits[1]])

    # 2일차 밤: 죽은 시민0 을 위조, 영매가 시민0 을 확인
    s, b = rpc("submit_night_action", forger,
               {"p_room_id": room_id, "p_action": "FORGE", "p_target_uid": uids[cits[0]]})
    check("사망자도 위조할 수 있다", s == 200, str(b))
    pass_night(room_id, roles, uids, victim_uid=uids[cits[2]], medium_uid=uids[cits[0]])
    pay = _result(medium, room_id, "MEDIUM", 2)
    check("위조된 시민을 영매가 확인 -> 마피아", pay.get("role") == "MAFIA", str(pay))

    # 마피아를 처형해 게임을 이어간다 (마피아1 vs 시민 진영3)
    pass_day(room_id, roles, uids, uids[mafia])
    check("3일차 밤으로", _phase(room_id, toks[0]).get("phase") == "NIGHT",
          str(_phase(room_id, toks[0])))

    s, b = rpc("submit_night_action", forger,
               {"p_room_id": room_id, "p_action": "FORGE", "p_target_uid": uids[forger]})
    check("횟수를 다 쓰면 위조 차단", s >= 400 and "위조 기회를 모두 썼습니다" in str(msg(b)), msg(b))

    close_room(toks, room_id)


ALL.extend([test_forger_police_detective, test_forger_medium_and_limit])


# ------------------------------------------------------------------
# 생존자 (0034) — 랜덤 구성에서만 나온다
# ------------------------------------------------------------------

def test_survivor_target():
    from harness import KEY
    want = {1: None, 2: None, 3: 2, 4: 2, 5: 4, 7: 4, 8: 6, 10: 6, 11: 8, 13: 8,
            14: 10, 15: 10, 16: 10, 17: 12, 50: 34}
    bad = []
    for m, w in want.items():
        s, got = rpc("survivor_target", KEY, {"p_max": m})
        if s != 200 or got != w:
            bad.append("%d일: %s" % (m, got))
    check("생존자 목표 날 (3~4일 2 · 5~7일 4 · ... · 14~15일 10)",
          not bad, "; ".join(bad) if bad else "1~50일")


def test_survivor_blocked_short_game():
    """최대 일수 2일이면 생존자만 켜져 있어도 배정되지 않는다"""
    from collections import Counter
    from stage2 import make_room
    off = [r for r in CITIZEN_SPECIALS + OTHER_SPECIALS if r != "SURVIVOR"]
    toks, room_id = make_room(5)
    if not room_id:
        check("생존자 제외 테스트 준비", False, "방 생성 실패")
        return
    rpc("set_timers", toks[0], {"p_room_id": room_id, "p_night": 30, "p_day": 60,
                                "p_max_days": 2})
    rpc("set_disabled_roles", toks[0], {"p_room_id": room_id, "p_disabled": off})
    rpc("start_game", toks[0], {"p_room_id": room_id})
    roles = {}
    for t in toks:
        s, b = rpc("my_role", t, {"p_room_id": room_id})
        if s == 200:
            roles[t] = b
    cc = Counter(r["role"] for r in roles.values())
    check("최대 2일이면 생존자 없음 (중립 자리는 시민)",
          len(roles) == 5 and "SURVIVOR" not in cc and cc.get("CITIZEN") == 4,
          str(dict(cc)))
    close_room(toks, room_id)


def test_survivor_wins():
    """목표 날의 낮이 끝날 때 살아 있으면 생존자 단독 승리"""
    from stage2 import make_room
    off = [r for r in CITIZEN_SPECIALS + OTHER_SPECIALS if r != "SURVIVOR"]
    toks, room_id = make_room(8)
    if not room_id:
        check("생존자 승리 테스트 준비", False, "방 생성 실패")
        return
    # 최대 4일 -> 목표 2일
    rpc("set_timers", toks[0], {"p_room_id": room_id, "p_night": 30, "p_day": 60,
                                "p_max_days": 4})
    rpc("set_disabled_roles", toks[0], {"p_room_id": room_id, "p_disabled": off})
    rpc("start_game", toks[0], {"p_room_id": room_id})
    roles = {}
    for t in toks:
        s, b = rpc("my_role", t, {"p_room_id": room_id})
        if s == 200:
            roles[t] = b
    uids = uid_map(roles)
    if "SURVIVOR" not in {r["role"] for r in roles.values()}:
        check("생존자 승리 준비", False, str([r["role"] for r in roles.values()]))
        close_room(toks, room_id)
        return

    survivor = _pick(roles, "SURVIVOR")
    mafias = [t for t, r in roles.items() if r["role"] == "MAFIA"]
    cits = [t for t, r in roles.items() if r["role"] == "CITIZEN"]

    s, v = rpc("my_game_view", survivor, {"p_room_id": room_id})
    check("생존자는 중립", v.get("team") == "NEUTRAL", str(v.get("team")))

    def split_night():
        # 마피아 표를 갈라 아무도 죽지 않게 한다
        rpc("submit_night_action", mafias[0],
            {"p_room_id": room_id, "p_action": "MAFIA_VOTE", "p_target_uid": uids[cits[3]]})
        rpc("submit_night_action", mafias[1],
            {"p_room_id": room_id, "p_action": "MAFIA_VOTE", "p_target_uid": uids[cits[4]]})

    split_night()
    pass_day(room_id, roles, uids, uids[cits[0]])
    st = _phase(room_id, toks[0])
    check("1일째 낮이 끝나도 게임은 계속 (목표 2일)",
          st.get("phase") == "NIGHT" and st.get("winner") is None, str(st))

    split_night()
    pass_day(room_id, roles, uids, uids[cits[1]])
    st = _phase(room_id, toks[0])
    check("2일째 낮이 끝날 때 살아 있으면 생존자 단독 승리",
          st.get("phase") == "ENDED" and st.get("winner") == "SURVIVOR", str(st))

    close_room(toks, room_id)


ALL.extend([test_survivor_target, test_survivor_blocked_short_game, test_survivor_wins])


# ------------------------------------------------------------------
# 투표 결과 시간 (0035) — 낮 투표 뒤 10초 동안 득표 수와 처형자 진영을 공개한다
# ------------------------------------------------------------------

def test_vote_result_phase():
    """낮 투표가 끝나면 DAY_RESULT(10초 고정)를 거쳐 다음 날 밤으로 간다"""
    toks, room_id, roles = make_game(5)
    if not room_id:
        check("투표 결과 시간 준비", False, "방 생성 실패")
        return
    uids = uid_map(roles)
    mafia = _pick(roles, "MAFIA")
    cits = [t for t, r in roles.items() if r["role"] == "CITIZEN"]

    # 밤에 의사가 공격 대상을 살려 5명 모두 낮으로 간다
    pass_night(room_id, roles, uids, victim_uid=uids[cits[0]], doctor_uid=uids[cits[0]])

    # --- 낮: 시민1 에게 4표, 시민0 에게 1표 ---
    last = None
    for t in roles:
        tgt = uids[cits[0]] if t == cits[1] else uids[cits[1]]
        s, last = rpc("submit_day_vote", t, {"p_room_id": room_id, "p_target_uid": tgt})
    check("전원 투표 후 자동 처리", isinstance(last, dict) and last.get("resolved") is True,
          str(last))

    st = _phase(room_id, toks[0])
    check("투표 뒤 결과 시간으로 (같은 날)",
          st.get("phase") == "DAY_RESULT" and st.get("day_number") == 1, str(st))

    s, b = rpc("tick_phase", toks[1], {"p_room_id": room_id})
    check("결과 시간은 10초 고정, 마감 전 tick 은 무시",
          s == 200 and b.get("resolved") is False and 0 < (b.get("remaining") or 0) <= 10,
          str(b))

    pay = _day_payload(room_id, toks[0], 1)
    votes = {v["uid"]: v["count"] for v in pay.get("votes") or []}
    check("득표 수 공개: 사람별",
          votes == {uids[cits[1]]: 4, uids[cits[0]]: 1}, str(pay.get("votes")))
    check("득표 수 공개: 처형자 4표",
          pay.get("executed") == uids[cits[1]] and pay.get("executedVotes") == 4, str(pay))
    check("처형자 진영 공개: 시민 진영",
          pay.get("executedTeam") == "CITIZEN" and pay.get("executedRole") is None, str(pay))

    # --- 결과 시간에는 투표·능력 불가, 생존자 대화 가능 ---
    s, b = rpc("submit_day_vote", mafia, {"p_room_id": room_id, "p_target_uid": uids[cits[0]]})
    check("결과 시간 투표 차단", s >= 400, msg(b))
    s, b = rpc("submit_night_action", mafia,
               {"p_room_id": room_id, "p_action": "MAFIA_VOTE", "p_target_uid": uids[cits[0]]})
    check("결과 시간 능력 차단", s >= 400, msg(b))
    s, b = rpc("send_chat", cits[0], {"p_room_id": room_id, "p_body": "결과 확인"})
    check("결과 시간 생존자 대화", s == 200 and b.get("channel") == "PUBLIC", str(b))
    s, b = rpc("send_chat", cits[1], {"p_room_id": room_id, "p_body": "억울"})
    check("결과 시간 사망자 대화 차단", s >= 400 and "사망한" in str(msg(b)), msg(b))

    # --- 10초가 지나면 다음 날 밤 ---
    b = skip_vote_result(room_id, toks[0])
    st = _phase(room_id, toks[0])
    check("결과 시간 뒤 2일차 밤으로",
          isinstance(b, dict) and b.get("resolved") is True
          and st.get("phase") == "NIGHT" and st.get("day_number") == 2, str(st))

    close_room(toks, room_id)


def test_vote_result_skipped_on_game_end():
    """투표로 게임이 끝나면 결과 시간 없이 바로 종료한다"""
    toks, room_id, roles = make_game(5)
    if not room_id:
        check("결과 시간 생략 준비", False, "방 생성 실패")
        return
    uids = uid_map(roles)
    pass_night(room_id, roles, uids, victim_uid=uids[_pick(roles, "POLICE")],
               doctor_uid=uids[_pick(roles, "POLICE")])
    pass_day(room_id, roles, uids, uids[_pick(roles, "MAFIA")])
    st = _phase(room_id, toks[0])
    check("마피아 처형 -> 결과 시간 없이 시민 승리",
          st.get("phase") == "ENDED" and st.get("winner") == "CITIZEN", str(st))
    close_room(toks, room_id)


ALL.extend([test_vote_result_phase, test_vote_result_skipped_on_game_end])
