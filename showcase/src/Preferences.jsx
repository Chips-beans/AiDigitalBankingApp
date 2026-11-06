import { createContext, useCallback, useContext, useLayoutEffect, useMemo, useState } from 'react';
import { khmer } from './i18n.js';

const PreferencesContext = createContext(null);
const save = (key, value) => { try { localStorage.setItem(key, value); } catch { /* Preferences still work without storage. */ } };

export function PreferencesProvider({ children }) {
  const [theme, setTheme] = useState(() => document.documentElement.dataset.theme || 'light');
  const [language, setLanguage] = useState(() => document.documentElement.lang === 'km' ? 'km' : 'en');
  const t = useCallback(text => language === 'km' ? khmer[text] ?? text : text, [language]);
  useLayoutEffect(() => {
    document.documentElement.dataset.theme = theme;
    document.documentElement.style.colorScheme = theme;
  }, [theme]);
  useLayoutEffect(() => {
    document.documentElement.lang = language;
    document.querySelector('meta[name="description"]').content = t('A full-stack banking solution connecting customer and merchant experiences through Flutter and Spring Boot.');
  }, [language, t]);
  const toggleTheme = useCallback(() => setTheme(current => {
    const next = current === 'light' ? 'dark' : 'light';
    save('kesor-theme', next);
    return next;
  }), []);
  const chooseLanguage = useCallback(next => { if (!['en', 'km'].includes(next)) return; save('kesor-language', next); setLanguage(next); }, []);
  const value = useMemo(() => ({ theme, language, t, toggleTheme, chooseLanguage }), [theme, language, t, toggleTheme, chooseLanguage]);
  return <PreferencesContext.Provider value={value}>{children}</PreferencesContext.Provider>;
}

export const usePreferences = () => useContext(PreferencesContext);

export function DisplaySwitches() {
  const { theme, language, t, toggleTheme, chooseLanguage } = usePreferences();
  const label = t(theme === 'light' ? 'Switch to dark mode' : 'Switch to light mode');
  return (
    <div className="display-switches" role="group" aria-label={t('Display preferences')}>
      <button className="theme-switch" type="button" onClick={toggleTheme} aria-label={label} title={label} aria-pressed={theme === 'dark'}>
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          {theme === 'light' ? <path d="M20.3 13.6A8.4 8.4 0 0 1 10.4 3.7 8.4 8.4 0 1 0 20.3 13.6Z" /> : <><circle cx="12" cy="12" r="4" /><path d="M12 2v2m0 16v2M2 12h2m16 0h2M4.9 4.9l1.4 1.4m11.4 11.4 1.4 1.4m0-14.2-1.4 1.4M6.3 17.7l-1.4 1.4" /></>}
        </svg>
      </button>
      <div className="language-switch" role="group" aria-label={t('Language')}>
        <button type="button" lang="en" aria-label="English" aria-pressed={language === 'en'} onClick={() => chooseLanguage('en')}>EN</button>
        <button type="button" lang="km" aria-label="ភាសាខ្មែរ" aria-pressed={language === 'km'} onClick={() => chooseLanguage('km')}>ខ្មែរ</button>
      </div>
    </div>
  );
}
