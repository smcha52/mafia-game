"""
2단계 직업 테스트 (요구사항 §8.2 순서로 하나씩 추가한다)

e2e.py 에서 불러 쓴다. 단독 실행하지 않는다.
"""

from harness import KEY, check, msg, req, rpc, uid_of, user_pool


def uid_map(roles):
    """토큰 -> uid 를 한 번만 조회해 둔다."""
    return {t: uid_of(t) for t in roles}


def alive_uids(room_id, token):
    s, b = req("/rest/v1/players?select=uid,alive&room_id=eq." + room_id, token)
    return {p["uid"] for p in b if p["alive"]} if isinstance(b, list) else set()


def pass_night(room_id, roles, uids, victim_uid=None, police_uid=None, doctor_uid=None):
    """밤에 행동하는 직업(마피아·경찰)을 모두 제출시켜 밤을 넘긴다.

    victim_uid 를 주지 않으면 마피아는 살아 있는 아무나를 공격한다.
    대상이 죽어 있으면 서버가 거부하므로 항상 생존자 중에서 고른다.
    """
    any_tok = next(iter(roles))
    alive = alive_uids(room_id, any_tok)
    if victim_uid not in alive:
        victim_uid = None
    if police_uid not in alive:
        police_uid = None
    if doctor_uid not in alive:
        doctor_uid = None

    last = None
    for t, r in roles.items():
        # 밤이 이미 끝났으면 더 제출하지 않는다.
        # 계속 보내면 "밤에만 능력을 사용할 수 있습니다" 오류가 마지막 응답이 된다.
        if isinstance(last, dict) and last.get("resolved") is True:
            break
        if uids[t] not in alive:
            continue
        if r["role"] == "MAFIA":
            tgt = victim_uid or next(u for u in alive if u != uids[t])
            s, last = rpc("submit_night_action", t,
                          {"p_room_id": room_id, "p_action": "MAFIA_VOTE", "p_target_uid": tgt})
        elif r["role"] == "POLICE":
            tgt = police_uid or next(iter(alive))
            s, last = rpc("submit_night_action", t,
                          {"p_room_id": room_id, "p_action": "POLICE", "p_target_uid": tgt})
        elif r["role"] == "DOCTOR":
            # 연속 치료 금지에 걸리지 않도록 직전 대상이 아닌 사람을 고른다
            s, mv = rpc("my_game_view", t, {"p_room_id": room_id})
            last_t = mv.get("lastTargetId") if s == 200 else None
            tgt = doctor_uid if doctor_uid and doctor_uid != last_t else None
            if tgt is None:
                tgt = next(u for u in alive if u != last_t)
            s, last = rpc("submit_night_action", t,
                          {"p_room_id": room_id, "p_action": "DOCTOR", "p_target_uid": tgt})
    return last


def pass_day(room_id, roles, uids, target_uid):
    """살아 있는 전원이 target 에게 투표해 낮을 넘긴다."""
    any_tok = next(iter(roles))
    alive = alive_uids(room_id, any_tok)
    last = None
    for t in roles:
        if isinstance(last, dict) and last.get("resolved") is True:
            break
        if uids[t] not in alive:
            continue
        s, last = rpc("submit_day_vote", t,
                      {"p_room_id": room_id, "p_target_uid": target_uid})
    return last


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
    check("비마피아 밤행동 차단", s >= 400 and "사용할 수 없는" in str(msg(b)), msg(b))

    s, b = rpc("submit_night_action", mafia_tok,
               {"p_room_id": room_id, "p_action": "MAFIA_VOTE", "p_target_uid": victim_uid})
    check("마피아만 제출 시 밤 유지", s == 200 and b.get("resolved") is False, str(b))

    # 5명 구성에는 경찰·의사가 있으므로 그들까지 제출해야 밤이 끝난다.
    # 의사는 공격 대상이 아닌 사람을 치료해야 victim 이 실제로 죽는다.
    uids = uid_map(roles)
    b = pass_night(room_id, roles, uids,
                   victim_uid=victim_uid,
                   police_uid=uids[mafia_tok],
                   doctor_uid=uids[mafia_tok])
    check("밤 행동 직업 전원 제출 시 종료",
          isinstance(b, dict) and b.get("resolved") is True, str(b))

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

    uids = uid_map(roles)
    b = pass_night(room_id, roles, uids, victim_uid=prey_uid)
    check("마피아 2명 합의 공격",
          isinstance(b, dict) and b.get("resolved") is True, str(b))

    pass_day(room_id, roles, uids, jester_uid)

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
    # 나머지 밤 직업(경찰·의사)도 제출해야 밤이 끝난다.
    # 마피아 표는 이미 갈라놓았으므로 pass_night 이 덮어써도 동점이 유지되도록
    # 마피아를 제외하고 제출시킨다.
    uids = uid_map(roles)
    non_mafia = {t: r for t, r in roles.items() if r["role"] != "MAFIA"}
    pass_night(room_id, non_mafia, uids, police_uid=uids[others[0]])

    s, b = req("/rest/v1/players?select=alive&room_id=eq." + room_id, mafia_toks[0])
    dead = sum(1 for p in b if not p["alive"]) if isinstance(b, list) else -1
    check("밤 동점 -> 사망자 없음 (§2.2)", dead == 0, "사망 %d명" % dead)

    s, b = req("/rest/v1/rooms?select=phase&id=eq." + room_id, mafia_toks[0])
    check("동점이어도 낮으로 진행", bool(b) and b[0]["phase"] == "DAY",
          b[0]["phase"] if b else "?")

    rpc("leave_room", toks[0], {"p_room_id": room_id})


ALL = [test_roles_mafia_citizen, test_jester_win, test_night_tie]


# ------------------------------------------------------------------
# 진행 화면용 조회 (my_game_view) — UI 가 이 값으로 그려진다
# ------------------------------------------------------------------

def test_game_view():
    toks, room_id, roles = make_game(7)
    if not room_id:
        check("화면조회 준비", False, "방 생성 실패")
        return

    mafia = [t for t, r in roles.items() if r["role"] == "MAFIA"]
    plain = [t for t, r in roles.items() if r["role"] not in ("MAFIA", "SPY")]

    # --- 밤 시작 직후 ---
    s, v = rpc("my_game_view", mafia[0], {"p_room_id": room_id})
    ok = (s == 200 and v.get("role") == "MAFIA" and v.get("team") == "MAFIA"
          and v.get("alive") is True and v.get("nightSubmitted") is None)
    check("마피아 초기 화면정보", ok, "role=%s night=%s" % (v.get("role"), v.get("nightSubmitted")))

    check("마피아 진행표시 제공",
          isinstance(v.get("nightProgress"), dict)
          and v["nightProgress"].get("expected") == 2
          and v["nightProgress"].get("submitted") == 0,
          str(v.get("nightProgress")))

    check("마피아 동료명단 포함",
          isinstance(v.get("mafiaMembers"), list) and len(v["mafiaMembers"]) == 2,
          "%d명" % len(v.get("mafiaMembers") or []))

    s, v2 = rpc("my_game_view", plain[0], {"p_room_id": room_id})
    check("시민 동료명단 없음", v2.get("mafiaMembers") is None, str(v2.get("mafiaMembers")))
    check("시민 진행표시 없음", v2.get("nightProgress") is None, str(v2.get("nightProgress")))

    # --- 한 명만 제출한 상태 ---
    target_uid = uid_of(plain[0])
    rpc("submit_night_action", mafia[0],
        {"p_room_id": room_id, "p_action": "MAFIA_VOTE", "p_target_uid": target_uid})

    s, v = rpc("my_game_view", mafia[0], {"p_room_id": room_id})
    check("제출 후 내 선택 복원", v.get("nightSubmitted") == target_uid,
          str(v.get("nightSubmitted"))[:36])
    check("동료 진행 1/2 표시",
          v.get("nightProgress", {}).get("submitted") == 1, str(v.get("nightProgress")))

    # 다른 마피아에게는 "누구를 골랐는지" 가 보이지 않아야 한다
    s, vm = rpc("my_game_view", mafia[1], {"p_room_id": room_id})
    check("동료의 선택은 안 보인다", vm.get("nightSubmitted") is None, str(vm.get("nightSubmitted")))

    # --- 낮으로 넘긴 뒤 (밤 직업 전원 제출) ---
    uids = uid_map(roles)
    # 의사가 대상을 치료하면 죽지 않으므로 다른 사람을 치료시킨다
    pass_night(room_id, roles, uids,
               victim_uid=target_uid, doctor_uid=uids[mafia[0]])

    s, v = rpc("my_game_view", mafia[0], {"p_room_id": room_id})
    check("낮 투표 인원 6명", v.get("dayProgress", {}).get("expected") == 6,
          str(v.get("dayProgress")))

    # 사망자 화면
    s, vd = rpc("my_game_view", plain[0], {"p_room_id": room_id})
    check("사망자 alive=false", vd.get("alive") is False, str(vd.get("alive")))

    voter = mafia[0]
    rpc("submit_day_vote", voter, {"p_room_id": room_id, "p_target_uid": uid_of(mafia[1])})
    s, v = rpc("my_game_view", voter, {"p_room_id": room_id})
    check("낮 투표 후 내 표 복원", v.get("daySubmitted") == uid_of(mafia[1]),
          str(v.get("daySubmitted"))[:36])

    rpc("leave_room", toks[0], {"p_room_id": room_id})


ALL.append(test_game_view)


# ------------------------------------------------------------------
# 페이즈 제한시간
# ------------------------------------------------------------------

def make_room(n, night=None, day=None):
    """게임을 시작하지 않은 채로 방만 만든다. 필요하면 제한시간을 바꾼다."""
    toks = user_pool(n)
    s, b = rpc("create_room", toks[0], {"p_nickname": "P1"})
    if s != 200:
        return None, None
    room_id, code = b["room_id"], b["room_code"]
    for i, t in enumerate(toks[1:], start=2):
        rpc("join_room", t, {"p_code": code, "p_nickname": "P%d" % i})
        rpc("set_ready", t, {"p_room_id": room_id, "p_ready": True})
    if night is not None:
        rpc("set_timers", toks[0], {"p_room_id": room_id, "p_night": night, "p_day": day or 180})
    return toks, room_id


def test_phase_timer():
    import time

    toks, room_id = make_room(5)
    if not room_id:
        check("제한시간 준비", False, "방 생성 실패")
        return

    # --- set_timers 권한 ---
    s, b = rpc("set_timers", toks[1], {"p_room_id": room_id, "p_night": 30, "p_day": 60})
    check("비방장 제한시간 변경 차단", s >= 400 and "방장만" in str(msg(b)), msg(b))

    s, b = rpc("set_timers", toks[0], {"p_room_id": room_id, "p_night": 12, "p_day": 60})
    check("방장 제한시간 변경", s in (200, 204), "HTTP %d" % s)

    s, b = req("/rest/v1/rooms?select=night_seconds,day_seconds,phase_deadline&id=eq." + room_id,
               toks[0])
    check("대기실엔 마감 없음",
          bool(b) and b[0]["night_seconds"] == 12 and b[0]["phase_deadline"] is None,
          "night=%s deadline=%s" % (b[0]["night_seconds"], b[0]["phase_deadline"]) if b else "?")

    # --- 시작하면 마감이 잡힌다 ---
    rpc("start_game", toks[0], {"p_room_id": room_id})
    s, b = req("/rest/v1/rooms?select=phase,phase_deadline&id=eq." + room_id, toks[0])
    check("시작 시 마감 설정", bool(b) and b[0]["phase_deadline"] is not None,
          str(b[0]["phase_deadline"])[:19] if b else "?")

    s, b = rpc("set_timers", toks[0], {"p_room_id": room_id, "p_night": 30, "p_day": 60})
    check("진행 중 제한시간 변경 차단", s >= 400 and "대기실에서만" in str(msg(b)), msg(b))

    # --- 마감 전에는 넘어가지 않는다 ---
    s, b = rpc("tick_phase", toks[1], {"p_room_id": room_id})
    check("마감 전 tick 은 무시", s == 200 and b.get("resolved") is False
          and (b.get("remaining") or 0) > 0, str(b))

    # --- 마감이 지나면 아무도 제출하지 않아도 넘어간다 ---
    time.sleep(13)
    s, b = rpc("tick_phase", toks[1], {"p_room_id": room_id})
    check("마감 후 자동 진행", s == 200 and b.get("resolved") is True, str(b))

    s, b = req("/rest/v1/players?select=alive&room_id=eq." + room_id, toks[0])
    dead = sum(1 for p in b if not p["alive"]) if isinstance(b, list) else -1
    check("미제출 밤은 사망자 없음", dead == 0, "사망 %d명" % dead)

    s, b = req("/rest/v1/rooms?select=phase,day_number,phase_deadline&id=eq." + room_id, toks[0])
    check("낮으로 전환 + 새 마감",
          bool(b) and b[0]["phase"] == "DAY" and b[0]["phase_deadline"] is not None,
          "%s / %s" % (b[0]["phase"], str(b[0]["phase_deadline"])[:19]) if b else "?")

    # --- 중복 tick 은 한 번만 ---
    s, b1 = rpc("tick_phase", toks[1], {"p_room_id": room_id})
    s, b2 = rpc("tick_phase", toks[2], {"p_room_id": room_id})
    check("중복 tick 무해", b1.get("resolved") is False and b2.get("resolved") is False,
          "%s %s" % (b1.get("resolved"), b2.get("resolved")))

    # --- 전원 제출하면 시간 안 기다리고 즉시 진행 ---
    s, pl = req("/rest/v1/players?select=uid,alive&room_id=eq." + room_id, toks[0])
    alive_uids = [p["uid"] for p in pl if p["alive"]]
    last = None
    for t in toks:
        s, last = rpc("submit_day_vote", t, {"p_room_id": room_id, "p_target_uid": alive_uids[0]})
    check("전원 제출 시 즉시 진행",
          isinstance(last, dict) and last.get("resolved") is True, str(last))

    rpc("leave_room", toks[0], {"p_room_id": room_id})


ALL.append(test_phase_timer)


# ------------------------------------------------------------------
# §8.2-2  경찰
# ------------------------------------------------------------------

def test_role_police():
    toks, room_id, roles = make_game(7)
    if not room_id:
        check("경찰 테스트 준비", False, "방 생성 실패")
        return

    police = next(t for t, r in roles.items() if r["role"] == "POLICE")
    mafias = [t for t, r in roles.items() if r["role"] == "MAFIA"]
    jester = next(t for t, r in roles.items() if r["role"] == "JESTER")
    doctor = next(t for t, r in roles.items() if r["role"] == "DOCTOR")

    # --- 권한 ---
    s, b = rpc("submit_night_action", doctor,
               {"p_room_id": room_id, "p_action": "POLICE", "p_target_uid": uid_of(mafias[0])})
    check("비경찰 조사 차단", s >= 400 and "사용할 수 없는" in str(msg(b)), msg(b))

    uids = uid_map(roles)
    citizen = next(t for t, r in roles.items() if r["role"] == "CITIZEN")

    # --- 마피아만 제출해도 밤이 끝나면 안 된다 ---
    for t in mafias:
        s, b = rpc("submit_night_action", t,
                   {"p_room_id": room_id, "p_action": "MAFIA_VOTE", "p_target_uid": uids[citizen]})
    check("경찰 미제출 시 밤 유지", isinstance(b, dict) and b.get("resolved") is False, str(b))

    s, b = req("/rest/v1/rooms?select=phase&id=eq." + room_id, police)
    check("아직 밤", bool(b) and b[0]["phase"] == "NIGHT", b[0]["phase"] if b else "?")

    # --- 경찰이 마피아를 조사, 의사는 다른 사람을 치료 ---
    b = pass_night(room_id, roles, uids,
                   victim_uid=uids[citizen],
                   police_uid=uids[mafias[0]],
                   doctor_uid=uids[doctor])
    check("경찰 제출로 밤 종료", isinstance(b, dict) and b.get("resolved") is True, str(b))

    s, v = rpc("my_game_view", police, {"p_room_id": room_id})
    res = [r for r in (v.get("privateResults") or []) if r["kind"] == "POLICE"]
    check("경찰 조사 결과 도착", len(res) == 1, "%d건" % len(res))
    check("마피아 -> 마피아 진영",
          bool(res) and res[0]["payload"]["team"] == "MAFIA",
          res[0]["payload"]["team"] if res else "?")

    # --- 결과는 경찰에게만 ---
    s, v2 = rpc("my_game_view", mafias[0], {"p_room_id": room_id})
    check("다른 사람은 결과 없음", not (v2.get("privateResults") or []),
          str(v2.get("privateResults")))

    s, b = req("/rest/v1/private_results?select=payload&room_id=eq." + room_id, mafias[0])
    check("private_results 직접 조회 차단", s >= 400, "HTTP %d" % s)

    # --- 2일차: 광대를 조사하면 중립 진영 (§2.3) ---
    # 광대를 처형하면 게임이 끝나므로(§4.1) 마피아 한 명을 처형한다
    pass_day(room_id, roles, uids, uids[mafias[0]])

    s, b = req("/rest/v1/rooms?select=phase,day_number,winner&id=eq." + room_id, police)
    if b and b[0]["phase"] == "NIGHT":
        # 죽은 사람은 지목할 수 없으므로 pass_night 이 생존자 중에서 고른다
        pass_night(room_id, roles, uids, police_uid=uids[jester])

        s, v = rpc("my_game_view", police, {"p_room_id": room_id})
        res2 = [r for r in (v.get("privateResults") or [])
                if r["kind"] == "POLICE" and r["day"] == 2]
        check("광대 -> 중립 진영 (§2.3)",
              bool(res2) and res2[0]["payload"]["team"] == "NEUTRAL",
              res2[0]["payload"]["team"] if res2 else "결과 없음")
        check("결과가 누적된다",
              len(v.get("privateResults") or []) == 2,
              "%d건" % len(v.get("privateResults") or []))
    else:
        check("광대 -> 중립 진영 (§2.3)", False,
              "2일차 진입 실패 phase=%s" % (b[0]["phase"] if b else "?"))
        check("결과가 누적된다", False, "건너뜀")

    rpc("leave_room", toks[0], {"p_room_id": room_id})


def test_police_dead_blocked():
    """사망한 경찰은 조사할 수 없다 (§6.2)

    7명에서는 경찰 사망 + 시민 처형이면 마피아 2 vs 시민 2 가 되어
    §4.3 으로 게임이 끝난다. 2일차 밤을 보려면 9명이 필요하다.
    """
    toks, room_id, roles = make_game(9)
    if not room_id:
        check("사망 경찰 테스트 준비", False, "방 생성 실패")
        return

    police = next(t for t, r in roles.items() if r["role"] == "POLICE")
    mafias = [t for t, r in roles.items() if r["role"] == "MAFIA"]
    uids = uid_map(roles)
    # 광대를 처형하면 게임이 끝나므로(§4.1) 처형 대상은 시민으로 고른다
    victim_day = next(t for t, r in roles.items() if r["role"] == "CITIZEN")

    # 마피아가 경찰을 공격, 경찰은 조사 후 사망.
    # 의사가 경찰을 치료하면 살아나므로 의사 자신을 치료시킨다 (§2.4 자가 치료 허용)
    doctor_tok = next(t for t, r in roles.items() if r["role"] == "DOCTOR")
    pass_night(room_id, roles, uids,
               victim_uid=uids[police],
               police_uid=uids[mafias[0]],
               doctor_uid=uids[doctor_tok])

    s, v = rpc("my_game_view", police, {"p_room_id": room_id})
    check("조사한 밤에 죽어도 결과는 받는다",
          v.get("alive") is False and len(v.get("privateResults") or []) == 1,
          "alive=%s 결과=%d건" % (v.get("alive"), len(v.get("privateResults") or [])))

    # 낮을 넘겨 2일차 밤으로
    pass_day(room_id, roles, uids, uids[victim_day])

    s, b = req("/rest/v1/rooms?select=phase,winner&id=eq." + room_id, mafias[0])
    if b and b[0]["phase"] == "NIGHT":
        s, b2 = rpc("submit_night_action", police,
                    {"p_room_id": room_id, "p_action": "POLICE", "p_target_uid": uids[mafias[0]]})
        check("사망 경찰 조사 차단", s >= 400 and "사망한" in str(msg(b2)), msg(b2))
    else:
        check("사망 경찰 조사 차단", False,
              "2일차 밤 진입 실패 phase=%s winner=%s"
              % (b[0]["phase"], b[0]["winner"]) if b else "?")

    rpc("leave_room", toks[0], {"p_room_id": room_id})


ALL.extend([test_role_police, test_police_dead_blocked])


# ------------------------------------------------------------------
# §8.2-3  의사
# ------------------------------------------------------------------

def test_role_doctor():
    toks, room_id, roles = make_game(7)
    if not room_id:
        check("의사 테스트 준비", False, "방 생성 실패")
        return

    uids = uid_map(roles)
    doctor = next(t for t, r in roles.items() if r["role"] == "DOCTOR")
    police = next(t for t, r in roles.items() if r["role"] == "POLICE")
    mafias = [t for t, r in roles.items() if r["role"] == "MAFIA"]
    citizen = next(t for t, r in roles.items() if r["role"] == "CITIZEN")

    # --- 권한 ---
    s, b = rpc("submit_night_action", citizen,
               {"p_room_id": room_id, "p_action": "DOCTOR", "p_target_uid": uids[citizen]})
    check("비의사 치료 차단", s >= 400 and "사용할 수 없는" in str(msg(b)), msg(b))

    # --- 자기 자신 치료 가능 (§2.4) ---
    s, b = rpc("submit_night_action", doctor,
               {"p_room_id": room_id, "p_action": "DOCTOR", "p_target_uid": uids[doctor]})
    check("의사 자가 치료 허용", s == 200, str(b)[:40])

    # --- 치료 대상을 공격 대상으로 바꿔 살려낸다 ---
    s, b = rpc("submit_night_action", doctor,
               {"p_room_id": room_id, "p_action": "DOCTOR", "p_target_uid": uids[citizen]})
    check("치료 대상 변경 가능", s == 200, str(b)[:40])

    for t in mafias:
        rpc("submit_night_action", t,
            {"p_room_id": room_id, "p_action": "MAFIA_VOTE", "p_target_uid": uids[citizen]})
    s, b = rpc("submit_night_action", police,
               {"p_room_id": room_id, "p_action": "POLICE", "p_target_uid": uids[mafias[0]]})
    check("밤 종료", isinstance(b, dict) and b.get("resolved") is True, str(b))

    s, b = req("/rest/v1/players?select=uid,alive&room_id=eq." + room_id, doctor)
    dead = [p for p in b if not p["alive"]] if isinstance(b, list) else []
    check("치료로 공격 무효 (§2.4)", len(dead) == 0, "사망 %d명" % len(dead))

    s, b = req("/rest/v1/public_results?select=payload&room_id=eq." + room_id
               + "&kind=eq.NIGHT&day_number=eq.1", citizen)
    check("공개 결과엔 사망자 없음만",
          bool(b) and b[0]["payload"]["nightDeaths"] == [], str(b[0]["payload"]) if b else "?")

    s, v = rpc("my_game_view", doctor, {"p_room_id": room_id})
    heal = [r for r in (v.get("privateResults") or []) if r["kind"] == "DOCTOR"]
    check("의사만 치료 성공을 안다", len(heal) == 1, "%d건" % len(heal))

    s, v2 = rpc("my_game_view", citizen, {"p_room_id": room_id})
    check("살아난 본인도 모른다", not (v2.get("privateResults") or []),
          str(v2.get("privateResults")))

    # --- 연속 치료 금지 (§2.4, §6.3) ---
    check("직전 대상 기록됨", v.get("lastTargetId") == uids[citizen],
          str(v.get("lastTargetId"))[:36])

    pass_day(room_id, roles, uids, uids[mafias[0]])
    s, b = req("/rest/v1/rooms?select=phase&id=eq." + room_id, doctor)
    if b and b[0]["phase"] == "NIGHT":
        s, b2 = rpc("submit_night_action", doctor,
                    {"p_room_id": room_id, "p_action": "DOCTOR", "p_target_uid": uids[citizen]})
        check("연속 치료 차단 (§2.4)",
              s >= 400 and "연속해서 치료할 수 없습니다" in str(msg(b2)), msg(b2))

        s, b3 = rpc("submit_night_action", doctor,
                    {"p_room_id": room_id, "p_action": "DOCTOR", "p_target_uid": uids[doctor]})
        check("다른 사람은 치료 가능", s == 200, str(b3)[:40])
    else:
        check("연속 치료 차단 (§2.4)", False, "2일차 밤 진입 실패")
        check("다른 사람은 치료 가능", False, "건너뜀")

    rpc("leave_room", toks[0], {"p_room_id": room_id})


def test_doctor_cannot_save_execution():
    """치료는 밤 공격만 막는다. 낮 처형은 막지 못한다."""
    toks, room_id, roles = make_game(7)
    if not room_id:
        check("처형 방어 테스트 준비", False, "방 생성 실패")
        return

    uids = uid_map(roles)
    doctor = next(t for t, r in roles.items() if r["role"] == "DOCTOR")
    citizen = next(t for t, r in roles.items() if r["role"] == "CITIZEN")

    # 밤에 시민을 치료해 두고, 낮에 그 시민을 처형한다
    pass_night(room_id, roles, uids, doctor_uid=uids[citizen])
    pass_day(room_id, roles, uids, uids[citizen])

    s, b = req("/rest/v1/players?select=uid,alive&room_id=eq." + room_id, doctor)
    target = next((p for p in b if p["uid"] == uids[citizen]), None) if isinstance(b, list) else None
    check("치료해도 처형은 막지 못한다", target is not None and target["alive"] is False,
          "alive=%s" % (target["alive"] if target else "?"))

    rpc("leave_room", toks[0], {"p_room_id": room_id})


ALL.extend([test_role_doctor, test_doctor_cannot_save_execution])
