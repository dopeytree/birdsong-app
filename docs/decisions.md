# Ed's decisions

What Ed approved and rejected, so it isn't tried twice. Newest first. Add
to this whenever he gives a verdict; use his words where you have them.

## The standing rule

Vintage natural history: paper, sepia ink, serif (IM Fell English),
engraved plates. "Vintage illustrations, not modern cartoon." Show an idea
or a small test before building it.

## 22 Nov 2026

- **Blackletter names and a symbol for every kind of ancient site: no.**
  "Put the font back, get rid of the icon. It's changed the font on
  irrelevant things." What he wants instead: "a slight icon for standing
  stones", and a drawing only for the special ones: Stonehenge, and
  Calanais on Lewis ("the only other big one like that that I know of
  deserving its own illustration"). Built that way; "ok nice".
- **Ancient woods:** his idea: "darker green than the normal woods,
  something subtle to make it more obvious it's ancient".
- **Session names:** keep the town and add where the walk was: "Ashcott –
  RSPB Ham Wall", "Ashcott – Loxley Woods".
- **Full-screen map:** no "Passed on the way" under it.
- **Map timing readout:** a switch, off by default.
- **Flutter plate as the default:** yes, with the web plate kept as a
  fallback and the options moved into Display.
- **Companion server:** parked.
- **Next pieces of the refactor:** "check with me first".
- **Cost:** development was costing too much (about £200 in 48 hours). Use
  cheaper models for routine work: see `cost.md`.

## Earlier

- **Wildlife silhouettes on the map: no.** Too modern; they also popped in
  and jumped on zoom. Real engravings (Bewick) are the direction, shown to
  Ed before building.
- **The refactor is a faithful port:** "this doesn't mean you are removing
  functions or design choices."
- **RSPB data:** not used without their permission.
- **No iPhone builds** until the app is complete.
- **Astro splash page:** Ed chose Astro over plain HTML and Flutter web.
  "Flutter web too slow to load and poor for search." Built with the app's
  palette (paper #EEE5CE, ink, sepia, madder) and IM Fell English fonts.
  Shows the app in a CSS-drawn iPhone frame. The iPhone | iPad pill (styled
  like the app's mic pill) switches device; the iPad shows sideways.
  Clicking the screen opens it full size in a popup over the page faded to
  black at 90%. The upright iPad shot is hidden for now (commented out in
  the shots list). Shots live in `site/public/shots/`.
- **Splash page extras (Ed, Nov 2026):** murmuration text effect on the
  tagline, title and paragraphs (`site/src/scripts/text-fx.js`; letters
  scatter from the pointer and settle; ink colour only; off with Reduce
  Motion). Chosen over "ink in water", still there with `?fx=ink`. An
  iPhone-style notification slides down 1.2 s after load and stays until clicked:
  "Birdsongs.ai / I just spotted Northern Cardinal! ❤️‍🔥 50 points". iOS look (frosted
  glass, system font); its icon is the
  cardinal from the app's loading screen (`assets/app/cardinal.png`) on paper.
- **Splash page background (Ed, Nov 2026):** the page is a darker paper,
  #C8B68C (`--page`), so the app's lighter screens stand out. Chosen over
  #E3D7B8, #D6C6A0 and #B8A479.
- **Splash page modes (Ed, Nov 2026):** black (#0E0D0C; ink and paper swap,
  the app's screens stay as they are) and white. The page follows the
  device's light or dark setting, live, until the visitor picks; the round
  button top right (Lucide sun and moon, ISC) switches and remembers it.
  `?bg=white` / `?bg=black` picks one. The paper mode (#C8B68C) was dropped.
- **Splash page credits (Ed, Nov 2026):** the footer cycles 16 credits, Nederlandsche Vogelen first
  (list in `index.astro`, `credits`), each flocking in letter by letter, then
  fading out (`site/src/scripts/credits.js`). Left out: the model
  gallery (tphakala) and the MIT code licence. Screen readers get the full list.
- **Notifications name the full species (Ed, Nov 2026):** e.g. "Northern
  Cardinal", not "cardinal", matching the species index. An iPhone banner
  shows about four lines (~160 characters), so even the longest names fit.
- **Splash notifications (Ed, Nov 2026):** only the Northern Cardinal
  ("Birdsongs.ai / Aye lovely a Northern Cardinal! ❤️‍🔥 +50points"), each
  time "Powered by BirdNET" flies into the footer credits (about 11 s in,
  then once a round of the credits). No timer, so they stay in step. The
  bell, top right, sends one straight away; light/dark is bottom right. A
  banner leaves after ~5 s or when tapped. Points are a stand-in. Other
  rhythms (a run through walk #20's 42 species, a round of five, random) were
  tried and archived in `docs/splash-notification-modes.md`; the walk's data
  stays in `site/src/data/walk-20.json` (made by `tool/export_site_walk.py`).
  The icon stays the app's: iOS doesn't allow a per-notification icon.
- **Splash "Coming soon" (Ed, Nov 2026):** the App Store and Google Play
  badges were tried and removed (with their trademark lines in the credits).
  "Coming Soon" sits in a thin rounded outline in the pill's red-orange (madder, #8C3B2A, both modes), a label
  rather than a button. The badges (official, from developer.apple.com and
  play.google.com) can come back at launch, linking to the listings.
- **Splash page on phones and iPads (Ed, Nov 2026):** two layouts only.
  Desktop, over 820px wide: text left, device right. Mobile, 820px and under
  (phones, upright iPads, narrow windows): one column with the tagline and
  title, then the device at most half the screen height, then the paragraphs
  and Coming Soon (centred between the quote and the credits), credits at
  the foot of the screen; smaller text and buttons. Held sideways, the device
  gets about 82% of the screen height. The "Tap the screen to see it full
  size" hint is hidden on every screen.
  On touch screens the first shot is the opposite shape to the screen: held
  upright, the sideways iPad; held sideways, the upright iPhone. Turning the
  device switches it, until the visitor uses the pill. Desktops open on the
  iPhone.
- **Splash page maker's mark (Ed, Nov 2026):** Ed's animated amber lion from
  ed-stone.co.uk, bottom left (70px; 56px on mobile), linking to his site.
  Copied into the site at 140px wide (`site/public/ed-stone-lion.gif`).
- **Licence (Ed, 23 Nov 2026):** the project moved from MIT to the PolyForm
  Noncommercial License 1.0.0 (briefly CC BY-NC 4.0, dropped as CC advises
  against its licences for code), with no commercial use spelt out in
  `LICENSE` and the README. Earlier copies
  keep MIT. Others' work keeps its own licence; the README lists them under
  "Credits and licences".
