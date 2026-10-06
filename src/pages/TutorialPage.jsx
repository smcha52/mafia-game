import { useState } from 'react';
import Alert from '@mui/material/Alert';
import AlertTitle from '@mui/material/AlertTitle';
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Chip from '@mui/material/Chip';
import Divider from '@mui/material/Divider';
import List from '@mui/material/List';
import ListItem from '@mui/material/ListItem';
import ListItemAvatar from '@mui/material/ListItemAvatar';
import ListItemText from '@mui/material/ListItemText';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import Typography from '@mui/material/Typography';
import SchoolIcon from '@mui/icons-material/School';
import SkipNextIcon from '@mui/icons-material/SkipNext';

import PlayerList from '../components/PlayerList';
import PlayerPicker from '../components/PlayerPicker';
import PrivateResults from '../components/PrivateResults';
import RoleAvatar from '../components/RoleAvatar';
import RoleCard from '../components/RoleCard';
import {
  NIGHT_ACTION, NIGHT_PROMPT, NO_SELF_TARGET, SUBMIT_LABEL, TEAMS, TEAM_RESULT, WINNERS, roleInfo,
} from '../lib/roles';

// 가입 직후 봇 4명과 하는 연습 게임. 서버 없이 이 화면 안에서만 진행된다.
// 판마다 직업이 정해져 있고, 봇은 사람이 반드시 이기도록 움직인다.

const ME = 'me';
const BOTS = ['bot1', 'bot2', 'bot3', 'bot4'];
const TOTAL_ROUNDS = 4;

// 판별 직업 구성
const SETUPS = {
  1: { me: 'CITIZEN', bot1: 'DOCTOR', bot2: 'POLICE', bot3: 'MAFIA', bot4: 'CITIZEN' },
  2: { me: 'POLICE', bot1: 'CITIZEN', bot2: 'DOCTOR', bot3: 'MAFIA', bot4: 'CITIZEN' },
  3: { me: 'DOCTOR', bot1: 'CITIZEN', bot2: 'POLICE', bot3: 'MAFIA', bot4: 'CITIZEN' },
  4: { me: 'MAFIA', bot1: 'CITIZEN', bot2: 'DOCTOR', bot3: 'POLICE', bot4: 'CITIZEN' },
};

// 판·시간대별 안내 문구
const TIPS = {
  1: {
    NIGHT: '당신은 시민입니다. 시민은 밤에 할 일이 없습니다. 마피아·경찰·의사가 움직이는 동안 아침을 기다리세요.',
    DAY: '낮에는 모두 함께 마피아로 의심되는 사람에게 투표합니다. 가장 많은 표를 받은 사람이 처형됩니다. 봇3에게 투표해 보세요.',
  },
  2: {
    NIGHT: '당신은 경찰입니다. 밤마다 한 명을 조사해 마피아인지 알아낼 수 있습니다. 봇3을 조사해 보세요.',
    DAY: '조사 결과는 당신에게만 보입니다. 마피아로 밝혀진 사람에게 투표하세요.',
  },
  3: {
    NIGHT: '당신은 의사입니다. 마피아가 노릴 것 같은 사람을 치료하면 그 사람은 죽지 않습니다. 자신을 치료해도 됩니다.',
    DAY: '누가 마피아일까요? 이번에도 봇3에게 투표해 보세요.',
  },
  4: {
    NIGHT: '이번에는 당신이 마피아입니다! 밤마다 제거할 사람을 고르세요. 살아 있는 시민 수가 마피아 수 이하가 되면 이깁니다.',
    DAY: '정체를 들키지 않게 시민인 척 다른 사람에게 투표하세요.',
  },
};

const RESULT_TIP = '투표 결과입니다. 처형된 사람이 어느 진영이었는지 공개됩니다.';

const teamOf = (role) => (role === 'MAFIA' ? 'MAFIA' : 'CITIZEN');
const pickRandom = (list) => list[Math.floor(Math.random() * list.length)];

function makePlayers(round, nickname) {
  const roles = SETUPS[round];
  return [ME, ...BOTS].map((uid, i) => ({
    uid,
    nickname: uid === ME ? nickname : `봇${i}`,
    role: roles[uid],
    alive: true,
  }));
}

// 승부가 났으면 이긴 진영, 아니면 null
function winnerOf(players) {
  const alive = players.filter((p) => p.alive);
  const mafia = alive.filter((p) => p.role === 'MAFIA').length;
  if (mafia === 0) return 'CITIZEN';
  if (mafia >= alive.length - mafia) return 'MAFIA';
  return null;
}

// 밤을 처리한다. myTarget 은 내가 고른 대상 (능력이 없으면 null)
function resolveNight(round, day, players, myTarget) {
  const me = players.find((p) => p.uid === ME);
  const aliveBots = players.filter((p) => p.alive && p.uid !== ME);

  // 마피아 공격. 봇 마피아는 사람을 빼고 다른 봇 중 아무나 공격한다
  const attack = me.role === 'MAFIA'
    ? myTarget
    : pickRandom(aliveBots.filter((p) => p.role !== 'MAFIA')).uid;

  // 의사 치료. 내가 마피아인 판에서는 봇 의사가 공격 대상을 고르지 않는다
  let heal;
  if (me.role === 'DOCTOR') {
    heal = myTarget;
  } else {
    const doctor = players.find((p) => p.role === 'DOCTOR' && p.alive);
    if (doctor) {
      const candidates = players.filter((p) => p.alive && (round !== 4 || p.uid !== attack));
      heal = pickRandom(candidates).uid;
    }
  }

  const deaths = attack && attack !== heal ? [attack] : [];
  const next = players.map((p) => (deaths.includes(p.uid) ? { ...p, alive: false } : p));

  const privateResults = [];
  if (me.role === 'POLICE' && myTarget) {
    const target = players.find((p) => p.uid === myTarget);
    privateResults.push({
      kind: 'POLICE',
      day,
      payload: { targetNickname: target.nickname, team: teamOf(target.role) },
    });
  }
  if (me.role === 'DOCTOR' && attack && attack === heal) {
    const saved = players.find((p) => p.uid === attack);
    privateResults.push({ kind: 'DOCTOR', day, payload: { savedNickname: saved.nickname } });
  }

  return { players: next, deaths, privateResults };
}

// 봇들의 투표. 1~3판은 봇3에게, 4판은 사람을 뺀 아무에게나 몰아준다
function botVotes(round, players) {
  const aliveBots = players.filter((p) => p.alive && p.uid !== ME);
  // 봇3 자신도 봇3에게 투표해 사람이 어디에 투표하든 봇3이 처형된다
  if (round < 4) {
    return aliveBots.map((b) => ({ voter: b.uid, target: 'bot3' }));
  }
  const target = pickRandom(aliveBots).uid;
  return aliveBots.map((b) => ({
    voter: b.uid,
    target: b.uid === target
      ? pickRandom(aliveBots.filter((p) => p.uid !== target)).uid
      : target,
  }));
}

// 득표를 세어 최다 득표자를 처형한다. 동점이면 아무도 처형되지 않는다
function tally(votes) {
  const counts = new Map();
  votes.forEach((v) => counts.set(v.target, (counts.get(v.target) ?? 0) + 1));
  const rows = [...counts.entries()]
    .map(([uid, count]) => ({ uid, count }))
    .sort((a, b) => b.count - a.count);
  const tie = rows.length > 1 && rows[0].count === rows[1].count;
  return { rows, executed: tie ? null : rows[0]?.uid ?? null, tie };
}

function TipBox({ round, children }) {
  return (
    <Alert severity="info" icon={<SchoolIcon />}>
      <AlertTitle sx={{ mb: 0.5 }}>튜토리얼 {round} / {TOTAL_ROUNDS}판</AlertTitle>
      {children}
    </Alert>
  );
}

export default function TutorialPage({ nickname, onDone }) {
  const [round, setRound] = useState(1);
  // LOBBY → NIGHT → DAY → RESULT → (NIGHT …) → ENDED
  const [stage, setStage] = useState('LOBBY');
  const [day, setDay] = useState(1);
  const [players, setPlayers] = useState(() => makePlayers(1, nickname));
  const [pick, setPick] = useState(null);
  const [deaths, setDeaths] = useState([]);
  const [privateResults, setPrivateResults] = useState([]);
  const [vote, setVote] = useState(null);
  const [winner, setWinner] = useState(null);

  const me = players.find((p) => p.uid === ME);
  // 어느 화면에서든 튜토리얼을 끝내고 첫 화면으로 간다
  const skipButton = (
    <Button color="inherit" startIcon={<SkipNextIcon />} onClick={onDone}>
      튜토리얼 건너뛰기
    </Button>
  );
  const nickOf = (id) => players.find((p) => p.uid === id)?.nickname ?? '알 수 없음';

  function startRound(n) {
    setRound(n);
    setPlayers(makePlayers(n, nickname));
    setDay(1);
    setDeaths([]);
    setPrivateResults([]);
    setVote(null);
    setWinner(null);
    setPick(null);
    setStage('NIGHT');
  }

  function endNight() {
    const r = resolveNight(round, day, players, pick);
    setPlayers(r.players);
    setDeaths(r.deaths);
    setPrivateResults((prev) => [...r.privateResults, ...prev]);
    setPick(null);
    const w = winnerOf(r.players);
    if (w) {
      setWinner(w);
      setStage('ENDED');
    } else {
      setStage('DAY');
    }
  }

  function endDay() {
    const votes = [...botVotes(round, players), { voter: ME, target: pick }];
    const result = tally(votes);
    const next = players.map((p) => (p.uid === result.executed ? { ...p, alive: false } : p));
    setPlayers(next);
    setVote(result);
    setPick(null);
    setStage('RESULT');
  }

  function afterResult() {
    const w = winnerOf(players);
    if (w) {
      setWinner(w);
      setStage('ENDED');
      return;
    }
    setDay((d) => d + 1);
    setStage('NIGHT');
  }

  // --- 대기실 ---
  if (stage === 'LOBBY') {
    // 봇들이 먼저 들어와 있고, 마지막에 들어온 내가 방장이다
    const lobby = [...BOTS, ME].map((uid) => {
      const p = players.find((x) => x.uid === uid);
      return { id: uid, uid, nickname: p.nickname, is_host: uid === ME, is_ready: uid !== ME };
    });

    return (
      <Stack spacing={2.5} sx={{ maxWidth: 480, mx: 'auto' }}>
        <Alert severity="info" icon={<SchoolIcon />}>
          <AlertTitle sx={{ mb: 0.5 }}>튜토리얼</AlertTitle>
          가입을 축하합니다! 봇 4명과 함께 연습 게임을 {TOTAL_ROUNDS}판 해 봅니다.
          봇들이 먼저 들어와 있고, 당신이 방장입니다.
        </Alert>

        <Stack direction="row" alignItems="center" justifyContent="space-between">
          <Typography variant="h6">참가자</Typography>
          <Chip size="small" color="success" label={`${lobby.length}명`} />
        </Stack>

        <PlayerList players={lobby} uid={ME} />

        <Paper sx={{ p: 2.5, textAlign: 'center' }}>
          <Typography variant="h6">게임을 시작 하세요</Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
            방장은 모두 준비되면 게임을 시작할 수 있습니다.
          </Typography>
        </Paper>

        <Button variant="contained" size="large" onClick={() => startRound(1)}>
          게임 시작
        </Button>

        {skipButton}
      </Stack>
    );
  }

  // --- 한 판 종료 ---
  if (stage === 'ENDED') {
    const w = WINNERS[winner];
    const last = round === TOTAL_ROUNDS;

    return (
      <Stack spacing={2} sx={{ maxWidth: 480, mx: 'auto' }}>
        <Paper sx={{ p: 3, textAlign: 'center' }}>
          <Box sx={{ fontSize: 44, lineHeight: 1 }}>{w.emoji}</Box>
          <Typography variant="h5" sx={{ mt: 1, color: w.color }}>
            {w.title}
          </Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mt: 1 }}>
            {last
              ? '튜토리얼을 모두 마쳤습니다. 이제 다른 사람들과 게임해 보세요!'
              : `튜토리얼 ${round} / ${TOTAL_ROUNDS}판 승리! 다음 판에서는 다른 직업을 맡습니다.`}
          </Typography>
        </Paper>

        <Paper sx={{ overflow: 'hidden' }}>
          <List disablePadding>
            {players.map((p) => {
              const team = TEAMS[teamOf(p.role)];
              return (
                <ListItem key={p.uid} divider>
                  <ListItemAvatar>
                    <RoleAvatar role={p.role} size={44} />
                  </ListItemAvatar>
                  <ListItemText
                    primary={
                      <Stack direction="row" spacing={0.75} alignItems="center" flexWrap="wrap">
                        <span style={{ textDecoration: p.alive ? 'none' : 'line-through' }}>
                          {p.nickname}
                        </span>
                        {p.uid === ME && <Chip size="small" label="나" />}
                        <Chip size="small" color={team.color} label={roleInfo(p.role).name} />
                      </Stack>
                    }
                    secondary={p.alive ? '생존' : '사망'}
                  />
                </ListItem>
              );
            })}
          </List>
        </Paper>

        <Button
          variant="contained"
          size="large"
          onClick={() => (last ? onDone() : startRound(round + 1))}
        >
          {last ? '튜토리얼 마치기' : `${round + 1}판 시작`}
        </Button>

        {!last && skipButton}
      </Stack>
    );
  }

  // --- 게임 진행 ---
  const isNight = stage === 'NIGHT';
  const isResult = stage === 'RESULT';
  const nightAction = NIGHT_ACTION[me.role] ?? null;
  const aliveCount = players.filter((p) => p.alive).length;

  return (
    <Stack spacing={2.5} sx={{ maxWidth: 480, mx: 'auto' }}>
      {/* 페이즈 머리말 */}
      <Paper sx={{ p: 2, bgcolor: isNight ? '#161428' : 'background.paper' }}>
        <Stack direction="row" alignItems="center" justifyContent="space-between">
          <Stack direction="row" spacing={1} alignItems="center">
            <Box sx={{ fontSize: 26, lineHeight: 1 }}>{isNight ? '🌙' : isResult ? '⚖️' : '☀️'}</Box>
            <Box>
              <Typography variant="h6">{isNight ? '밤' : isResult ? '투표 결과' : '낮'}</Typography>
              <Typography variant="caption" color="text.secondary">
                {day}일차
              </Typography>
            </Box>
          </Stack>
          <Stack direction="row" spacing={0.75} alignItems="center">
            <Chip size="small" color="primary" label={`튜토리얼 ${round}/${TOTAL_ROUNDS}`} />
            <Chip size="small" label={`생존 ${aliveCount} / ${players.length}`} />
          </Stack>
        </Stack>
      </Paper>

      <TipBox round={round}>{isResult ? RESULT_TIP : TIPS[round][stage]}</TipBox>

      <RoleCard view={{ role: me.role, team: teamOf(me.role), alive: me.alive }} />

      <PrivateResults results={privateResults} />

      {/* 지난 밤 결과 */}
      {stage === 'DAY' && (
        <Alert severity={deaths.length ? 'error' : 'success'}>
          {deaths.length
            ? `간밤에 ${deaths.map(nickOf).join(', ')}님이 사망했습니다.`
            : '간밤에 아무도 죽지 않았습니다.'}
        </Alert>
      )}

      {/* 투표 결과 — 득표 수와 처형자의 진영 */}
      {isResult && vote && (
        <Paper sx={{ p: 2 }}>
          <Stack spacing={1.5}>
            {vote.executed ? (
              <Alert severity="error" icon={false}>
                <Stack direction="row" spacing={0.75} alignItems="center" flexWrap="wrap" useFlexGap>
                  <strong>{nickOf(vote.executed)}</strong>
                  <span>님이</span>
                  <Chip size="small" label={`${vote.rows[0].count}표`} />
                  <span>로 처형되었습니다.</span>
                  {(() => {
                    const t = TEAM_RESULT[teamOf(players.find((p) => p.uid === vote.executed).role)];
                    return <Chip size="small" color={t.color} label={t.label} />;
                  })()}
                </Stack>
              </Alert>
            ) : (
              <Alert severity="info">
                {vote.tie
                  ? '투표가 동점이라 아무도 처형되지 않았습니다.'
                  : '아무도 처형되지 않았습니다.'}
              </Alert>
            )}

            <Typography variant="subtitle2" color="text.secondary">득표 수</Typography>
            <Stack spacing={0.75}>
              {vote.rows.map((v) => (
                <Stack key={v.uid} direction="row" alignItems="center" justifyContent="space-between">
                  <Typography>{nickOf(v.uid)}</Typography>
                  <Chip
                    size="small"
                    color={v.uid === vote.executed ? 'error' : 'default'}
                    label={`${v.count}표`}
                    sx={{ fontVariantNumeric: 'tabular-nums' }}
                  />
                </Stack>
              ))}
            </Stack>

            <Button variant="contained" size="large" onClick={afterResult}>
              다음
            </Button>
          </Stack>
        </Paper>
      )}

      {/* 행동 영역 */}
      {!isResult && (
        <>
          <Divider />
          {isNight && !nightAction ? (
            <Paper sx={{ p: 3, textAlign: 'center' }}>
              <Stack alignItems="center">
                <RoleAvatar role={me.role} size={52} />
              </Stack>
              <Typography sx={{ mt: 1 }}>밤이 지나가길 기다리는 중…</Typography>
              <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
                오늘 밤 당신이 할 일은 없습니다.
              </Typography>
              <Button variant="contained" size="large" sx={{ mt: 2 }} fullWidth onClick={endNight}>
                아침 맞이하기
              </Button>
            </Paper>
          ) : (
            <>
              <Typography variant="subtitle1">
                {isNight
                  ? (NIGHT_PROMPT[me.role] ?? '대상을 고르세요')
                  : '처형할 사람에게 투표하세요'}
              </Typography>

              <PlayerPicker
                players={players}
                uid={ME}
                value={pick}
                onChange={setPick}
                excludeSelf={isNight && NO_SELF_TARGET.has(me.role)}
              />

              <Button
                variant="contained"
                size="large"
                disabled={!pick}
                onClick={isNight ? endNight : endDay}
              >
                {isNight ? (SUBMIT_LABEL[me.role] ?? '확정') : '투표 확정'}
              </Button>
            </>
          )}
        </>
      )}

      {skipButton}
    </Stack>
  );
}
