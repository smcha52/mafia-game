"""
1단계 테스트 — 온라인 방 / 대기실 / 준비 / 시작 / 재접속
"""

from harness import check, close_room, msg, req, rpc, uid_of, user_pool


def test_lobby():
    # 풀에서 7명을 받아 5명은 참가자, 나머지는 외부인 역할로 쓴다
    pool = user_pool(7)
    toks, t_extra, t_out = pool[:5], pool[5], pool[6]
    check("사용자 5명 확보", len(toks) == 5 and all(toks), "토큰 재사용")

    s, b = rpc("create_room", toks[0], {"p_nickname": "방장"})
    good = s == 200 and isinstance(b, dict) and len(b.get("room_code", "")) == 6
    check("방 만들기", good, ("코드 %s" % b["room_code"]) if good else msg(b))
    if not good:
        return
    room_id, code = b["room_id"], b["room_code"]

    s, b = rpc("start_game", toks[0], {"p_room_id": room_id})
    check("5명 미만 시작 차단", s >= 400 and "최소 5명" in str(msg(b)), msg(b))

    joined, errs = 0, []
    for i, t in enumerate(toks[1:], start=2):
        s, b = rpc("join_room", t, {"p_code": code, "p_nickname": "참가자%d" % i})
        if s == 200:
            joined += 1
        else:
            errs.append(msg(b))
    check("참가자 4명 입장", joined == 4, "%d/4 입장  %s" % (joined, errs[:1]))

    # 새로고침·재접속 시 같은 사람은 그대로 들어가야 한다
    s, b = rpc("join_room", toks[3], {"p_code": code, "p_nickname": "다른이름"})
    check("같은 사람 재입장 허용",
          s == 200 and isinstance(b, dict) and b.get("room_code") == code, "HTTP %d" % s)

    s, b = rpc("join_room", t_extra, {"p_code": code, "p_nickname": "참가자2"})
    check("닉네임 중복 차단", s >= 400 and "이미 사용" in str(msg(b)), msg(b))

    s, b = rpc("join_room", t_extra, {"p_code": "ZZZZZZ", "p_nickname": "없는방"})
    check("없는 코드 차단", s >= 400 and "존재하지 않는" in str(msg(b)), msg(b))

    s, b = req("/rest/v1/players?select=nickname,is_ready,is_host&room_id=eq." + room_id, toks[0])
    n = len(b) if isinstance(b, list) else -1
    check("참가자 목록 조회", s == 200 and n == 5, "%d명 조회됨" % n)

    # --- 보안 (§6.2) ---
    s, b = req("/rest/v1/players?select=nickname&room_id=eq." + room_id, t_out)
    check("외부인 목록 차단(RLS)", s == 200 and b == [], "조회 결과 %s" % b)

    s, b = req("/rest/v1/players?room_id=eq." + room_id, toks[1],
               body={"is_ready": True}, method="PATCH")
    check("직접 UPDATE 차단", s >= 400, "HTTP %d %s" % (s, str(msg(b))[:48]))

    s, b = req("/rest/v1/rooms", toks[1],
               body={"code": "HACKED", "host_uid": "00000000-0000-0000-0000-000000000000"})
    check("직접 INSERT 차단", s >= 400, "HTTP %d %s" % (s, str(msg(b))[:48]))

    # --- 시작 조건 ---
    s, b = rpc("start_game", toks[0], {"p_room_id": room_id})
    check("미준비 상태 시작 차단", s >= 400 and "준비하지 않은" in str(msg(b)), msg(b))

    s, b = rpc("set_ready", toks[0], {"p_room_id": room_id, "p_ready": False})
    check("방장 준비토글 차단", s >= 400 and "방장은" in str(msg(b)), msg(b))

    for t in toks[1:]:
        rpc("set_ready", t, {"p_room_id": room_id, "p_ready": True})
    s, b = req("/rest/v1/players?select=is_ready&room_id=eq." + room_id, toks[0])
    ready = sum(1 for p in b if p["is_ready"]) if isinstance(b, list) else -1
    check("전원 준비 완료", ready == 5, "%d/5 준비" % ready)

    s, b = rpc("start_game", toks[1], {"p_room_id": room_id})
    check("비방장 시작 차단", s >= 400 and "방장만" in str(msg(b)), msg(b))

    s, b = rpc("my_active_room", toks[2], {})
    check("재접속 방 복원",
          s == 200 and isinstance(b, dict) and b.get("room_code") == code,
          "코드 %s" % (b.get("room_code") if isinstance(b, dict) else None))

    # void 를 반환하는 RPC 는 PostgREST 가 204 No Content 로 응답한다
    s, b = rpc("start_game", toks[0], {"p_room_id": room_id})
    check("게임 시작", s in (200, 204), "HTTP %d %s" % (s, str(msg(b))[:38] if s >= 400 else ""))

    s, b = req("/rest/v1/rooms?select=phase,day_number&id=eq." + room_id, toks[0])
    okp = isinstance(b, list) and b and b[0]["phase"] == "NIGHT" and b[0]["day_number"] == 1
    check("phase 전환", okp, ("%s %s일차" % (b[0]["phase"], b[0]["day_number"])) if b else "?")

    s, b = rpc("join_room", t_extra, {"p_code": code, "p_nickname": "지각생"})
    check("시작 후 입장 차단", s >= 400 and "이미 시작" in str(msg(b)), msg(b))

    s, b = rpc("set_ready", toks[1], {"p_room_id": room_id, "p_ready": False})
    check("시작 후 준비변경 차단", s >= 400 and "대기실에서만" in str(msg(b)), msg(b))

    s, b = rpc("start_game", toks[0], {"p_room_id": room_id})
    check("중복 시작 차단", s >= 400 and "이미 시작" in str(msg(b)), msg(b))

    # 방장이 나가면 그다음으로 들어온 사람이 방장이 된다 (0026)
    rpc("leave_room", toks[0], {"p_room_id": room_id})
    next_uid = uid_of(toks[1])
    s, b = req("/rest/v1/rooms?select=host_uid&id=eq." + room_id, toks[1])
    check("방장 퇴장 시 방 유지", isinstance(b, list) and len(b) == 1, "남은 방 %s" % b)
    check("다음 입장자에게 방장 이전",
          bool(b) and b[0]["host_uid"] == next_uid, str(b)[:60])
    s, b = req("/rest/v1/players?select=nickname,is_host&room_id=eq." + room_id
               + "&is_host=eq.true", toks[1])
    check("방장 표시도 한 명만 이전",
          isinstance(b, list) and [p["nickname"] for p in b] == ["참가자2"], str(b))

    # 정리 — 전원이 나가면 방이 삭제된다
    # 나간 사람은 RLS 때문에 방이 남아 있어도 [] 를 받는다. 코드로 입장해 확인한다.
    close_room(toks, room_id)
    s, b = rpc("join_room", t_out, {"p_code": code, "p_nickname": "확인"})
    check("전원 퇴장 시 방 삭제", s >= 400 and "존재하지 않는" in str(msg(b)), msg(b))
    if s == 200:
        close_room([t_out], room_id)


# ------------------------------------------------------------------
# 대기실 추방 (0027)
# ------------------------------------------------------------------

def test_kick():
    toks = user_pool(5)
    uids = [uid_of(t) for t in toks]

    s, b = rpc("create_room", toks[0], {"p_nickname": "방장"})
    if s != 200:
        check("추방 테스트 준비", False, "방 생성 실패")
        return
    room_id, code = b["room_id"], b["room_code"]
    for i, t in enumerate(toks[1:], start=1):
        rpc("join_room", t, {"p_code": code, "p_nickname": "추방%d" % i})
        rpc("set_ready", t, {"p_room_id": room_id, "p_ready": True})

    # --- 권한 ---
    s, b = rpc("kick_player", toks[1], {"p_room_id": room_id, "p_target_uid": uids[2]})
    check("비방장 추방 차단", s >= 400 and "방장만" in str(msg(b)), msg(b))

    s, b = rpc("kick_player", toks[0], {"p_room_id": room_id, "p_target_uid": uids[0]})
    check("자기 자신 추방 차단", s >= 400 and "자신" in str(msg(b)), msg(b))

    # --- 추방 ---
    s, b = rpc("kick_player", toks[0], {"p_room_id": room_id, "p_target_uid": uids[1]})
    check("방장 추방", s in (200, 204), "HTTP %d %s" % (s, str(msg(b))[:38] if s >= 400 else ""))

    s, b = req("/rest/v1/players?select=uid&room_id=eq." + room_id, toks[0])
    left = [p["uid"] for p in b] if isinstance(b, list) else []
    check("추방된 사람은 목록에서 빠진다", uids[1] not in left and len(left) == 4,
          "%d명" % len(left))

    s, b = req("/rest/v1/rooms?select=id&id=eq." + room_id, toks[1])
    check("추방된 사람은 방을 못 읽는다", b == [], str(b))

    s, b = rpc("heartbeat", toks[1], {"p_room_id": room_id})
    check("추방된 사람의 heartbeat 거부", s >= 400 and "참가자가 아닙니다" in str(msg(b)), msg(b))

    # --- 추방 안내: 추방당한 사람에게만, 한 번만 ---
    s, b = rpc("take_kick_notice", toks[2], {"p_room_id": room_id})
    check("다른 사람에겐 추방 안내 없음", b is False, str(b))

    s, b = rpc("take_kick_notice", toks[1], {"p_room_id": room_id})
    check("추방된 사람에게 안내", b is True, str(b))

    s, b = rpc("take_kick_notice", toks[1], {"p_room_id": room_id})
    check("추방 안내는 한 번만", b is False, str(b))

    s, b = rpc("kick_player", toks[0], {"p_room_id": room_id, "p_target_uid": uids[1]})
    check("방에 없는 사람 추방 차단", s >= 400 and "참가자가 아닙니다" in str(msg(b)), msg(b))

    # --- 다시 들어오는 것은 막지 않는다 ---
    s, b = rpc("join_room", toks[1], {"p_code": code, "p_nickname": "추방1"})
    check("추방 후 재입장 허용", s == 200, msg(b) if s >= 400 else "HTTP 200")
    rpc("set_ready", toks[1], {"p_room_id": room_id, "p_ready": True})

    # --- 게임 중에는 추방할 수 없다 ---
    s, b = rpc("start_game", toks[0], {"p_room_id": room_id})
    check("추방 테스트: 게임 시작", s in (200, 204), msg(b) if s >= 400 else "HTTP %d" % s)

    s, b = rpc("kick_player", toks[0], {"p_room_id": room_id, "p_target_uid": uids[2]})
    check("게임 중 추방 차단", s >= 400 and "대기실에서만" in str(msg(b)), msg(b))

    close_room(toks, room_id)


ALL = [test_lobby, test_kick]
