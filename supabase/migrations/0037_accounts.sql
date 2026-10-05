-- ============================================================
-- 마피아 게임 · 회원가입 / 로그인
-- ============================================================
-- 닉네임 + 비밀번호로 가입하고 로그인한다. 가입할 때 생년월일도 받는다.
--
-- Supabase 로그인은 이메일이 필요하므로, 가입할 때 화면이 임의의 내부용 이메일
-- (<무작위>@mafia-game.local)을 만들어 쓴다. 로그인할 때는 닉네임으로 그 이메일을
-- 찾아(login_email) 비밀번호와 함께 로그인한다.
--
-- 닉네임·생년월일은 가입 요청의 user_metadata 로 넘어오고, auth.users 에 행이
-- 생길 때 트리거가 profiles 에 옮겨 담는다. 익명 사용자(테스트)는 프로필이 없다.
--
-- 필요한 대시보드 설정: Authentication > Sign In / Providers > Email 에서
-- "Confirm email" 을 끈다. 내부용 이메일은 받을 수 없으므로 확인 메일을 보내면 안 된다.
-- ============================================================

create table if not exists public.profiles (
  uid        uuid primary key references auth.users (id) on delete cascade,
  nickname   text not null check (char_length(btrim(nickname)) between 1 and 12),
  birth      date not null,
  email      text not null unique,
  created_at timestamptz not null default now()
);

-- 닉네임은 대소문자만 다른 것도 같은 닉네임으로 본다
create unique index if not exists profiles_nickname_key on public.profiles (lower(nickname));

alter table public.profiles enable row level security;

drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles
  for select using (auth.uid() = uid);

-- ------------------------------------------------------------
-- 가입 시 프로필 만들기
-- ------------------------------------------------------------
create or replace function public.handle_new_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nick  text := btrim(coalesce(new.raw_user_meta_data ->> 'nickname', ''));
  v_birth date;
begin
  -- 익명 로그인, 닉네임 없이 만든 사용자는 건너뛴다
  if coalesce(new.is_anonymous, false) or v_nick = '' then
    return new;
  end if;

  if char_length(v_nick) > 12 then
    raise exception '닉네임은 12자 이내로 입력해 주세요.';
  end if;

  v_birth := (new.raw_user_meta_data ->> 'birth')::date;
  if v_birth is null or v_birth < date '1900-01-01' or v_birth > current_date then
    raise exception '생년월일이 올바르지 않습니다.';
  end if;

  insert into public.profiles (uid, nickname, birth, email)
  values (new.id, v_nick, v_birth, new.email);
  return new;
exception
  when unique_violation then
    raise exception '이미 사용 중인 닉네임입니다.';
end;
$$;

drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile
  after insert on auth.users
  for each row execute function public.handle_new_profile();

-- ------------------------------------------------------------
-- 닉네임 사용 가능 여부 (가입 전 확인)
-- ------------------------------------------------------------
create or replace function public.nickname_available(p_nickname text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not exists (
    select 1 from public.profiles
     where lower(nickname) = lower(btrim(coalesce(p_nickname, '')))
  );
$$;

-- ------------------------------------------------------------
-- 닉네임으로 로그인용 이메일 찾기. 없으면 null
-- ------------------------------------------------------------
create or replace function public.login_email(p_nickname text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select email from public.profiles
   where lower(nickname) = lower(btrim(coalesce(p_nickname, '')));
$$;

grant execute on function public.nickname_available(text) to anon, authenticated;
grant execute on function public.login_email(text) to anon, authenticated;
