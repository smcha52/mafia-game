import { useEffect, useState } from 'react';
import Alert from '@mui/material/Alert';
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Chip from '@mui/material/Chip';
import CircularProgress from '@mui/material/CircularProgress';
import Divider from '@mui/material/Divider';
import LinearProgress from '@mui/material/LinearProgress';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import Typography from '@mui/material/Typography';
import LogoutIcon from '@mui/icons-material/Logout';

import GameOver from '../components/GameOver';
import PlayerPicker from '../components/PlayerPicker';
import ChatPanel from '../components/ChatPanel';
import PrivateResults from '../components/PrivateResults';
import RoleAvatar from '../components/RoleAvatar';
import RoleCard from '../components/RoleCard';
import {
  ABILITY_READY, NIGHT_ACTION, NIGHT_PROMPT, NO_SELF_TARGET, ONE_SHOT,
  REPEAT_BLOCKED, SUBMITTED_NOTE, SUBMIT_LABEL, TARGETS_DEAD, TEAM_RESULT,
  roleInfo,
} from '../lib/roles';
import {
  leaveRoom, skipNightAction, submitDayVote, submitNightAction, tickPhase,
} from '../lib/api';
import { useChat } from '../lib/useChat';
import { useGame } from '../lib/useGame';

export default function GamePage({ roomId, uid, onLeave }) {
  const { room, players, results, view, loading, error, reload } = useGame(roomId);
  const { messages } = useChat(roomId);
  const [pick, setPick] = useState(null);
  const [busy, setBusy] = useState('');
  const [actionError, setActionError] = useState('');

  const phase = room?.phase;
  const day = room?.day_number;

  // 1초마다 남은 시간을 다시 계산한다
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, []);

  const deadline = room?.phase_deadline ? new Date(room.phase_deadline).getTime() : null;
  const remaining = deadline === null ? null : Math.max(0, Math.round((deadline - now) / 1000));

  // 마감이 지난 것으로 보이면 서버에 처리를 요청한다.
  //
  // 마감 판정의 기준은 서버 시계다. 브라우저 시계가 조금이라도 앞서 있으면
  // 클라이언트는 0초라고 보는데 서버는 아직 남았다고 답한다. 그때 한 번 부르고
  // 끝내면 그 페이즈에서 다시는 시도하지 않아 게임이 영구히 멈춘다.
  // 그래서 서버가 resolved 를 돌려줄 때까지, 서버가 알려준 남은 시간만큼
  // 기다렸다가 다시 시도한다.
  const expired = remaining !== null && remaining <= 0;
  useEffect(() => {
    if (phase !== 'NIGHT' && phase !== 'DAY') return undefined;
    if (!expired) return undefined;

    let stopped = false;
    let timer = null;

    const attempt = () => {
      tickPhase(roomId)
        .then((r) => {
          if (stopped) return;
          if (r?.resolved) {
            reload();
            return;                       // 페이즈가 바뀌면 이 effect 는 새로 돈다
          }
          const wait = Math.max(1, Number(r?.remaining) || 1);
          timer = setTimeout(attempt, wait * 1000);
        })
        .catch(() => {
          if (!stopped) timer = setTimeout(attempt, 3000);
        });
    };
    attempt();

    return () => {
      stopped = true;
      if (timer) clearTimeout(timer);
    };
  }, [phase, day, expired, roomId, reload]);

  // 페이즈가 바뀌면 선택을 비운다
  useEffect(() => {
    setPick(null);
    setActionError('');
  }, [phase, day]);

  async function run(kind, fn) {
    setBusy(kind);
    setActionError('');
    try {
      await fn();
      await reload();
    } catch (e) {
      setActionError(e.message);
    } finally {
      setBusy('');
    }
  }

  if (loading) {
    return (
      <Stack sx={{ minHeight: '60dvh' }} alignItems="center" justifyContent="center">
        <CircularProgress />
      </Stack>
    );
  }

  if (error || !room) {
    return (
      <Stack spacing={2} sx={{ maxWidth: 480, mx: 'auto' }}>
        <Alert severity="error">{error || '방을 찾을 수 없습니다.'}</Alert>
        <Button variant="outlined" onClick={onLeave}>첫 화면으로</Button>
      </Stack>
    );
  }

  const nickOf = (id) => players.find((p) => p.uid === id)?.nickname ?? '알 수 없음';
  const lastNight = results.find((r) => r.kind === 'NIGHT' && r.day_number === day);
  const deaths = (phase === 'DAY' ? lastNight?.payload?.nightDeaths : null) ?? [];
  const reveals = (phase === 'DAY' ? lastNight?.payload?.reporterReveal : null) ?? [];

  const leaveButton = (
    <Button
      color="inherit"
      startIcon={<LogoutIcon />}
      disabled={busy !== ''}
      loading={busy === 'leave'}
      onClick={() => run('leave', async () => {
        await leaveRoom(roomId);
        onLeave();
      })}
    >
      나가기
    </Button>
  );

  if (phase === 'ENDED') {
    return (
      <Stack spacing={2.5} sx={{ maxWidth: 480, mx: 'auto' }}>
        <GameOver roomId={roomId} winner={room.winner} />
      <ChatPanel
        roomId={roomId}
        phase={phase}
        uid={uid}
        alive={view?.alive ?? false}
        team={view?.team ?? null}
        messages={messages}
      />

        {leaveButton}
      </Stack>
    );
  }

  const isNight = phase === 'NIGHT';
  const alive = view?.alive ?? false;
  const role = view?.role;
  const nightAction = NIGHT_ACTION[role] ?? null;
  const spentOneShot = ONE_SHOT.has(role) && view?.abilityUsed;
  const needsDead = TARGETS_DEAD.has(role);
  const deadCount = players.filter((p) => !p.alive).length;
  const noTargets = needsDead && deadCount === 0;
  const canAct = isNight
    ? Boolean(nightAction) && !spentOneShot && !noTargets
    : true;
  // 기자는 대상 없이 넘길 수 있다. 그때 nightSubmitted 는 null 이라 별도 표시가 필요하다
  const skipped = isNight && view?.nightActed && !view?.nightSubmitted;
  const submitted = isNight ? view?.nightSubmitted : view?.daySubmitted;
  const progress = isNight ? view?.nightProgress : view?.dayProgress;

  return (
    <Stack spacing={2.5} sx={{ maxWidth: 480, mx: 'auto' }}>
      {/* 페이즈 머리말 */}
      <Paper sx={{ p: 2, bgcolor: isNight ? '#161428' : 'background.paper' }}>
        <Stack direction="row" alignItems="center" justifyContent="space-between">
          <Stack direction="row" spacing={1} alignItems="center">
            <Box sx={{ fontSize: 26, lineHeight: 1 }}>{isNight ? '🌙' : '☀️'}</Box>
            <Box>
              <Typography variant="h6">{isNight ? '밤' : '낮'}</Typography>
              <Typography variant="caption" color="text.secondary">
                {day}일차
              </Typography>
            </Box>
          </Stack>
          <Stack direction="row" spacing={0.75} alignItems="center">
            {remaining !== null && (
              <Chip
                size="small"
                color={remaining <= 10 ? 'error' : 'default'}
                label={`${String(Math.floor(remaining / 60)).padStart(2, '0')}:${String(remaining % 60).padStart(2, '0')}`}
                sx={{ fontVariantNumeric: 'tabular-nums' }}
              />
            )}
            <Chip
              size="small"
              label={`생존 ${players.filter((p) => p.alive).length} / ${players.length}`}
            />
          </Stack>
        </Stack>
      </Paper>

      <RoleCard view={view} />

      <PrivateResults results={view?.privateResults} />

      {/* 지난 밤 결과 */}
      {phase === 'DAY' && (
        <Alert severity={deaths.length ? 'error' : 'success'}>
          {deaths.length
            ? `간밤에 ${deaths.map(nickOf).join(', ')}님이 사망했습니다.`
            : '간밤에 아무도 죽지 않았습니다.'}
        </Alert>
      )}

      {/* 기자 보도 — 모든 생존자가 본다 (§2.7) */}
      {phase === 'DAY' && reveals.map((r) => {
        const t = TEAM_RESULT[r.team] ?? null;
        return (
          <Alert key={r.targetUid} severity="warning" icon={false}>
            <Stack direction="row" spacing={0.75} alignItems="center" flexWrap="wrap" useFlexGap>
              <span>📰 오늘의 보도 —</span>
              <strong>{r.targetNickname}</strong>
              <span>님은</span>
              {t && <Chip size="small" color={t.color} label={t.label} />}
              <span>입니다.</span>
            </Stack>
          </Alert>
        );
      })}

      {!alive && (
        <Alert severity="info">
          사망하여 관전 중입니다. 능력과 투표를 사용할 수 없습니다.
        </Alert>
      )}

      {/* 행동 영역 */}
      {alive && (
        <>
          <Divider />
          {canAct ? (
            <>
              <Stack direction="row" alignItems="center" justifyContent="space-between">
                <Typography variant="subtitle1">
                  {isNight
                    ? (NIGHT_PROMPT[role] ?? '대상을 고르세요')
                    : '처형할 사람에게 투표하세요'}
                </Typography>
                {progress && (
                  <Chip
                    size="small"
                    color={submitted ? 'success' : 'default'}
                    label={`${progress.submitted} / ${progress.expected}`}
                  />
                )}
              </Stack>

              {skipped && (
                <Alert severity="info">
                  오늘 밤은 능력을 사용하지 않기로 했습니다. 아직 한 번 남아 있습니다.
                </Alert>
              )}

              {submitted && (
                <Alert severity="success">
                  <strong>{nickOf(submitted)}</strong>님을 선택했습니다.
                  {!isNight
                    ? ' 투표는 변경할 수 없습니다.'
                    : (SUBMITTED_NOTE[role] ?? ' 밤이 끝나기를 기다리는 중입니다.')}
                </Alert>
              )}

              <PlayerPicker
                players={players}
                uid={uid}
                value={submitted ?? pick}
                onChange={setPick}
                locked={Boolean(submitted)}
                dead={isNight && needsDead}
                excludeSelf={isNight && NO_SELF_TARGET.has(role)}
                blockedUid={isNight && REPEAT_BLOCKED[role] ? view?.lastTargetId : null}
                blockedNote={REPEAT_BLOCKED[role] ?? ''}
              />

              {actionError && <Alert severity="error">{actionError}</Alert>}

              {!submitted && (
                <Stack spacing={1}>
                  <Button
                    variant="contained"
                    size="large"
                    disabled={!pick || busy !== ''}
                    loading={busy === 'submit'}
                    onClick={() => run('submit', () =>
                      isNight
                        ? submitNightAction(roomId, nightAction, pick)
                        : submitDayVote(roomId, pick))}
                  >
                    {!isNight ? '투표 확정' : (SUBMIT_LABEL[role] ?? '확정')}
                  </Button>

                  {isNight && ONE_SHOT.has(role) && !skipped && (
                    <Button
                      color="inherit"
                      disabled={busy !== ''}
                      loading={busy === 'skip'}
                      onClick={() => run('skip', () => skipNightAction(roomId, nightAction))}
                    >
                      오늘은 사용하지 않기
                    </Button>
                  )}
                </Stack>
              )}
            </>
          ) : (
            <Paper sx={{ p: 3, textAlign: 'center' }}>
              <Stack alignItems="center">
                <RoleAvatar role={role} size={52} />
              </Stack>
              <Typography sx={{ mt: 1 }}>밤이 지나가길 기다리는 중…</Typography>
              <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
                {noTargets
                  ? '아직 사망자가 없어 능력을 쓸 수 없습니다.'
                  : spentOneShot
                    ? '능력을 이미 사용했습니다.'
                    : ABILITY_READY.has(role)
                      ? '오늘 밤 당신이 할 일은 없습니다.'
                      : `${roleInfo(role).name}의 능력은 아직 준비 중입니다.`}
              </Typography>
              <LinearProgress
                sx={{ mt: 2 }}
                variant={remaining === null ? 'indeterminate' : 'determinate'}
                value={remaining === null ? 0 : Math.min(100, (remaining / 90) * 100)}
              />
            </Paper>
          )}
        </>
      )}

      <ChatPanel
        roomId={roomId}
        phase={phase}
        uid={uid}
        alive={view?.alive ?? false}
        team={view?.team ?? null}
        messages={messages}
      />

      {leaveButton}
    </Stack>
  );
}
