import { useEffect, useMemo, useState } from 'react';
import { siFlutter, siDart, siAndroid, siSpringboot, siOpenjdk, siSpringsecurity, siHibernate, siJsonwebtokens, siApachemaven, siSwagger, siPostgresql, siFlyway, siGithub, siFigma, siDocker, siRailway, siJunit5, siGmail, siTelegram } from 'simple-icons';
import { links, stack, team, aiTools } from './data.js';
import Hero from './Hero.jsx';
import Splash from './Splash.jsx';
import GridMotion from '@/components/GridMotion';
import CircularCarousel from '@/components/CircularCarousel';
import InfiniteSpiral from '@/components/InfiniteSpiral';
import DomeGallery from '@/components/DomeGallery';
import { usePreferences } from './Preferences.jsx';

const icons = { siFlutter, siDart, siAndroid, siSpringboot, siOpenjdk, siSpringsecurity, siHibernate, siJsonwebtokens, siApachemaven, siSwagger, siPostgresql, siFlyway, siGithub, siFigma, siDocker, siRailway, siJunit5, siGmail, siTelegram };
// Latest Merchant App screens (Figma change-list captures, 5 Nov 2026, plus the
// 6 Nov splash), shown as phone-shaped cards in the Orbit carousel. Orbit scales
// the whole ring to fit its box, so the card count is kept to eight.
const merchantCards = [
  ['mc-home', 'Home', "Today's collections and business wallets"],
  ['mc-collect', 'Collect', 'Enter the amount to receive'],
  ['mc-waiting', 'Waiting for payment', 'A Kesor Merchant QR for the customer'],
  ['mc-received', 'Payment received', 'Confirmed with the full breakdown'],
  ['mc-sales', 'Sales', 'Every payment, searchable'],
  ['mc-receipt', 'Receipt', 'Share or save each sale'],
  ['mc-reports', 'Collections report', 'Daily and monthly totals'],
  ['mc-transfer', 'Transfer to my wallet', 'Move takings to the owner'],
].map(([id, title, subtitle]) => ({ src: `/screens/${id}.webp`, alt: `Merchant App: ${title}`, title, subtitle }));

function useNarrow(query = '(max-width: 760px)') {
  const [narrow, setNarrow] = useState(() => window.matchMedia(query).matches);
  useEffect(() => {
    const mq = window.matchMedia(query);
    const on = () => setNarrow(mq.matches);
    mq.addEventListener('change', on);
    return () => mq.removeEventListener('change', on);
  }, [query]);
  return narrow;
}

// Latest Customer App renders (Flutter QA captures, 4-6 Nov 2026), shown as
// phone-shaped tiles in the Customer section's moving grid.
const customerTiles = [
  ['cg-home', 'Home with balances and favourite recipients'],
  ['cg-wallets', 'Riel, dollar and merchant wallets'],
  ['cg-analytics', 'Monthly analytics'],
  ['cg-review', 'Review transfer'],
  ['cg-assistant', 'AI assistant'],
  ['cg-wallet', 'Wallet details and history'],
  ['cg-qr', 'Kesor QR with a requested amount'],
  ['cg-success', 'Transfer successful'],
  ['cg-receipt', 'Transaction receipt'],
  ['cg-home-preview', 'Home before the PIN, money masked'],
  ['cg-splash', 'Kesor Bank splash'],
].map(([id, alt]) => ({ src: `/screens/${id}.webp`, alt }));

function useReveal() {
  useEffect(() => {
    if (!('IntersectionObserver' in window) || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    const observer = new IntersectionObserver(entries => {
      entries.forEach(({ target, isIntersecting }) => {
        if (!isIntersecting) return;
        target.animate([{ opacity: 0, transform: 'translateY(24px)' }, { opacity: 1, transform: 'translateY(0)' }], {
          duration: 700, delay: Number(target.dataset.delay || 0), easing: 'cubic-bezier(.16,1,.3,1)', fill: 'backwards',
        });
        observer.unobserve(target);
      });
    }, { threshold: 0.08 });
    document.querySelectorAll('[data-reveal]').forEach(element => observer.observe(element));
    return () => observer.disconnect();
  }, []);
}

function Screen({ id, alt, className = '' }) {
  // Decode before replacing so a new selection never flashes an empty frame.
  const [shown, setShown] = useState(id);
  useEffect(() => {
    let current = true;
    const image = new Image();
    image.src = `/screens/${id}.webp`;
    image.decode().then(() => { if (current) setShown(id); }).catch(() => {});
    return () => { current = false; };
  }, [id]);
  return <img className={`product-screen ${className}`} src={`/screens/${shown}.webp`} alt={alt} width="720" height="1560" loading="lazy" />;
}

function CustomerChapter() {
  const { t } = usePreferences();
  const tiles = useMemo(() => customerTiles.map(item => ({ ...item, alt: t(item.alt) })), [t]);
  return (
    <section className="chapter customer" id="customer" aria-labelledby="customer-h">
      <div className="customer-layout">
        <div className="customer-copy">
          <h2 id="customer-h" data-reveal>{t('Customer App')}</h2>
          <p className="section-lead" data-reveal data-delay="70">{t('Your everyday money,')}<br />{t('in riel and dollars.')}</p>
          <p className="body-copy" data-reveal data-delay="140">{t('Two wallets, instant transfers and a monthly picture of where the money went. Built for everyday banking in Cambodia.')}</p>
        </div>
        <figure className="customer-preview" id="customer-preview" data-reveal data-delay="120">
          <div className="customer-grid" data-ui role="img" aria-label={t('Screens from the latest Customer App design moving in a grid')}>
            <GridMotion
              items={tiles}
              rows={3}
              aspectRatio={0.46}
              gap={14}
              radius={18}
              angle={-10}
              speed={18}
              parallax={0.4}
              spotlight={0.5}
              dim={0.12}
              fade={0.3}
              theme="light"
              tileColor="#ffffff"
            />
          </div>
        </figure>
      </div>
    </section>
  );
}

function MerchantChapter() {
  const { t, language } = usePreferences();
  const cards = useMemo(() => merchantCards.map(item => ({ ...item, title: t(item.title), subtitle: t(item.subtitle), alt: `${t('Merchant App')}: ${t(item.title)}` })), [t]);
  const narrow = useNarrow();
  return (
    <section className="chapter merchant" id="merchant" aria-labelledby="merchant-h">
      <div className="merchant-layout">
        <div className="merchant-carousel" data-reveal data-delay="100" data-ui>
          <CircularCarousel
            items={cards}
            ariaLabel={t('Image carousel')}
            itemLabel={(item, index, count) => language === 'km' ? `${item.title}, ${index + 1} ក្នុងចំណោម ${count}` : `${item.title}, ${index + 1} of ${count}`}
            preset="orbit"
            cardWidth={230}
            aspectRatio={393 / 852}
            gap={10}
            cornerRadius={narrow ? 18 : 24}
            fadeColor="var(--section-ground)"
            depthFade={0.6}
            autoplay="drift"
            speed={12}
            captions
          />
        </div>
        <div className="merchant-copy">
          <h2 id="merchant-h" data-reveal>{t('Merchant App')}</h2>
          <p className="section-lead" data-reveal data-delay="70">{t('A till in your pocket.')}<br />{t('A view of your business.')}</p>
          <p className="body-copy" data-reveal data-delay="140">{t('Collect a payment, find a receipt and check the day’s takings. Sign in through the owner’s Customer App, with no second password.')}</p>
        </div>
      </div>
    </section>
  );
}

// Groq has no simple-icons entry: a plain wordmark in its brand colour stands in.
const GROQ = { hex: 'F55036' };

// Each logo becomes a small SVG tile (brand-coloured mark + name) for the spiral.
const logoTile = item => {
  const ic = icons[item.icon];
  const color = `#${(ic ?? GROQ).hex}`;
  const mark = ic
    ? `<g transform="translate(44 26) scale(3)"><path fill="${color}" d="${ic.path}"/></g>`
    : `<text x="80" y="78" text-anchor="middle" font-family="Poppins, Arial, sans-serif" font-size="42" font-weight="700" fill="${color}">groq</text>`;
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="160" height="160" viewBox="0 0 160 160"><rect width="160" height="160" fill="#ffffff"/>${mark}<text x="80" y="136" text-anchor="middle" font-family="Poppins, Arial, sans-serif" font-size="15" font-weight="500" fill="#133358">${item.name}</text></svg>`;
  return { src: `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`, alt: item.name, label: item.name };
};
const stackTiles = stack.flatMap(group => group.items).map(logoTile);

function StackIcon({ icon }) {
  if (icons[icon]) return <svg viewBox="0 0 24 24" aria-hidden="true"><path d={icons[icon].path} /></svg>;
  return <span className="stack-mark" aria-hidden="true">g</span>;
}

function TechStack() {
  const { t } = usePreferences();
  const narrow = useNarrow();
  return (
    <section className="chapter technology" id="stack" aria-labelledby="stack-h">
      <div className="tech-layout">
        <div className="tech-copy">
          <h2 id="stack-h" data-reveal>{t('Built together')}</h2>
          <p className="section-lead" data-reveal data-delay="70">{t('Two Flutter clients.')}<br />{t('One Spring Boot backend.')}</p>
          <dl className="stack-groups">
            {stack.map((group, i) => (
              <div className="stack-group" key={group.group} data-reveal data-delay={120 + i * 60}>
                <dt>{t(group.group)}</dt>
                <dd>
                  <ul>
                    {group.items.map(item => <li key={item.name}><StackIcon icon={item.icon} />{item.name}</li>)}
                  </ul>
                </dd>
              </div>
            ))}
          </dl>
        </div>
        <div className="tech-spiral" data-reveal data-delay="100" data-ui role="img" aria-label={t('Logos of the technologies used, turning in a spiral')}>
          <InfiniteSpiral
            items={stackTiles}
            cardWidth={narrow ? 76 : 104}
            cardHeight={narrow ? 76 : 104}
            radius={narrow ? 120 : 190}
            verticalSpacing={narrow ? 26 : 34}
            cardsPerTurn={8}
            cardRadius={20}
            centerScale={1.15}
            edgeFade={0.35}
            edgeBlur={4}
            imageFit="contain"
            speed={0.45}
            pauseOnHover={false}
          />
        </div>
      </div>
    </section>
  );
}

// The dome shows the three AI tools the team worked with (Gemini, Claude, Codex),
// listed twice; the component repeats them to fill every tile on the sphere.
const domeImages = [...aiTools, ...aiTools];

function Team() {
  const { t } = usePreferences();
  const narrow = useNarrow();
  return (
    <section className="chapter team" id="team" aria-labelledby="team-h">
      <div className="team-layout">
        <div className="team-copy">
          <h2 id="team-h" data-reveal>{t('The people behind Kesor')}</h2>
          <p className="section-lead" data-reveal data-delay="70">{t('Three developers.')}<br />{t('One banking platform.')}</p>
          <p className="body-copy" data-reveal data-delay="140">{t('Kesor was designed, built and tested by a team of three students, with Gemini, Claude and Codex as AI tools along the way.')}</p>
          <ul className="team-members">
            {team.map((member, i) => (
              <li className="team-member" key={member.name} data-reveal data-delay={200 + i * 80}>
                <img src={member.photo} alt="" width="88" height="88" loading="lazy" />
                <div>
                  <h3>{member.name}</h3>
                  <p className="member-role">{t(member.role)}</p>
                  <p className="member-duties">{t(member.duties)}</p>
                </div>
              </li>
            ))}
          </ul>
        </div>
        <div className="team-dome" data-reveal data-delay="120" data-ui>
          <DomeGallery
            images={domeImages}
            autoRotateSpeed={narrow ? 10 : 12}
            fit={narrow ? 0.62 : 0.52}
            minRadius={narrow ? 380 : 560}
            segments={narrow ? 28 : 34}
            overlayBlurColor="var(--section-ground)"
            grayscale={false}
            imageBorderRadius="22px"
            openedImageBorderRadius="26px"
            openedImageWidth={narrow ? '280px' : '360px'}
            openedImageHeight={narrow ? '280px' : '360px'}
          />
        </div>
      </div>
    </section>
  );
}

function Footer() {
  const { t } = usePreferences();
  return (
    <footer className="chapter footer" aria-labelledby="footer-h">
      <div className="footer-top">
        <div className="footer-brand">
          <h2 id="footer-h">Kesor Bank</h2>
          <p>{t('Explore the design.')}<br />{t('Read the source.')}</p>
        </div>
        <nav className="footer-nav" aria-label={t('Footer navigation')}>
          <a href="#customer">{t('Customer App')}</a>
          <a href="#merchant">{t('Merchant App')}</a>
          <a href="#stack">{t('Tech stack')}</a>
        </nav>
        <div className="footer-actions">
          <a className="repository-link" href={links.github}>{t('View on GitHub')} <span aria-hidden="true">↗</span></a>
          <a className="repository-link" href={links.figma}>{t('View on Figma')} <span aria-hidden="true">↗</span></a>
          <a href="#top">{t('Back to top')}</a>
        </div>
      </div>
    </footer>
  );
}

export default function App() {
  useReveal();
  const [revealed, setRevealed] = useState(false);
  return <><Splash onReveal={() => setRevealed(true)} /><Hero ready={revealed} /><main className="showcase-content"><CustomerChapter /><MerchantChapter /><TechStack /><Team /></main><Footer /></>;
}
