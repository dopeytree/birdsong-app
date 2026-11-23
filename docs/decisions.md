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
  black at 70%. The upright iPad shot is hidden for now (commented out in
  the shots list). Shots live in `site/public/shots/`.
- **Splash page extras (Ed, Nov 2026):** murmuration text effect on the
  tagline, title and paragraphs (`site/src/scripts/text-fx.js`; letters
  scatter from the pointer and settle; ink colour only; off with Reduce
  Motion). Chosen over "ink in water", still there with `?fx=ink`. An
  iPhone-style notification slides down 1.2 s after load and stays until clicked:
  "Birdsongs / I just spotted Kingfisher! :D ❤️‍🔥 50 points". iOS look (frosted
  glass, system font); its icon is the
  cardinal from the app's loading screen (`assets/app/cardinal.png`) on paper.
