import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import App from './App.jsx';
import { PreferencesProvider } from './Preferences.jsx';
import './styles.css';
import './hero.css';
import './preferences.css';

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <PreferencesProvider><App /></PreferencesProvider>
  </StrictMode>
);
