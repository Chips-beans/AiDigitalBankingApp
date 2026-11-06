import { useEffect, useState } from 'react';
import StrokeText from '@/components/StrokeText';
import './splash.css';

// Splash: "KESOR Bank" is drawn in the primary gold outline, filled with gold,
// then the white sheet slides up to reveal the hero. Runs on every load/refresh.
// onReveal fires as the sheet starts to move, so the hero can animate in under it.

const DRAW = 1.15; // StrokeText drawDuration (s)
const STAGGER = 0.045; // per letter
const FILL_DELAY = 0.1;
const TEXT = 'KESOR Bank';
// draw + stagger across the letters + fill wipe (StrokeText: max(0.4, draw * 0.5)) + a short hold
const HOLD_MS = Math.round((DRAW + FILL_DELAY + Math.max(0.4, DRAW * 0.5) + 0.25) * 1000);
const EXIT_MS = 700;

export default function Splash({ onReveal }) {
  const reduced =
    typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const [phase, setPhase] = useState('draw'); // draw -> leave -> gone

  useEffect(() => {
    // always open at the top so the hero entrance is seen
    if ('scrollRestoration' in history) history.scrollRestoration = 'manual';
    window.scrollTo(0, 0);
    document.documentElement.classList.add('is-splashing');

    const leaveAt = reduced ? 600 : HOLD_MS;
    const t1 = setTimeout(() => {
      setPhase('leave');
      document.documentElement.classList.remove('is-splashing');
      onReveal?.();
    }, leaveAt);
    const t2 = setTimeout(() => setPhase('gone'), leaveAt + (reduced ? 300 : EXIT_MS));
    return () => {
      clearTimeout(t1);
      clearTimeout(t2);
      document.documentElement.classList.remove('is-splashing');
    };
    // run once per page load
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (phase === 'gone') return null;

  return (
    <div className={`splash ${phase === 'leave' ? 'is-leaving' : ''}`} role="presentation">
      <div className="splash-word">
        <StrokeText
          text={TEXT}
          strokeColor="#CDA32F"
          fillColor="#CDA32F"
          strokeWidth={1.6}
          drawDuration={DRAW}
          stagger={STAGGER}
          fillDelay={FILL_DELAY}
          fillMode="wipe"
          wipeFrom="left"
          fontFamily="Poppins, system-ui, sans-serif"
          fontWeight={600}
          fontSize={140}
          letterSpacing={-5}
          ease="power2.inOut"
        />
      </div>
    </div>
  );
}
