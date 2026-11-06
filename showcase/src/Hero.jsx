import { lazy, Suspense, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import CursorGrid from '@/components/CursorGrid';
import TechText from '@/components/TechText';
import TextLoop from '@/components/TextLoop';
import OrbitImages from '@/components/OrbitImages';
import { DisplaySwitches, usePreferences } from './Preferences.jsx';

const ORBIT_SET = [
  { src: '/orbit/bank.webp', alt: 'Kesor Bank app icon' },
  { src: '/orbit/merchant.webp', alt: 'Kesor Merchant app icon' },
  { src: '/orbit/assistant.webp', alt: 'Kesor AI Assistant' },
];
// the three images twice, so six tiles share the orbit
const ORBIT_IMAGES = [...ORBIT_SET, ...ORBIT_SET];
import { links } from './data.js';

// three.js is large; load the lanyard after the page's own code. The chunk is
// fetched while the splash plays. It is mounted once the copy has finished its
// entrance (WebGL setup briefly blocks the main thread, which would stutter the
// title), and its own drop-in intro is the last beat of the hero entrance.
const loadLanyard = () => import('@/components/Lanyard');
const Lanyard = lazy(loadLanyard);
const LANYARD_DELAY_MS = 1000;

// Hero from Figma "Kesor Bank" node 437:2492 (MacBook Pro 14", 1512 wide).
// The hanging ID badge is React Bits' Lanyard (three.js), dressed with the
// Kesor card face and a navy strap printed with the Kesor mark.

function useViewportWidth() {
  const [width, setWidth] = useState(() => window.innerWidth);
  useEffect(() => {
    const on = () => setWidth(window.innerWidth);
    window.addEventListener('resize', on);
    return () => window.removeEventListener('resize', on);
  }, []);
  return width;
}

// The lanyard canvas covers the hero (and spills below it), so the card's size
// and strap length are given as fractions of that layer. These are the pixel
// targets: overlay height (matches --lanyard-h), card height, card top.
const DESKTOP = { h: 1200, card: 330, top: 168 };
const PHONE = { h: 1000, card: 250, top: 120 };

function lanyardFraming(vw) {
  const phone = vw <= 760;
  const f = phone ? PHONE : DESKTOP;
  // card top sits at mix(0.12, 0.42, strapLength) of the layer height
  const strapLength = Math.min(1, Math.max(0, (f.top / f.h - 0.12) / 0.3));
  // desktop: x 1067 of the 1512 Figma frame, inside a centred max-width column;
  // phone: just right of centre, in the gap between the name and the buttons
  const column = Math.min(vw, 1512);
  const anchor = phone ? 0.62 : ((vw - column) / 2 + column * 0.706) / vw;
  return { size: f.card / f.h, strapLength, anchor };
}

// Where the left copy block's top-left corner sits inside the hero, so the
// background grid's lines can be made to pass through it.
function useGridOrigin(heroRef, copyRef) {
  const [origin, setOrigin] = useState(null);
  useLayoutEffect(() => {
    const hero = heroRef.current;
    const copy = copyRef.current;
    if (!hero || !copy) return undefined;
    const measure = () => {
      // offsets ignore the entrance transform, unlike getBoundingClientRect
      let x = 0;
      let y = 0;
      for (let el = copy; el && el !== hero; el = el.offsetParent) {
        x += el.offsetLeft;
        y += el.offsetTop;
      }
      setOrigin(prev => (prev && prev.x === x && prev.y === y ? prev : { x, y }));
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(hero);
    return () => observer.disconnect();
  }, [heroRef, copyRef]);
  return origin;
}

export default function Hero({ ready = true }) {
  const { theme, language, t } = usePreferences();
  const dark = theme === 'dark';
  const orbitImages = useMemo(() => ORBIT_IMAGES.map(image => ({ ...image, alt: t(image.alt) })), [t]);
  const vw = useViewportWidth();
  const framing = lanyardFraming(vw);
  const heroRef = useRef(null);
  const copyRef = useRef(null);
  const origin = useGridOrigin(heroRef, copyRef);
  const cell = vw <= 760 ? 48 : 64; // = --cell in hero.css

  const [cardOn, setCardOn] = useState(false);
  useEffect(() => {
    loadLanyard();
  }, []);
  useEffect(() => {
    if (!ready) return undefined;
    const t = setTimeout(() => setCardOn(true), LANYARD_DELAY_MS);
    return () => clearTimeout(t);
  }, [ready]);

  return (
    <header className={`hero${ready ? ' is-ready' : ''}`} id="top" ref={heroRef}>
      {/* React Bits CursorGrid: a faint navy grid whose cells light up gold under the pointer */}
      <div className="hero-grid" aria-hidden="true">
        {ready && (
        <CursorGrid
          lightMode={!dark}
          cellSize={cell}
          originX={origin?.x}
          originY={origin?.y}
          gridColor={dark ? '#b7cbe0' : '#133358'}
          color="#CDA32F"
          gridOpacity={0.08}
          fillOpacity={0.08}
          maxOpacity={0.9}
          radius={150}
          spotlight={0.5}
          edgeFade={0.06}
        />
        )}
      </div>

      <div className="hero-inner">
        <nav className="hero-top" aria-label={t('Project links')}>
          <a className="hero-brand" href="#top">
            <span className="hero-logo">
              <img src="/hero/logo.svg" alt="" width="42.6667" height="53.329" />
            </span>
            <span className="hero-brand-name">Kesor Bank PLc.</span>
          </a>
          <div className="hero-pills">
            <a className="hero-pill github-link" href={links.github} aria-label={t('GitHub repository')}>
              <img src="/hero/github.svg" alt="" width="24" height="24" />
              <span>Github</span>
            </a>
            <a className="hero-pill" href={links.figma} aria-label={t('Figma design file')}>
              <img src="/hero/figma.svg" alt="" width="24" height="24" />
              <span>Figma</span>
            </a>
            <DisplaySwitches />
          </div>
        </nav>

        {/* React Bits OrbitImages: the two app icons and the AI Assistant (twice) on a
            visible tilted ellipse. Wide screens: in the open space right of "Connect."
            and left of the card. Narrower: a flatter ring above "to" and "C". */}
        <div className="hero-orbit">
          <OrbitImages
            images={orbitImages}
            altPrefix="Kesor"
            shape="ellipse"
            radiusX={vw > 1300 ? 420 : 700}
            radiusY={vw > 1300 ? 230 : 140}
            rotation={-6}
            itemSize={170}
            duration={34}
            depth={0.55}
            itemRadius={34}
            shadow={0.18}
            hoverScale={1.08}
            showPath
            pathColor={dark ? 'rgba(183, 203, 224, 0.3)' : 'rgba(19, 51, 88, 0.22)'}
            pathWidth={1.5}
          />
        </div>

        <div className="hero-lanyard-space" aria-hidden="true" />

        <div className="hero-copy" ref={copyRef}>
          {/* React Bits TechText: one canvas per line (it draws a single line in one
              colour). The h1 keeps the real words for screen readers and search. */}
          <h1 className="hero-title">
            <span className="sr-only">{t('Built to Connect.')} {t('Designed to Flow.')}</span>
            {['Built to Connect.', 'Designed to Flow.'].map(line => (
              <span className="hero-line" key={line} aria-hidden="true">
                <span className="hero-line-in">
                  <TechText
                    text={t(line)}
                    align="left"
                    fontFamily={language === 'km' ? 'Google Sans, sans-serif' : 'Poppins, system-ui, sans-serif'}
                    fontWeight={500}
                    fontSize={vw <= 760 ? Math.round(vw * 0.098) : language === 'km' && vw <= 1100 ? 44 : 64}
                    letterSpacing={language === 'km' ? 0 : -0.02}
                    color={dark ? '#f4f7fa' : '#0B1F35'}
                    accentColor="#CDA32F"
                    reach={vw <= 760 ? 140 : 230}
                    softness={0.9}
                    bounce={0.15}
                    speed={0.55}
                    ease={2.2}
                  />
                </span>
              </span>
            ))}
          </h1>
          <p className="hero-lead">
            {t('A full-stack banking solution connecting customer and merchant experiences through Flutter and Spring Boot.')}
          </p>
          <div className="hero-apks">
            <a className="hero-apk apk-customer" href={links.customerApk} download="Kesor Bank.apk">
              <img src="/hero/android-gold.svg" alt="" width="24" height="24" />
              <span>{t('Kesor Bank APK')}</span>
            </a>
            <a className="hero-apk apk-merchant" href={links.merchantApk} download="KesorMerchant.apk">
              <img src="/hero/android-navy.svg" alt="" width="24" height="24" />
              <span>{t('Kesor Merchant APK')}</span>
            </a>
          </div>
        </div>
      </div>

      {/* React Bits TextLoop: a gold ribbon of the three phrases along a gentle wave,
          closing the hero under the buttons and the card */}
      <div className="hero-ribbon" role="img" aria-label={t('Designed to Inspire. ✦ Made to Move. ✦ Created to Stand Out.')}>
        <TextLoop
          text={t('Designed to Inspire. ✦ Made to Move. ✦ Created to Stand Out.')}
          separator="✦"
          shape="wave"
          curviness={26}
          speed={70}
          fontSize={32}
          fontWeight={600}
          letterSpacing={language === 'km' ? 0 : 2.5}
          color="#0B1F35"
          ribbonColor="#CDA32F"
          ribbonWidth={56}
          pauseOnHover={false}
        />
      </div>

      <div className="hero-lanyard" role="img" aria-label={t('Kesor Bank ID card hanging on a lanyard')}>
        {cardOn && (
        <Suspense fallback={null}>
          <Lanyard
            frontImage="/lanyard/card-front.svg"
            strapImage="/lanyard/strap.svg"
            strapColor="#133358"
            cardColor="#F4F4F4"
            finish="matte"
            cornerRadius={0.25}
            metal="silver"
            anchor={framing.anchor}
            size={framing.size}
            strapLength={framing.strapLength}
            strapWidth={0.6}
            damping={0.7}
            breeze={0.15}
          />
        </Suspense>
        )}
      </div>
    </header>
  );
}
