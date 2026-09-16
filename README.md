# 마피아 게임

5~15명이 함께하는 온라인 마피아 게임. React + Vite + MUI + Supabase.

요구사항 전문: [`docs/요구사항.md`](docs/요구사항.md)

## 진행 상황

| 단계 | 내용 | 상태 |
|---|---|---|
| 1 | 온라인 방 · 대기실 · 준비 · 게임 시작 · 재접속 | ✅ 구현 완료 (설정 필요) |
| 2 | 직업 시스템 (마피아/시민 → … → 광대) | ⬜ 미착수 |

## 설정 순서

### 1. Supabase 프로젝트 만들기

1. [supabase.com](https://supabase.com) 에서 새 프로젝트 생성
2. **Authentication → Sign In / Providers → Anonymous sign-ins 를 켠다**
   (이 게임은 닉네임만으로 입장하므로 익명 로그인이 필수입니다)

### 2. 스키마 적용

Supabase 대시보드 → **SQL Editor** 에서
[`supabase/migrations/0001_lobby.sql`](supabase/migrations/0001_lobby.sql) 전체를 붙여넣고 실행합니다.

테이블 2개(`rooms`, `players`)와 RPC 6개가 생성되고 RLS가 켜집니다.

### 3. 환경변수

```bash
cp .env.example .env
```

Supabase 대시보드 → **Project Settings → API** 에서 값을 복사해 채웁니다.

```
VITE_SUPABASE_URL=https://xxxx.supabase.co
VITE_SUPABASE_ANON_KEY=eyJhbGci...
```

> `anon` 키만 사용합니다. `service_role` 키는 절대 넣지 마세요.
> `.env` 는 `.gitignore` 에 있어 커밋되지 않습니다.

### 4. 실행

```bash
npm install
npm run dev
```

## 배포

GitHub Actions → GitHub Pages 로 배포됩니다.
저장소 **Settings → Secrets and variables → Actions** 에 두 값을 등록해야 빌드가 통과합니다.

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`

## 구조

```
src/
  lib/
    supabase.js   Supabase 클라이언트 + 익명 로그인
    api.js        RPC 래퍼
    useRoom.js    방·참가자 실시간 구독
  pages/
    HomePage.jsx    방 만들기 / 코드로 입장
    LobbyPage.jsx   대기실 · 준비 · 시작
    SetupNotice.jsx .env 미설정 안내
  components/
    PlayerList.jsx  참가자 목록
supabase/migrations/
  0001_lobby.sql  테이블 · RLS · RPC
```

## 보안 설계

요구사항 §6.2 "클라이언트에서 숨기기만 하는 방식은 보안으로 인정하지 않는다" 를 지키기 위해:

- 모든 테이블 RLS 활성화, **SELECT 정책만 존재**. 클라이언트의 직접 INSERT/UPDATE/DELETE는 전부 거부됩니다.
- 쓰기는 `SECURITY DEFINER` RPC 함수로만 가능하며, 검증(방장 여부·인원수·준비 상태·정원)이 함수 안에서 이루어집니다.
- 브라우저 콘솔에서 `supabase.from('players').update(...)` 를 시도해도 정책이 없어 차단됩니다.
