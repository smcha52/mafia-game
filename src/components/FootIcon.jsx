import SvgIcon from '@mui/material/SvgIcon';

// 추방 버튼용 발 모양 아이콘. MUI 기본 아이콘에는 발바닥 모양이 없어 직접 그린다.
export default function FootIcon(props) {
  return (
    <SvgIcon {...props}>
      <path d="M12 9.2c-2.9 0-4.9 2.5-4.9 6.1 0 3.8 2 6.7 4.9 6.7s4.6-2.4 4.6-5.6c0-4.2-1.6-7.2-4.6-7.2z" />
      <circle cx="7.3" cy="6.4" r="1.6" />
      <circle cx="10" cy="4.2" r="1.45" />
      <circle cx="12.9" cy="3.5" r="1.25" />
      <circle cx="15.4" cy="4.3" r="1.1" />
      <circle cx="17.2" cy="6.2" r="0.95" />
    </SvgIcon>
  );
}
