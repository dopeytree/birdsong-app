# Fix for dopeytree/birdsong: white paper behind some plates

Two places, one cause: a plate's white paper only melts into the page when a
multiply blend has the page's paper behind it in the same layer.

## The bug

Some creatures, bats especially, show on the collage as a white rectangle (the
plate's paper) instead of a figure on the page. The same plate in the detail
card looks right: its white paper melts into the page.

Example: Nyctalus noctula, drawn from the family plate
`Chalinolobus_gouldi-Cayley_2.jpg` (Wikimedia Commons, 453 × 453).

## Why

1. `makeFigure()` tries to cut each creature off its plate with `cutout()`.
2. `cutout()` reads the paper colour from the margins correctly (pure white
   here), then measures how much of the picture the figure covers. For this
   bat on its rock it is 61 %. Over 50 % it treats the plate as a painted
   scene and returns `null`:

   ```js
   if (tot / (W * H) > .5) return null;   // a full painted scene: leave it whole
   ```

3. With no cut-out, `makeFigure()` falls back to the whole `<img>`, and the
   collage draws it as it is, so the white paper shows.
4. The detail card never has this problem, because every plate there goes
   through `mix-blend-mode: multiply` (`#card figure img`). Multiplying
   turns white into whatever is behind it: the paper of the page.

Bats are hit most because they have no Fugleramme cut-outs. Their plates come
from Wikimedia Commons, and many of those are tight crops where the animal
and its perch run to the edges.

## The fix

Give whole plates on the collage the same multiply blend as the card.

The blend has to go on the figure (`.bird`), not on its `<img>`. Each `.bird`
is placed with a `transform`, and a transform makes the element its own
stacking context, so a blend on the `<img>` would only blend with the
figure's own transparent box and change nothing. `#plate` has no transform
and no `z-index`, so a blend on `.bird` reaches the page background (paper,
noise and vignette).

Three small changes to `index.html`, plus the card fix below (patch:
`upstream-whole-plate-blend.patch`, made against v0.42):

1. CSS, after the `.bird.ink>img` rule:
   ```css
   .bird.whole{mix-blend-mode:multiply}
   ```
2. `makeFigure()`: mark the fallback.
   ```js
   if (whole) { ...; return { el: whole.img, aspect: ..., plate: whole.plate, whole: true }; }
   ```
3. `ensureFigure()`: pass the mark on as a class.
   ```js
   b.className = "bird" + (have ? " in" : "") + (plate && plate.ready ? " ink" : "") + (fig.whole ? " whole" : "");
   ```

Cut-outs, Fugleramme figures and photographs are left alone; only the
whole-plate fallback changes. The madder "latest" dot on such a figure is
multiplied too, which darkens it very slightly.

Apply it with `git apply upstream-whole-plate-blend.patch` in the birdsong
repo. If the lines have moved, apply the three edits by hand.

## The same white in the detail card, when it scrolls

In a window too small for the card, the dialog scrolls
(`dialog{max-height:92vh;overflow:auto}`). WebKit draws a scrolled box's
contents in a separate layer from the box's own background, so the card
picture's `mix-blend-mode: multiply` has nothing behind it and the white
shows. In a large window the card doesn't scroll, so it looks right; that's
why it seemed to break only sometimes. (The page already works around this for
cut-outs, `#card figure img.ink`, "holds up when the card scrolls".)

The fix is to give the figure its own paper inside the scrolled layer. It's the
same colour as the dialog, so nothing else changes:

```css
#card figure{margin:0;background:var(--paper)}
```

## Things to check after applying

- A plate that now shows white (Nyctalus noctula, for example) melts into the
  page like the others, on hover too (the hover raises `z-index`, which is
  fine for a blend on the figure itself).
- Open that plate's card in a small window (so the card scrolls): its paper
  should still melt into the card.
- Anything that later gives `#plate` a `transform`, `filter`, `opacity < 1`
  or `isolation` will make it a stacking context and bring the white back.
  The app's pinch zoom does exactly that, and gives `#plate` a paper
  background while zoomed for this reason.

## In birdsong-app until then

The app never edits the page, so it carries the same fix from outside:

- `assets/app/plate-extras.js` adds the `whole` class to figures whose picture
  is an `<img>` from a plate that isn't a ready cut-out or a photograph.
- `lib/server/local_server.dart` injects `.bird.whole{mix-blend-mode:multiply}`
  and `#card figure{background:var(--paper)}`.

Once the page sets `whole` itself, the app's marking finds it already done.
After the next web sync it can be removed, and tool/web_contract.json loses
its two hooks for it.
