# Splash page: notification modes (archived)

Removed from `site/src/pages/index.astro` in Nov 2026, when Ed settled on the
Northern Cardinal arriving with the "Powered by BirdNET" credit. Kept here in
case the other rhythms are wanted again. Nothing loads this file.

The modes were cycled by a shuffle button (bottom right) or `?rhythm=`:

- **cardinal** (kept, now the only one): the cardinal each time "Powered by
  BirdNET" flies into the footer credits.
- **intro**: 5 s after the page opens, a burst of three, 5 s clear, then each
  other species of walk #20 alone with 5 s clear between.
- **single**: every species of walk #20 in the order first heard, each alone,
  3 s clear between.
- **round**: five (the cardinal and the walk's first four): three, 5 s clear,
  two, 10 s clear, again; gaps in a burst the walk's own, 5× faster.
- **random**: the round with made-up gaps.

It relied on `notify()`, `STAY`, the `#notice` template and
`src/data/walk-20.json` (still in the repo), imported as `walk`.

## The button

```html
  <!-- Test: the walk's own rhythm, or a made-up one. Lucide "shuffle" (ISC). -->
  <button class="mode rhythm" type="button" aria-pressed="false" aria-label="Random rhythm" title="Rhythm: the walk's own (click for random)">
    <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">
      <path d="m18 14 4 4-4 4" /><path d="m18 2 4 4-4 4" /><path d="M2 18h1.973a4 4 0 0 0 3.3-1.7l5.454-7.6a4 4 0 0 1 3.3-1.7H22" /><path d="M2 6h1.973a4 4 0 0 1 3.3 1.7l1.174 1.6" /><path d="M22 18h-6.041a4 4 0 0 1-3.3-1.8l-.359-.45" />
    </svg>
  </button>
```

## Its styles

```css
  .rhythm { top: auto; bottom: 18px; }
  .rhythm[aria-pressed='true'] { background: var(--ink); color: var(--page); }
  /* mobile: */
  .rhythm { top: 10px; bottom: auto; right: auto; left: 10px; }
```

## The script

```js
    // How the notifications play. Five modes, cycled by the shuffle button
    // (bottom right) or picked with ?rhythm=cardinal|intro|single|round|random:
    //   cardinal (default, Ed, Nov 2026): only the Northern Cardinal, each
    //     time "Powered by BirdNET" flies into the footer's credits (first at
    //     about 11 s, then once per round of the credits).
    //   intro: 5 s after the page opens, a burst of three
    //     (the cardinal and the walk's first two), 5 s of clear screen, then
    //     every other species one at a time with 5 s clear between; then
    //     again from the burst.
    //   single: every species of walk #20 in the order
    //     first heard, after the opening Northern Cardinal; one at a time,
    //     then 3 s of clear screen before the next.
    //   round: five (the cardinal and the walk's first four), as three, a
    //     rest with 5 s clear, two, then a long rest with 10 s clear; gaps in
    //     a burst are the walk's own, 5× faster. Then the same five again.
    //   random: the round of five with made-up gaps within a burst.
    // Walk #20 is Fri 25 Dec 2026: src/data/walk-20.json, made by
    // tool/export_site_walk.py. Points are a stand-in until the app has its
    // own rule: 10 for a new species, plus 10 a call heard.
    const SPEED = 5, OPENING = 1200;
    const GONE = STAY + 350;                       // until a banner has left
    const REST = GONE + 5000, LONG_REST = GONE + 10000, BETWEEN = GONE + 3000;
    const CARDINAL = { common: 'Northern Cardinal', points: 50, at: 0 };
    const ALL = [CARDINAL, ...walk.species.map(s => ({ common: s.common, points: 10 + 10 * s.calls, at: s.firstHeardSeconds }))];
    const ROUND = ALL.slice(0, 5);
    const MODES = ['cardinal', 'intro', 'single', 'round', 'random'];
    const NAMES = { cardinal: 'the cardinal alone', intro: 'three, then one at a time', single: 'one at a time', round: 'a round of five', random: 'random gaps' };
    let rhythm = MODES.includes(new URLSearchParams(location.search).get('rhythm')) ? new URLSearchParams(location.search).get('rhythm') : 'cardinal';
    let k = -1, timer = null, playing = true;
    const list = () => rhythm === 'cardinal' ? [CARDINAL] : rhythm === 'intro' || rhythm === 'single' ? ALL : ROUND;
    const CARDINAL_WAIT = 10000, CARDINAL_EVERY = 60000;
    const INTRO_WAIT = 5000, INTRO_BETWEEN = GONE + 5000;
    function gap(from) {
      if (rhythm === 'cardinal') return CARDINAL_EVERY;
      if (rhythm === 'intro') {
        if (from === 0) return 1300;               // the burst of three
        if (from === 1) return 1300;
        return INTRO_BETWEEN;                      // then 5 s clear between each
      }
      if (rhythm === 'single') return BETWEEN;
      if (from === 2) return REST;                 // after the third
      if (from === 4) return LONG_REST;            // after the fifth
      if (rhythm === 'random') return 300 + Math.random() * 1800;
      if (from === 0) return 2500;                 // after the opening cardinal
      return Math.max(300, (ROUND[from + 1].at - ROUND[from].at) * 1000 / SPEED);
    }
    function schedule(wait) {
      clearTimeout(timer);
      timer = setTimeout(() => {
        const l = list();
        k = (k + 1) % l.length;
        notify(`I just spotted ${l[k].common}! ❤️‍🔥 ${l[k].points} points`);
        schedule(gap(k));
      }, wait);
    }
    const firstWait = () => rhythm === 'cardinal' ? CARDINAL_WAIT : rhythm === 'intro' ? INTRO_WAIT : OPENING;
    // The cardinal mode has no timer: the cardinal arrives each time "Powered
    // by BirdNET" flies into the footer credits, so the two stay in step for
    // as long as the page is open. (Without that credit, it falls back to a
    // timer: 10 s, then every 60 s.)
    const CUE = 'Powered by BirdNET';
    const credits = document.querySelector('footer .credit');
    const cued = () => rhythm === 'cardinal' && JSON.parse(credits.dataset.credits || '[]').includes(CUE);
    credits.addEventListener('credit', e => {
      if (e.detail === CUE && cued() && playing && !document.hidden) notify(`I just spotted ${CARDINAL.common}! ❤️‍🔥 ${CARDINAL.points} points`);
    });
    // Start the timer, unless the credits are doing the timing.
    const start = wait => { if (!cued()) schedule(wait); };
    start(firstWait());

    // Bell: pause or resume.
    const bell = document.querySelector('.test-notice');
    bell.addEventListener('click', () => {
      playing = !playing;
      bell.setAttribute('aria-pressed', String(playing));
      bell.title = playing ? 'Pause notifications' : 'Resume notifications';
      bell.setAttribute('aria-label', bell.title);
      if (playing) start(600); else clearTimeout(timer);
    });
    // Shuffle (test): the next mode, starting it afresh.
    const shuffle = document.querySelector('.rhythm');
    const showRhythm = () => {
      const next = MODES[(MODES.indexOf(rhythm) + 1) % MODES.length];
      shuffle.setAttribute('aria-pressed', String(rhythm !== 'cardinal'));
      shuffle.title = `Notifications: ${NAMES[rhythm]} (click for ${NAMES[next]})`;
      shuffle.setAttribute('aria-label', shuffle.title);
    };
    showRhythm();
    shuffle.addEventListener('click', () => {
      rhythm = MODES[(MODES.indexOf(rhythm) + 1) % MODES.length];
      showRhythm();
      k = -1;
      clearTimeout(timer);
      if (playing) start(rhythm === 'cardinal' ? CARDINAL_WAIT : rhythm === 'intro' ? INTRO_WAIT : GONE);
    });
```
