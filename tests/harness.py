"""
테스트 공용 헬퍼 — 접속, 요청, 결과 수집.

접속 정보는 프로젝트 루트의 .env 에서 읽는다.
환경변수 VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY 로 덮어쓸 수 있다.

익명 로그인에는 시간당 한도가 있다. 테스트마다 새로 로그인하면 금방 걸리므로
사용자 풀을 만들어 재사용하고, 토큰은 .token-cache.json 에 저장해
다시 실행할 때도 그대로 쓴다.
"""

import io
import json
import os
import sys
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".token-cache.json")


def load_env():
    values = {}
    path = os.path.join(ROOT, ".env")
    if os.path.exists(path):
        with io.open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                values[k.strip()] = v.strip().strip('"').strip("'")

    url = os.environ.get("VITE_SUPABASE_URL") or values.get("VITE_SUPABASE_URL", "")
    key = os.environ.get("VITE_SUPABASE_ANON_KEY") or values.get("VITE_SUPABASE_ANON_KEY", "")

    if not url or not key:
        sys.exit(
            "접속 정보를 찾을 수 없습니다.\n"
            "  .env 에 VITE_SUPABASE_URL 과 VITE_SUPABASE_ANON_KEY 를 채워 주세요.\n"
            "  (.env.example 참고)"
        )
    return url.rstrip("/"), key


URL, KEY = load_env()


def req(path, token=None, body=None, method=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(
        URL + path, data=data, method=method or ("POST" if data is not None else "GET")
    )
    r.add_header("apikey", KEY)
    r.add_header("Authorization", "Bearer " + (token or KEY))
    r.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(r) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw.strip() else None)
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except ValueError:
            return e.code, raw


# ------------------------------------------------------------------
# 사용자 풀
# ------------------------------------------------------------------

_pool = []
_loaded = False


def _read_cache():
    if not os.path.exists(CACHE):
        return []
    try:
        with io.open(CACHE, encoding="utf-8") as f:
            return json.load(f).get("tokens", [])
    except (ValueError, OSError):
        return []


def _write_cache():
    try:
        with io.open(CACHE, "w", encoding="utf-8") as f:
            json.dump({"tokens": _pool}, f)
    except OSError:
        pass


def _valid(token):
    s, _ = req("/auth/v1/user", token)
    return s == 200


def _new_user():
    s, b = req("/auth/v1/signup", body={})
    if s == 429:
        sys.exit(
            "익명 로그인 한도를 초과했습니다 (429).\n"
            "  잠시 뒤 다시 실행해 주세요. 토큰은 tests/.token-cache.json 에 저장되어\n"
            "  다음 실행에서는 재사용되므로 한도를 다시 쓰지 않습니다."
        )
    if s != 200:
        sys.exit(
            "익명 로그인 실패 (%s): %s\n"
            "  Authentication > Sign In / Providers 에서 Anonymous sign-ins 를 켜 주세요." % (s, b)
        )
    return b["access_token"]


def user_pool(n):
    """n명의 토큰을 돌려준다. 캐시에 있으면 재사용한다."""
    global _pool, _loaded
    if not _loaded:
        _pool = [t for t in _read_cache() if _valid(t)]
        _loaded = True

    grew = False
    while len(_pool) < n:
        _pool.append(_new_user())
        grew = True
    if grew:
        _write_cache()
    return _pool[:n]


def uid_of(token):
    s, b = req("/auth/v1/user", token)
    return b["id"] if s == 200 else None


def rpc(fn, token, args):
    return req("/rest/v1/rpc/" + fn, token, args)


def msg(b):
    return b.get("message") if isinstance(b, dict) else b


# ------------------------------------------------------------------
# 결과 수집
# ------------------------------------------------------------------

RESULTS = []


def check(name, cond, detail=""):
    RESULTS.append((name, bool(cond), detail))


def report():
    width = max(len(n) for n, _, _ in RESULTS)
    passed = sum(1 for _, c, _ in RESULTS if c)
    for name, cond, detail in RESULTS:
        print("  [%s] %-*s  %s" % ("PASS" if cond else "FAIL", width, name, str(detail)[:62]))
    print("\n  %d/%d 통과\n" % (passed, len(RESULTS)))
    return 0 if passed == len(RESULTS) else 1
