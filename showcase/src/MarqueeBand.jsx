import CurvedLoop from '@/components/CurvedLoop';
import './marquee-band.css';

// Gold band under the hero: three phrases running along a bending arc
// (React Bits CurvedLoop). Drag it to fling the text either way.
const PHRASES = ['Designed to Inspire', 'Made to Move', 'Designed to Stand Out'];

export default function MarqueeBand() {
  return (
    <section className="marquee-band" aria-label={PHRASES.join(', ')}>
      <CurvedLoop
        marqueeText={PHRASES.join(' ✦ ')}
        separator={'✦'}
        shape="arc"
        curveAmount={220}
        speed={1.6}
        direction="left"
        fontSize={92}
        fontWeight={600}
        letterSpacing={-1}
        color="#0B1F35"
        interactive
      />
    </section>
  );
}
