import { useCallback, useEffect, useState } from 'react';
import Alert from '@mui/material/Alert';
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import ButtonBase from '@mui/material/ButtonBase';
import Dialog from '@mui/material/Dialog';
import DialogActions from '@mui/material/DialogActions';
import DialogContent from '@mui/material/DialogContent';
import DialogTitle from '@mui/material/DialogTitle';
import Paper from '@mui/material/Paper';
import Stack from '@mui/material/Stack';
import Typography from '@mui/material/Typography';
import EmojiEventsIcon from '@mui/icons-material/EmojiEvents';

import BoxArt, { BOXES } from './BoxArt';
import ProfileAvatar, { AVATARS } from './ProfileAvatar';
import { REWARD, untilText } from './QuestDialog';
import { myDailyRewards, openDailyBox } from '../lib/api';

// 등급 이름과 색
export const TIER = {
  NORMAL: { label: '일반', color: 'text.secondary' },
  LUCKY: { label: '럭키', color: '#2e7d32' },
  SUPER_LUCKY: { label: '슈퍼 럭키', color: '#d500f9' },
};

// 재화 아이콘과 개수
function Amount({ type, amount, variant = 'body2' }) {
  return (
    <Stack
      direction="row"
      alignItems="center"
      justifyContent="center"
      spacing={0.25}
      aria-label={`${REWARD[type].label} ${amount}개`}
    >
      {REWARD[type].icon}
      <Typography variant={variant} fontWeight={700}>{amount}</Typography>
    </Stack>
  );
}

// 칸 안의 보상. 상자는 그대로 보여주고, 열었으면 나온 것을 작게 덧붙인다
function CellBody({ item }) {
  if (!item) {
    return <EmojiEventsIcon fontSize="small" sx={{ mt: 0.5, color: 'text.disabled' }} aria-label="승리하면 받음" />;
  }
  if (item.type !== 'BOX') {
    return <Box sx={{ mt: 0.5 }}><Amount type={item.type} amount={item.amount} /></Box>;
  }
  return (
    <Stack alignItems="center" spacing={0.25} sx={{ mt: 0.25 }}>
      <BoxArt box={item.box} open={item.opened} size={30} />
      {item.opened ? (
        item.open.item && !item.open.dup ? (
          <ProfileAvatar avatar={item.open.item} size={20} />
        ) : (
          <Amount type={item.open.type} amount={item.open.amount} variant="caption" />
        )
      ) : (
        <Typography variant="caption" color="primary" fontWeight={700}>열기</Typography>
      )}
    </Stack>
  );
}

// 칸 하나 — 위에 등급, 아래에 보상. 열지 않은 상자는 누르면 열린다
function RewardCell({ item, onOpen }) {
  const tier = item && TIER[item.tier];
  const special = item && item.tier !== 'NORMAL';
  const closedBox = item?.type === 'BOX' && !item.opened;
  const body = (
    <>
      <Typography
        variant="caption"
        fontWeight={700}
        sx={{ color: tier ? tier.color : 'text.disabled', display: 'block', whiteSpace: 'nowrap' }}
      >
        {tier ? tier.label : '?'}
      </Typography>
      <CellBody item={item} />
    </>
  );
  return (
    <Paper
      variant="outlined"
      sx={{
        minHeight: 64,
        textAlign: 'center',
        overflow: 'hidden',
        borderColor: special ? tier.color : closedBox ? 'primary.main' : undefined,
        borderWidth: special || closedBox ? 2 : 1,
      }}
    >
      {closedBox ? (
        <ButtonBase
          onClick={() => onOpen(item)}
          sx={{ display: 'block', width: '100%', height: '100%', p: 0.75 }}
          aria-label={`${BOXES[item.box].name} 열기`}
        >
          {body}
        </ButtonBase>
      ) : (
        <Box sx={{ p: 0.75 }}>{body}</Box>
      )}
    </Paper>
  );
}

// 상자를 열고 나온 것을 보여주는 창
function OpenDialog({ opening, onClose }) {
  const { box, result, error } = opening ?? {};
  const name = box && BOXES[box].name;
  return (
    <Dialog open={!!opening} onClose={result || error ? onClose : undefined} maxWidth="xs" fullWidth>
      <DialogTitle sx={{ textAlign: 'center' }}>{name}</DialogTitle>
      <DialogContent>
        <Stack alignItems="center" spacing={1.5} sx={{ py: 1 }}>
          <BoxArt box={box} open={!!result} size={88} />
          {error && <Alert severity="error">{error}</Alert>}
          {!result && !error && <Typography color="text.secondary">여는 중…</Typography>}
          {result && (result.item && !result.dup ? (
            <Stack alignItems="center" spacing={1}>
              <ProfileAvatar avatar={result.item} size={56} />
              <Typography fontWeight={700}>{AVATARS[result.item].name} 프로필을 얻었습니다!</Typography>
              <Typography variant="caption" color="text.secondary">장착 화면에서 바꿀 수 있습니다.</Typography>
            </Stack>
          ) : (
            <Stack alignItems="center" spacing={0.5}>
              {result.dup && (
                <Typography variant="body2" color="text.secondary" textAlign="center">
                  {AVATARS[result.item].name} 프로필은 이미 있어서 바꿔 드렸습니다.
                </Typography>
              )}
              <Amount type={result.type} amount={result.amount} variant="h5" />
            </Stack>
          ))}
        </Stack>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose} disabled={!result && !error}>확인</Button>
      </DialogActions>
    </Dialog>
  );
}

// 홈 화면 방 찾기 아래. 이길 때마다 보상 하나, 하루에 5개까지 (0057·0058)
// 게임이 끝나 홈으로 돌아오면 다시 그려지므로 그때 새로 읽는다
// 상자를 열어 재화가 바뀌면 onRewarded 로 다시 읽게 한다
export default function DailyRewards({ onRewarded }) {
  const [data, setData] = useState(null);
  // 여는 중인 상자 { box, result, error }
  const [opening, setOpening] = useState(null);

  const load = useCallback(() => {
    myDailyRewards().then(setData).catch(() => setData(null));
  }, []);

  useEffect(load, [load]);

  async function open(item) {
    setOpening({ box: item.box });
    try {
      const result = await openDailyBox(item.day, item.idx);
      setOpening({ box: item.box, result });
      onRewarded?.();
    } catch (e) {
      setOpening({ box: item.box, error: e.message });
    }
    load();
  }

  if (!data) return null;

  const done = data.items.length >= data.limit;
  return (
    <Box>
      <Stack direction="row" alignItems="baseline" justifyContent="space-between" sx={{ mb: 0.75 }}>
        <Typography variant="subtitle2" fontWeight={700}>
          일일보상 {data.items.length}/{data.limit}
        </Typography>
        <Typography variant="caption" color="text.secondary">
          {done ? `${untilText(data.next)} 뒤 다시 받을 수 있어요` : '승리하면 하나씩 받아요'}
        </Typography>
      </Stack>
      <Box sx={{ display: 'grid', gridTemplateColumns: `repeat(${data.limit}, 1fr)`, gap: 0.75 }}>
        {Array.from({ length: data.limit }, (_, i) => (
          <RewardCell key={i} item={data.items[i]} onOpen={open} />
        ))}
      </Box>

      {data.boxes.length > 0 && (
        <Box sx={{ mt: 1 }}>
          <Typography variant="caption" color="text.secondary">지난날 열지 않은 상자</Typography>
          <Box sx={{ display: 'grid', gridTemplateColumns: `repeat(${data.limit}, 1fr)`, gap: 0.75, mt: 0.5 }}>
            {data.boxes.map((b) => (
              <RewardCell key={`${b.day}-${b.idx}`} item={b} onOpen={open} />
            ))}
          </Box>
        </Box>
      )}

      <OpenDialog opening={opening} onClose={() => setOpening(null)} />
    </Box>
  );
}
