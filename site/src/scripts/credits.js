// The footer's credits, one at a time. Each line flocks in: its letters fly
// from scattered places and settle into line, hold, then fade out for the
// next. With Reduce Motion on, the lines simply change in place.
//
// The list itself is in index.astro (`credits`); screen readers get it whole.

const HOLD = 3200;      // ms a settled line stays
const STAGGER = 16;     // ms between letters arriving
const FLIGHT = 900;     // ms for a letter's flight (matches the CSS)
const FADE = 750;       // ms for the line to fade out (opacity .7s in the CSS)

export function startCredits(el) {
  const list = JSON.parse(el.dataset.credits || '[]');
  if (list.length < 2) return;
  const still = matchMedia('(prefers-reduced-motion: reduce)').matches;
  let i = 0;

  const scatter = s => {
    const a = Math.random() * Math.PI * 2, r = 28 + Math.random() * 48;
    s.style.transform = `translate(${(Math.cos(a) * r).toFixed(1)}px, ${(Math.sin(a) * r * 0.6).toFixed(1)}px) rotate(${((Math.random() - 0.5) * 70).toFixed(0)}deg)`;
    s.style.opacity = '0';
  };

  function show(text) {
    if (still) { el.textContent = text; return; }
    const letters = [...text].map(ch => {
      const s = document.createElement('span');
      s.className = 'cr-ch';
      s.textContent = ch === ' ' ? ' ' : ch;
      scatter(s);
      return s;
    });
    el.replaceChildren(...letters);
    // Two frames so the scattered start is drawn before the flight begins.
    requestAnimationFrame(() => requestAnimationFrame(() => letters.forEach((s, j) => {
      s.style.transitionDelay = `${j * STAGGER + Math.random() * 140}ms`;
      s.style.transform = '';
      s.style.opacity = '1';
    })));
    const settled = letters.length * STAGGER + 140 + FLIGHT;
    // Leaving: the whole line fades out together, letters staying in place.
    setTimeout(() => letters.forEach(s => {
      s.style.transitionDelay = '0ms';
      s.style.opacity = '0';
    }), settled + HOLD);
    return settled + HOLD + FADE;
  }

  function next() {
    const took = show(list[i]);
    i = (i + 1) % list.length;
    setTimeout(next, still ? 4000 : took);
  }
  next();
}
