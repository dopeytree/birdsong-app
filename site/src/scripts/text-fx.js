// Text effects for the splash page. Murmur is the default (Ed's choice);
// ?fx=ink or ?fx=none in the address to compare.
// Ink colour only; moving the pointer (or a finger) disturbs the words near
// it, a tap sends a ring outward, and everything settles back to plain text.
// Off for anyone with Reduce Motion turned on.
//
//   murmur: letters lift and scatter a few pixels, turning slightly like a
//           flock, then spring back into line.
//   ink:    words waver as if seen through rippling water, then go still
//           (an SVG displacement filter, strongest nearest the pointer).

const TARGETS = 'h1, .lede, .kicker em';

// Options, for murmur (Ed, Nov 2026: the whole page murmurs, like the text):
//   letters: more text to split into letters that scatter (button words...).
//   dynamicLetters: text that comes and goes (the notifications), split into
//            letters when it's first found.
//   dynamic: letters that are already split and come and go (the credits'
//            flying letters).
//   Both are looked up afresh each time stirring begins.
//   wholes:  bigger things that sway and drift as one piece (outlines,
//            pictures), turning less the bigger they are.
// Bits, dynamic pieces and wholes move by the separate CSS translate and
// rotate properties, so they add to any transform they already have.
export function startTextFx(mode, { letters = '', dynamicLetters = '', dynamic = '', wholes = '' } = {}) {
  if (!['murmur', 'ink'].includes(mode)) return;
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  const murmuring = mode === 'murmur';
  const sel = murmuring && letters ? `${TARGETS}, ${letters}` : TARGETS;
  const els = [...document.querySelectorAll(sel)];
  const parts = els.flatMap(el => split(el, murmuring));
  const piece = (el, whole) => ({ el, whole, props: true, x: 0, y: 0, vx: 0, vy: 0 });
  if (murmuring) {
    if (wholes) document.querySelectorAll(wholes).forEach(el => parts.push(piece(el, true)));
  }
  // Dynamic pieces: drop the ones that have gone, add the new ones.
  const seen = new WeakSet();
  const refresh = () => {
    if (!murmuring || !(dynamic || dynamicLetters)) return [];
    const before = parts.length;
    for (let i = parts.length - 1; i >= 0; i--) if (parts[i].dyn && !parts[i].el.isConnected) parts.splice(i, 1);
    if (dynamic) document.querySelectorAll(dynamic).forEach(el => { if (!seen.has(el)) { seen.add(el); parts.push({ ...piece(el, false), dyn: true }); } });
    if (dynamicLetters) document.querySelectorAll(dynamicLetters).forEach(el => {
      if (seen.has(el)) return;
      seen.add(el);
      split(el, true).forEach(q => { q.dyn = true; parts.push(q); });
    });
    return parts.slice(before);
  };
  refresh();
  const fx = mode === 'murmur' ? murmur(parts) : ink(parts);

  // Rest positions, in page coordinates (and half sizes, for whole pieces).
  // Measured at rest: at the start, after the fonts arrive, on resize, and
  // whenever stirring begins (things move, appear and switch meanwhile).
  const place = p => {
    const r = p.el.getBoundingClientRect();
    p.cx = r.left + scrollX + r.width / 2;
    p.cy = r.top + scrollY + r.height / 2;
    p.hw = r.width / 2;
    p.hh = r.height / 2;
  };
  const measure = () => { refresh(); parts.forEach(p => { if (!p.moved) place(p); }); };
  measure();
  document.fonts?.ready.then(measure);
  addEventListener('resize', measure);

  let last = null, running = false;
  const ripples = [];
  const wake = () => { if (!running) { running = true; requestAnimationFrame(frame); } };

  addEventListener('pointermove', e => {
    // At rest, measure everything; mid-stir, take in any new pieces (a new
    // credit line, a new notification) and measure just those.
    if (!running) measure(); else refresh().forEach(place);
    const p = { x: e.pageX, y: e.pageY };
    if (last) fx.stir(p, Math.min(Math.hypot(p.x - last.x, p.y - last.y), 40), p.x - last.x, p.y - last.y);
    last = p;
    wake();
  }, { passive: true });
  addEventListener('pointerdown', e => {
    if (!running) measure();
    ripples.push({ x: e.pageX, y: e.pageY, t0: performance.now(), hit: new Set() });
    wake();
  }, { passive: true });

  function frame(now) {
    // A ring travels outward from each tap; parts it passes get a nudge.
    for (let i = ripples.length - 1; i >= 0; i--) {
      const r = ripples[i], radius = (now - r.t0) * 0.55;
      if (radius > 700) { ripples.splice(i, 1); continue; }
      const strength = Math.exp(-radius / 320);
      parts.forEach(p => {
        if (r.hit.has(p)) return;
        const d = gap(p, r.x, r.y);
        if (d < radius) { r.hit.add(p); fx.pulse(p, (p.cx - r.x) / (d || 1), (p.cy - r.y) / (d || 1), strength); }
      });
    }
    const busy = fx.step(now);
    if (busy || ripples.length) requestAnimationFrame(frame);
    else running = false;
  }
}

// Wrap each word (and, for murmur, each letter) in a span. Screen readers get
// the plain text from a hidden copy; the spans are hidden from them.
function split(el, letters) {
  const text = el.textContent.replace(/\s+/g, ' ').trim();
  const plain = document.createElement('span');
  plain.className = 'sr-only';
  plain.textContent = text;
  const shown = document.createElement('span');
  shown.setAttribute('aria-hidden', 'true');
  const parts = [];
  // Words keep the class of any span they were in (e.g. a coloured phrase).
  const tokens = [];
  el.childNodes.forEach(n => {
    const cls = n.nodeType === 1 ? n.className : '';
    n.textContent.split(/(\s+)/).forEach(t => tokens.push({ t: /^\s+$/.test(t) ? ' ' : t, cls }));
  });
  const words = tokens.filter(x => x.t);
  while (words[0]?.t === ' ') words.shift();
  while (words.at(-1)?.t === ' ') words.pop();
  words.forEach(({ t: tok, cls }, i) => {
    if (tok === ' ') {
      if (words[i - 1]?.t === ' ') return;
      // A space inside a picked-out phrase keeps its class (an underline runs on).
      const same = words[i - 1]?.cls && words[i - 1].cls === words[i + 1]?.cls;
      if (same) { const sp = document.createElement('span'); sp.className = words[i - 1].cls; sp.textContent = ' '; shown.append(sp); }
      else shown.append(' ');
      return;
    }
    const w = document.createElement('span');
    w.className = cls ? `fx-word ${cls}` : 'fx-word';
    if (letters) {
      [...tok].forEach(ch => {
        const c = document.createElement('span');
        c.className = 'fx-ch';
        c.textContent = ch;
        w.append(c);
        parts.push({ el: c, x: 0, y: 0, vx: 0, vy: 0 });
      });
    } else {
      w.textContent = tok;
      parts.push({ el: w, e: 0, level: 0 });
    }
    shown.append(w);
  });
  el.replaceChildren(plain, shown);
  return parts;
}

// How far a point is from a part: from a letter's centre, or from the edge
// of a whole piece (0 when the point is over it).
function gap(q, x, y) {
  if (!q.whole) return Math.hypot(q.cx - x, q.cy - y);
  return Math.hypot(Math.max(0, Math.abs(q.cx - x) - q.hw), Math.max(0, Math.abs(q.cy - y) - q.hh));
}

function murmur(parts) {
  const R = 90, MAX = 9;
  return {
    stir(p, speed, mx, my) {
      parts.forEach(q => {
        const d = gap(q, p.x, p.y);
        if (d > R) return;
        const dx = q.cx - p.x, dy = q.cy - p.y, c = Math.hypot(dx, dy) || 1;
        const f = (1 - d / R) ** 2 * speed * 0.05;
        // Away from the pointer, and carried a little along its path.
        q.vx += (dx / c) * f + mx * f * 0.03;
        q.vy += (dy / c) * f + my * f * 0.03;
      });
    },
    pulse(q, ux, uy, s) { q.vx += ux * 2.2 * s; q.vy += uy * 2.2 * s; },
    step() {
      let busy = false;
      parts.forEach(q => {
        q.vx = (q.vx - q.x * 0.07) * 0.84;
        q.vy = (q.vy - q.y * 0.07) * 0.84;
        q.x = Math.max(-MAX, Math.min(MAX, q.x + q.vx));
        q.y = Math.max(-MAX, Math.min(MAX, q.y + q.vy));
        const still = Math.abs(q.x) + Math.abs(q.y) + Math.abs(q.vx) + Math.abs(q.vy) < 0.05;
        if (still) {
          if (q.moved) {
            if (q.props) { q.el.style.translate = ''; q.el.style.rotate = ''; }
            else q.el.style.transform = '';
            q.moved = false;
          }
          q.x = q.y = q.vx = q.vy = 0;
          return;
        }
        busy = true;
        q.moved = true;
        // Pieces use the separate translate/rotate properties, so they add to
        // the transforms they already have (hover, flights). Whole pieces
        // turn less the bigger they are.
        const size = q.whole ? Math.max(2 * q.hw, 2 * q.hh, 1) : 1;
        const turn = Math.max(-14, Math.min(14, q.vx * 3)) * (q.whole ? Math.min(1, 40 / size) : 1);
        if (q.props) {
          q.el.style.translate = `${q.x.toFixed(2)}px ${q.y.toFixed(2)}px`;
          q.el.style.rotate = `${turn.toFixed(2)}deg`;
        } else q.el.style.transform = `translate(${q.x.toFixed(2)}px, ${q.y.toFixed(2)}px) rotate(${turn.toFixed(1)}deg)`;
      });
      return busy;
    },
  };
}

function ink(parts) {
  // Four strengths of the same watery filter; each word takes the one that
  // matches how disturbed it is.
  const scales = [1.5, 3, 4.5, 6];
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('width', '0'); svg.setAttribute('height', '0');
  svg.setAttribute('aria-hidden', 'true');
  svg.style.position = 'absolute';
  svg.innerHTML = scales.map((s, i) => `
    <filter id="fx-ink-${i + 1}" x="-15%" y="-40%" width="130%" height="180%">
      <feTurbulence class="fx-water" type="fractalNoise" baseFrequency="0.035 0.09" numOctaves="2" seed="${i * 7 + 3}" result="w"/>
      <feDisplacementMap in="SourceGraphic" in2="w" scale="${s}" xChannelSelector="R" yChannelSelector="G"/>
    </filter>`).join('');
  document.body.append(svg);
  const water = [...svg.querySelectorAll('.fx-water')];
  const R = 110;
  return {
    stir(p, speed) {
      parts.forEach(q => {
        const d = Math.hypot(q.cx - p.x, q.cy - p.y);
        if (d < R) q.e = Math.max(q.e, (1 - d / R) * Math.min(speed / 18, 1));
      });
    },
    pulse(q, ux, uy, s) { q.e = Math.max(q.e, 0.9 * s); },
    step(now) {
      // The water keeps moving while anything is disturbed.
      const bf = `${(0.035 + 0.008 * Math.sin(now / 380)).toFixed(4)} ${(0.09 + 0.015 * Math.cos(now / 520)).toFixed(4)}`;
      water.forEach(t => t.setAttribute('baseFrequency', bf));
      let busy = false;
      parts.forEach(q => {
        q.e *= 0.95;
        if (q.e < 0.04) q.e = 0;
        const level = Math.ceil(q.e * scales.length);
        if (level !== q.level) { q.level = level; q.el.style.filter = level ? `url(#fx-ink-${level})` : ''; }
        if (q.e) busy = true;
      });
      return busy;
    },
  };
}
