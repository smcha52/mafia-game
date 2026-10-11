-- ============================================================
-- 마피아 게임 · 나이 범위 설정의 최대값
-- ============================================================
-- 나이 범위 설정(RANGE)은 가입할 때 넣을 수 있는 가장 많은 나이까지 고를 수 있다.
-- 가입 화면의 생년월일은 1900-01-01 부터이므로 최대 = 올해 - 1900 (src/lib/roomRules.js).
-- 나이 조절(PLUS / MINUS)은 그대로 0~25 다.
-- ============================================================

-- create_room: 나이 RANGE 의 최대값만 바꿨다 (0044 와 나머지는 같다)
create or replace function public.create_room(
  p_nickname   text,
  p_public     boolean default true,
  p_age_mode   text    default 'NONE',
  p_age_a      int     default null,
  p_age_b      int     default null,
  p_level_mode text    default 'NONE',
  p_level_a    int     default null,
  p_level_b    int     default null)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_code  text;
  v_id    uuid;
  v_age   text := upper(coalesce(p_age_mode, 'NONE'));
  v_level text := upper(coalesce(p_level_mode, 'NONE'));
begin
  if v_uid is null then
    raise exception '로그인이 필요합니다.';
  end if;
  if char_length(btrim(coalesce(p_nickname, ''))) = 0 then
    raise exception '닉네임을 입력해 주세요.';
  end if;
  if p_public is null then
    raise exception '공개 / 비공개를 골라 주세요.';
  end if;
  if v_age not in ('NONE', 'ALL', 'PLUS', 'MINUS', 'RANGE') then
    raise exception '나이 설정이 올바르지 않습니다.';
  end if;
  if v_level not in ('NONE', 'PLUS', 'MINUS', 'RANGE') then
    raise exception '레벨 설정이 올바르지 않습니다.';
  end if;

  perform public.check_rule('나이', v_age, p_age_a, p_age_b, 0,
    case when v_age = 'RANGE'
         then date_part('year', current_date)::int - 1900
         else 25 end);
  perform public.check_rule('레벨', v_level, p_level_a, p_level_b, 5, 50);

  v_code := public.gen_room_code();

  insert into public.rooms (code, host_uid, is_public,
                            age_mode, age_a, age_b, level_mode, level_a, level_b)
  values (v_code, v_uid, p_public,
          v_age,
          case when v_age in ('PLUS', 'MINUS', 'RANGE') then p_age_a end,
          case when v_age = 'RANGE' then p_age_b end,
          v_level,
          case when v_level in ('PLUS', 'MINUS', 'RANGE') then p_level_a end,
          case when v_level = 'RANGE' then p_level_b end)
  returning id into v_id;

  insert into public.players (room_id, uid, nickname, is_host, is_ready)
  values (v_id, v_uid, btrim(p_nickname), true, true);

  return json_build_object('room_id', v_id, 'room_code', v_code);
end;
$$;

grant execute on function public.create_room(text, boolean, text, int, int, text, int, int)
  to anon, authenticated;
