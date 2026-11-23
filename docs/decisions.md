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
  ("Birdsongs.ai / Aye lovely a Northern Cardinal! ❤️‍🔥 +50points"), with its
  song (`site/public/sounds/northern_cardinal.mp3`, 4.4 s), and only when the
  visitor does something: taps "Tap to Enter", presses the bell (top right),
  clicks Coming Soon, or stirs the text (pointer over or click; then a 10 s
  rest). Nothing arrives by itself: arriving with the "Powered by BirdNET"
  credit (song 2 s ahead) was tried and dropped. Browsers allow sound only
  after a click, tap or key, which entering gives. A banner leaves after ~5 s
  or when tapped. Points are a stand-in. Other rhythms (a run through walk
  #20's 42 species, a round of five, random) are archived in
  `docs/splash-notification-modes.md`; the walk's data stays in
  `site/src/data/walk-20.json` (made by `tool/export_site_walk.py`). The icon
  stays the app's: iOS doesn't allow a per-notification icon.
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
- **Licence (Ed, 23 Nov 2026):** all rights reserved, personal use only: a
  short licence of our own in `LICENSE` (personal, noncommercial use and
  changes for yourself; no sharing beyond linking; no commercial use; no use
  by any organisation; anything else by Ed's written permission). Tried and
  dropped the same day: CC BY-NC 4.0 (CC advise against it for code) and
  PolyForm Noncommercial 1.0.0 (it lets charities, schools and public bodies
  use it). Earlier copies keep MIT. Others' work keeps its own licence; the
  README lists them under "Credits and licences".
- **Splash murmuration's reach (Ed, Nov 2026):** the text, Coming Soon (its
  letters, and its outline swaying as one) and the credits (their letters,
  and the side rules). The round buttons and icons, the pill, the device
  pictures, the lion and the notifications stay still: murmuring them was
  tried and dropped, as was scattering icon strokes. Only the text brings the
  notification.
- **Splash gate (Ed, Nov 2026):** the site opens under a veil, the page faded
  (98% of the page colour, no blur) behind a "Tap to Enter" pill styled as
  Coming Soon (italic, madder, thin outline).
  A click, tap, Enter or Space lifts it with a fade; that tap also lets the page
  play sound, brings the cardinal (song and notification) at once, and starts
  the credits.
- **Gate video (on trial, Ed, Nov 2026):** the 22 s preview
  (`site/public/media/coming-soon.mp4`, black bands cropped) plays once
  above Tap to Enter. It tries to play with sound; browsers mostly refuse
  before a tap, so it plays silently with a "Sound on" label (sound on, from
  where it is). It has the browser's controls (pause, scrub, volume); clicks
  on it never enter. Entering stops it.
- **Gate texture (on trial, Ed, Nov 2026):** the veil carries the Northern
  Cardinal's own spectrogram (made from its song with ffmpeg, the 1.5–7.5 kHz
  band, cleaned; `site/public/media/cardinal-spectrogram.png`) along the
  bottom in the ink colour, faint, plus fine grain. `?veil=song`, `?veil=grain`
  or `?veil=both` (default) to compare.
- **Model updates (Ed, Nov 2026):** the app looks for newer builds of the
  models you have installed, once a day: on opening, on coming back to it,
  and every 3 h while open (1 h wait after a failed try). A slim paper strip
  along the top of the screen, not a card or a system notification: "A newer
  {model} is ready ({version}, {MB} MB)." Download (madder) and Skip, set
  well apart (Ed). It sits outside the share capture. Settings →
  Models shows "Newer build ready" and Check now. Downloads are checked by
  sha256; the old files go once the new ones check out.
- **Page spectrogram (Ed, Nov 2026):** the cardinal's spectrogram from the
  veil also lies faint along the foot of the main page, fixed behind
  everything, in the ink colour (7% on black, 9% on white).
- **iOS and Android buttons (Ed, Nov 2026):** either side of Coming Soon, on one line, outlined like
  it but in the quote's colour, each with its logo (Apple, Android; from
  Simple Icons). Plain-word versions were tried and dropped. Labels only, no
  links yet. Apple's rules don't allow its logo on its own in others'
  marketing; revisit (or use the official badge) at launch.
- **Text links (Ed, Nov 2026):** "Index of Species" opens the sideways iPad
  (its index) full size; "walk" opens the sideways iPad playing a walk (the
  map, then a bird's card): `site/public/media/walk.mp4`, 8 s, silent,
  looping, 2.7 MB, made from Ed's screen recording. These clicks don't also
  bring the cardinal.
- **Walk map marks (Ed, Nov 2026):** each bird is a small ❤️ (larger for a
  species' first sighting; was a madder hand-drawn ✕, then ❤️‍🔥), the start a hand-drawn
  + and the finish a ✕, both in ink on a paper halo. A listening station keeps
  its ring. (`walk_map.dart`: `_birds`, `_ends`, `_StartFinishPainter`.)
- **Map labels (Ed, Nov 2026):** a place's label takes the app's dialog look
  (deeper paper, rounded, soft shadow, no ring); tapping the same thing again,
  or the label, closes it. Bird names on the map are in ink, apart from the red
  hearts.
- **Corner icons (Ed, Nov 2026):** the bell (top right) and sun/moon (bottom
  right) are filled icons on their own, no circle round them.
- **Heartbeat (Ed, Nov 2026):** a click on "Time" (in "Aye Old as Time.")
  sends ripples out through the murmuring page from the word, in a heartbeat:
  lub-dub, four beats at about 70 a minute. It doesn't also bring the cardinal.
