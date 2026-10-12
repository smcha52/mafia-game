import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import CssBaseline from '@mui/material/CssBaseline';
import { ThemeProvider } from '@mui/material/styles';

import App from './App';
import HalloweenSpiders from './components/HalloweenSpiders';
import theme, { halloween } from './theme';
import './index.css';

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <App />
      {halloween && <HalloweenSpiders />}
    </ThemeProvider>
  </StrictMode>,
);
