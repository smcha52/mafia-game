import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import CssBaseline from '@mui/material/CssBaseline';
import { ThemeProvider } from '@mui/material/styles';

import App from './App';
import AutumnLeaves from './components/AutumnLeaves';
import HalloweenSpiders from './components/HalloweenSpiders';
import theme, { autumn, halloween } from './theme';
import './index.css';

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <App />
      {halloween && <HalloweenSpiders />}
      {autumn && <AutumnLeaves />}
    </ThemeProvider>
  </StrictMode>,
);
