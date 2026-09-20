#!/usr/bin/env python3
"""
마피아 게임 · 종단간 테스트 실행기

실제 Supabase 인스턴스를 대상으로 서버 규칙을 검증한다.
요구사항 §8.3 체크리스트 중 서버에서 확인 가능한 항목을 다룬다.

실행:
    npm run test:e2e
    python tests/e2e.py

단계별 테스트는 stage1.py, stage2.py 에 있다.
직업을 하나 추가할 때마다 stage2.py 에 테스트를 덧붙인다.

주의: 실행할 때마다 익명 사용자가 생성된다. 방과 참가자는 각 테스트 끝에서
      정리하지만 auth.users 행은 남는다 (삭제에 service_role 키가 필요하다).
"""

import io
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

import harness  # noqa: E402
import stage1  # noqa: E402
import stage2  # noqa: E402
import stage3  # noqa: E402

SUITES = [
    ("1단계 · 대기실", stage1.ALL),
    ("2단계 · 직업별 능력", stage2.ALL),
    ("2단계-10 · 전체 조합과 승리 조건", stage3.ALL),
]


def main():
    print("\n  대상: %s\n" % harness.URL)
    for title, tests in SUITES:
        print("  [%s]" % title)
        for fn in tests:
            fn()
    print()
    return harness.report()


if __name__ == "__main__":
    sys.exit(main())
