"""
2단계 직업 테스트 (요구사항 §8.2 순서로 하나씩 추가한다)

e2e.py 에서 불러 쓴다. 단독 실행하지 않는다.
"""

from harness import KEY, check, msg, req, rpc, uid_of, user_pool


def make_game(n):
    """n명짜리 방을 만들고 게임을 시작한다. (토큰들, room_id, 직업맵) 반환."""
    toks = user_pool(n)
    s, b = rpc("create_room", toks[0], {"p_nickname": "P1"})
    if s != 200:
        return None, None, None
    room_id, code = b["room_id"], b["room_code"]
    for i, t in enumerate(toks[1:], start=2):
        rpc("join_room", t, {"p_code": code, "p_nickname": "P%d" % i})
        rpc("set_ready", t, {"p_room_id": room_id, "p_ready": True})
    rpc("start_game", toks[0], {"p_room_id": room_id})

    roles = {}
    for t in toks:
        s, b = rpc("my_role", t, {"p_room_id": room_id})
        if s == 200:
            roles[t] = b
    return toks, room_id, roles


# ------------------------------------------------------------------
# §8.2-1  마피아와 시민
# ------------------------------------------------------------------

def test_roles_mafia_citizen():
    # --- 구성표 (§5.1) ---
    bad = []
    for n in range(5, 16):
        s, b = rpc("role_composition", KEY, {"p_count": n})
        if s != 200 or not isinstance(b, list) or len(b) != n:
            bad.append(n)
    check("구성표 5~15명 합계 일치", not bad, "불일치 %s" % (bad or "없음"))

    s, b = rpc("role_composition", KEY, {"p_count": 4})
    check("4명 구성표 거부", s >= 400 and "지원하지 않습니다" in str(msg(b)), msg(b))

    toks, room_id, roles = make_game(5)
    if not room_id:
        check("5명 게임 시작", False, "방 생성 실패")
        return
    check("전원 직업 배정", len(roles) == 5, "%d/5 배정" % len(roles))

    got = sorted(r["role"] for r in roles.values())
    want = sorted(["MAFIA", "POLICE", "DOCTOR", "CITIZEN", "CITIZEN"])
    check("5명 구성 일치", got == want, ",".join(got))

    # --- 비밀 보장 (§6.2) ---
    s, b = req("/rest/v1/private_roles?select=role&room_id=eq." + room_id, toks[1])
    check("private_roles 직접 조회 차단", s >= 400, "HTTP %d %s" % (s, str(msg(b))[:38]))

    s, b = req("/rest/v1/night_actions?select=target_uid&room_id=eq." + room_id, toks[1])
    check("night_actions 직접 조회 차단", s >= 400, "HTTP %d %s" % (s, str(msg(b))[:38]))

    mafia_tok = next(t for t, r in roles.items() if r["role"] == "MAFIA")
    civ_toks = [t for t, r in roles.items() if r["role"] != "MAFIA"]

    check("마피아는 명단을 본다", roles[mafia_tok].get("mafiaMembers") is not None,
          "명단 %d명" % len(roles[mafia_tok].get("mafiaMembers") or []))
    check("시민은 명단을 못 본다",
          all(roles[t].get("mafiaMembers") is None for t in civ_toks), "")

    # --- 밤: 마피아 공격 ---
    victim = civ_toks[0]
    victim_uid = uid_of(victim)

    s, b = rpc("submit_night_action", civ_toks[1],
               {"p_room_id": room_id, "p_action": "MAFIA_VOTE", "p_target_uid": victim_uid})
    check("비마피아 밤행동 차단", s >= 400 and "마피아만" in str(msg(b)), msg(b))

    s, b = rpc("submit_night_action", mafia_tok,
               {"p_room_id": room_id, "p_action": "MAFIA_VOTE", "p_target_uid": victim_uid})
    check("마피아 공격 제출", s == 200 and isinstance(b, dict) and b.get("resolved") is True, str(b))

    s, b = req("/rest/v1/players?select=uid,alive&room_id=eq." + room_id, mafia_tok)
    dead = [p for p in b if not p["alive"]] if isinstance(b, list) else []
    check("공격 대상 사망", len(dead) == 1 and dead[0]["uid"] == victim_uid, "사망 %d명" % len(dead))

    s, b = req("/rest/v1/rooms?select=phase,day_number&id=eq." + room_id, mafia_tok)
    check("밤 -> 낮 전환", bool(b) and b[0]["phase"] == "DAY" and b[0]["day_number"] == 1,
          ("%s %s일차" % (b[0]["phase"], b[0]["day_number"])) if b else "?")

    s, b = req("/rest/v1/public_results?select=payload&room_id=eq." + room_id + "&kind=eq.NIGHT",
               civ_toks[1])
    check("밤 결과 공개", s == 200 and bool(b) and "nightDeaths" in b[0]["payload"], str(b)[:46])

    # --- 죽은 사람 차단 (§6.2) ---
    s, b = rpc("submit_day_vote", victim, {"p_room_id": room_id, "p_target_uid": victim_uid})
    check("사망자 투표 차단", s >= 400 and "사망한" in str(msg(b)), msg(b))

    # --- 낮: 마피아를 처형 ---
    mafia_uid = uid_of(mafia_tok)

    s, b = rpc("submit_day_vote", mafia_tok,
               {"p_room_id": room_id, "p_target_uid": uid_of(civ_toks[1])})
    check("낮 투표 제출", s == 200, str(b)[:38])

    s, b = rpc("submit_day_vote", mafia_tok, {"p_room_id": room_id, "p_target_uid": mafia_uid})
    check("투표 변경 차단", s >= 400 and "변경할 수 없습니다" in str(msg(b)), msg(b))

    last = None
    for t in civ_toks[1:]:
        s, last = rpc("submit_day_vote", t, {"p_room_id": room_id, "p_target_uid": mafia_uid})
    check("전원 투표 후 자동 처리",
          isinstance(last, dict) and last.get("resolved") is True, str(last))

    s, b = req("/rest/v1/rooms?select=phase,winner&id=eq." + room_id, mafia_tok)
    check("마피아 전멸 -> 시민 승리 (§4.2)",
          bool(b) and b[0]["phase"] == "ENDED" and b[0]["winner"] == "CITIZEN",
          ("%s / %s" % (b[0]["phase"], b[0]["winner"])) if b else "?")

    s, b = rpc("final_roles", civ_toks[1], {"p_room_id": room_id})
    check("종료 후 전체 직업 공개", s == 200 and isinstance(b, list) and len(b) == 5,
          "%d명 공개" % (len(b) if isinstance(b, list) else -1))

    rpc("leave_room", toks[0], {"p_room_id": room_id})


# ------------------------------------------------------------------
# §4.1  광대 단독 승리 (구성표상 7명부터 배정되므로 지금 검증한다)
# ------------------------------------------------------------------

def test_jester_win():
    toks, room_id, roles = make_game(7)
    if not room_id:
        check("7명 게임 시작", False, "방 생성 실패")
        return

    got = sorted(r["role"] for r in roles.values())
    want = sorted(["MAFIA", "MAFIA", "POLICE", "DOCTOR", "JESTER", "CITIZEN", "CITIZEN"])
    check("7명 구성 일치", got == want, ",".join(got))

    jester_tok = next(t for t, r in roles.items() if r["role"] == "JESTER")
    jester_uid = uid_of(jester_tok)
    mafia_toks = [t for t, r in roles.items() if r["role"] == "MAFIA"]
    # 광대가 밤에 죽으면 승리하지 못하므로(§2.10) 다른 사람을 공격한다
    prey = next(t for t, r in roles.items() if r["role"] not in ("MAFIA", "JESTER"))
    prey_uid = uid_of(prey)

    b = None
    for t in mafia_toks:
        s, b = rpc("submit_night_action", t,
                   {"p_room_id": room_id, "p_action": "MAFIA_VOTE", "p_target_uid": prey_uid})
    check("마피아 2명 합의 공격",
          isinstance(b, dict) and b.get("resolved") is True, str(b))

    for t in [x for x in toks if x != prey]:
        rpc("submit_day_vote", t, {"p_room_id": room_id, "p_target_uid": jester_uid})

    s, b = req("/rest/v1/rooms?select=phase,winner&id=eq." + room_id, jester_tok)
    check("광대 처형 -> 광대 단독 승리 (§4.1)",
          bool(b) and b[0]["phase"] == "ENDED" and b[0]["winner"] == "JESTER",
          ("%s / %s" % (b[0]["phase"], b[0]["winner"])) if b else "?")

    rpc("leave_room", toks[0], {"p_room_id": room_id})


# ------------------------------------------------------------------
# §2.2  밤 투표 동점
# ------------------------------------------------------------------

def test_night_tie():
    toks, room_id, roles = make_game(7)
    if not room_id:
        check("동점 테스트 준비", False, "방 생성 실패")
        return

    mafia_toks = [t for t, r in roles.items() if r["role"] == "MAFIA"]
    others = [t for t, r in roles.items() if r["role"] != "MAFIA"]

    # 두 마피아가 서로 다른 사람을 지목 -> 1표씩 동점
    rpc("submit_night_action", mafia_toks[0],
        {"p_room_id": room_id, "p_action": "MAFIA_VOTE", "p_target_uid": uid_of(others[0])})
    rpc("submit_night_action", mafia_toks[1],
        {"p_room_id": room_id, "p_action": "MAFIA_VOTE", "p_target_uid": uid_of(others[1])})

    s, b = req("/rest/v1/players?select=alive&room_id=eq." + room_id, mafia_toks[0])
    dead = sum(1 for p in b if not p["alive"]) if isinstance(b, list) else -1
    check("밤 동점 -> 사망자 없음 (§2.2)", dead == 0, "사망 %d명" % dead)

    s, b = req("/rest/v1/rooms?select=phase&id=eq." + room_id, mafia_toks[0])
    check("동점이어도 낮으로 진행", bool(b) and b[0]["phase"] == "DAY",
          b[0]["phase"] if b else "?")

    rpc("leave_room", toks[0], {"p_room_id": room_id})


ALL = [test_roles_mafia_citizen, test_jester_win, test_night_tie]
