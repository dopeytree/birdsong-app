/* Birdsong app: extras for the plate page, served by the app beside it.
   The page itself is dopeytree/birdsong's, unchanged; tool/web_contract.json
   lists what this relies on in it. */
(function () {
  "use strict";
  var plate = document.getElementById("plate");
  var tip = document.getElementById("tip");
  var index = document.getElementById("index");
  var heading = index && index.previousElementSibling && index.previousElementSibling.tagName === "H2"
    ? index.previousElementSibling : null;
  function relayout() { dispatchEvent(new Event("resize")); }
  function tell(msg) {
    try { if (window.BirdsongHost) window.BirdsongHost.postMessage(msg); } catch (e) {}
  }

  /* ---- Tap "Index of species" to fold the list away (and back) ----------
     While the list shows, a small down arrow sits below it (tap to fold it
     away); once folded, an up arrow sits on the line above the heading (tap
     to bring it back). The collage takes the room and is laid out afresh. */
  if (heading) {
    heading.classList.add("bsIx");
    heading.setAttribute("role", "button");
    heading.setAttribute("tabindex", "0");
    var arrow = document.createElement("div");
    arrow.className = "bsIxArrow bsIxUp";
    arrow.textContent = "\u2303";
    arrow.setAttribute("aria-hidden", "true");
    heading.parentNode.insertBefore(arrow, heading);
    var down = document.createElement("div");
    down.className = "bsIxArrow bsIxDown";
    down.textContent = "\u2304";
    down.setAttribute("aria-hidden", "true");
    index.parentNode.insertBefore(down, index.nextSibling);
    var setFolded = function (on) {
      document.body.classList.toggle("bs-noindex", on);
      heading.setAttribute("aria-expanded", String(!on));
      try { localStorage.setItem("birdplate.bsIndexFolded", on ? "1" : "0"); } catch (e) {}
    };
    var folded = false;
    try { folded = localStorage.getItem("birdplate.bsIndexFolded") === "1"; } catch (e) {}
    setFolded(folded);
    var toggle = function () {
      if (document.body.classList.contains("no-plate")) return;   // the index alone: nothing to fold to
      setFolded(!document.body.classList.contains("bs-noindex"));
      relayout();
    };
    heading.addEventListener("click", toggle);
    arrow.addEventListener("click", toggle);
    down.addEventListener("click", toggle);
    heading.addEventListener("keydown", function (e) {
      if (e.key === "Enter" || e.key === " ") { e.preventDefault(); toggle(); }
    });

    /* ---- The session arrows, at the outer ends of the heading's rules -----
       The app says which way there are sessions to go (birdsongSteps) and
       steps when one is tapped. Where the heading is not on show (a mode
       without the index), the app draws its own pair instead. */
    var step = function (dir, glyph, label) {
      var b = document.createElement("span");
      b.className = "bsStep";
      b.textContent = glyph;
      b.setAttribute("role", "button");
      b.setAttribute("aria-label", label);
      b.addEventListener("click", function (e) {
        e.stopPropagation();          // not a fold of the index
        if (!b.classList.contains("off")) tell("step:" + dir);
      });
      return b;
    };
    var prev = step(-1, "\u2039", "Earlier session"), next = step(1, "\u203A", "Later session");
    heading.insertBefore(prev, heading.firstChild);
    heading.appendChild(next);
    window.birdsongSteps = function (canPrev, canNext) {
      prev.classList.toggle("off", !canPrev);
      next.classList.toggle("off", !canNext);
      document.body.classList.toggle("bs-steps", canPrev || canNext);
    };
    var shown = null;
    var report = function () {
      var on = heading.offsetParent !== null;
      if (on === shown) return;
      shown = on;
      tell(on ? "arrows:page" : "arrows:app");
    };
    addEventListener("resize", report);
    setInterval(report, 1000);
    report();
  } else {
    tell("arrows:app");
  }

  /* ---- Mode c: the index alone, centred on the window -----------------
     CSS centres it in the room under the title; a matching space below
     (as much as the title takes, if there is room) puts it in the middle of
     the whole window instead. A long index just scrolls as before. */
  var main = document.querySelector("main"), head = document.querySelector("header");
  if (main && head) {
    var lastPad = -1;
    var balance = function () {
      var only = document.body.classList.contains("no-plate") && !document.body.classList.contains("latest");
      var pad = 0;
      if (only) {
        var sec = main.querySelector("section");
        var bs = getComputedStyle(document.body);
        var room = innerHeight - parseFloat(bs.paddingTop) - parseFloat(bs.paddingBottom) - head.offsetHeight;
        pad = Math.max(0, Math.min(head.offsetHeight, room - (sec ? sec.offsetHeight : 0)));
      }
      pad = Math.round(pad);
      if (pad === lastPad) return;
      lastPad = pad;
      main.style.paddingBottom = pad ? pad + "px" : "";
    };
    addEventListener("resize", balance);
    setInterval(balance, 500);
    balance();
  }

  /* ---- Modes d and e: the one bird opens its card ---------------------
     The page's latest and top views show a single bird with no way into
     its details; a tap on the picture or the name opens the same card the
     collage does. The page's own names (species, latestOf, openDetail) are
     shared with this script. */
  var single = document.getElementById("latest");
  if (single) {
    var open = function () {
      try {
        if (typeof openDetail !== "function" || !latestOf) return;
        var sp = species.find(function (x) { return x.sci === latestOf; });
        if (sp) openDetail(sp);
      } catch (e) {}
    };
    // Listen here draws one session, so "since records began" means this session.
    var when = document.getElementById("latestWhen");
    if (when && /[?&]bs=listen\b/.test(location.search)) {
      var reword = function () {
        var t = when.textContent;
        if (t.indexOf("since records began") >= 0) when.textContent = t.replace("since records began", "this session");
      };
      new MutationObserver(reword).observe(when, { childList: true, characterData: true, subtree: true });
      reword();
    }
    ["latestFig", "latestName", "latestSci"].forEach(function (id) {
      var el = document.getElementById(id);
      if (!el) return;
      el.style.cursor = "pointer";
      el.addEventListener("click", open);
    });
  }

  /* ---- A plate that would not lift off its page --------------------------
     The page cuts each creature out of its plate, but gives up when the
     creature fills more than half the picture (a bat on its rock, say) and
     draws the whole plate instead, white paper and all. The detail card
     melts that paper into the page with a multiply blend; this gives the
     collage the same, on the figure itself (each figure is placed with a
     transform, which would keep a blend on its picture from reaching the
     page). Marks those figures "whole", the class the page will set itself
     once the fix is upstream; see docs/upstream-whole-plate-blend.md. */
  var markWhole = function () {
    if (typeof figures === "undefined" || !figures.forEach) return;
    figures.forEach(function (rec) {
      var b = rec.button, el = b && b.firstElementChild, p = rec.plate;
      var whole = !!(el && el.tagName === "IMG" && p && !p.ready && !p.photo && !rec.blank);
      if (b && b.classList.contains("whole") !== whole) b.classList.toggle("whole", whole);
    });
  };
  if (plate) {
    new MutationObserver(markWhole).observe(plate,
      { childList: true, subtree: true, attributes: true, attributeFilter: ["class"] });
    markWhole();
  }

  /* ---- Pinch to zoom the collage (touch screens) ------------------------
     Two fingers zoom about their midpoint, one finger pans once zoomed in,
     a double tap goes back. While a gesture runs, and just after, taps and
     the name label are held back, so a pinch never opens a creature's card;
     a plain tap still does. The page's own zoom is off: pinching elsewhere
     does nothing. */
  if (!plate || !("ontouchstart" in window)) return;
  var box = document.createElement("div");
  box.id = "bsZoomBox";
  plate.parentNode.insertBefore(box, plate);
  box.appendChild(plate);
  document.addEventListener("gesturestart", function (e) { e.preventDefault(); }, { passive: false });

  var z = 1, tx = 0, ty = 0, pinch = null, pan = null, quietUntil = 0, lastTap = 0;
  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }
  function apply() {
    var w = plate.offsetWidth, h = plate.offsetHeight;
    tx = clamp(tx, w * (1 - z), 0);
    ty = clamp(ty, h * (1 - z), 0);
    plate.style.transformOrigin = "0 0";
    plate.style.transform = z === 1 ? "" : "translate(" + tx + "px," + ty + "px) scale(" + z + ")";
    document.body.classList.toggle("bs-zoomed", z > 1);
  }
  function reset() { z = 1; tx = 0; ty = 0; apply(); }
  function quiet() {
    quietUntil = Date.now() + 450;
    if (tip) tip.classList.remove("on");
  }
  function local(t) {
    var r = plate.getBoundingClientRect();   // includes the current transform
    return { x: (t.clientX - r.left) / z, y: (t.clientY - r.top) / z };
  }

  box.addEventListener("touchstart", function (e) {
    if (e.touches.length === 2) {
      e.preventDefault();
      var a = e.touches[0], b = e.touches[1];
      var mid = { clientX: (a.clientX + b.clientX) / 2, clientY: (a.clientY + b.clientY) / 2 };
      pinch = { d: Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY), z: z, at: local(mid) };
      pan = null;
      quiet();
    } else if (e.touches.length === 1 && z > 1) {
      var t = e.touches[0];
      pan = { x: t.clientX, y: t.clientY, tx: tx, ty: ty, moved: false };
    }
  }, { passive: false });

  box.addEventListener("touchmove", function (e) {
    if (pinch && e.touches.length === 2) {
      e.preventDefault();
      var a = e.touches[0], b = e.touches[1];
      z = clamp(pinch.z * Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY) / pinch.d, 1, 4);
      var r = box.getBoundingClientRect();
      var mx = (a.clientX + b.clientX) / 2 - r.left - plate.offsetLeft;
      var my = (a.clientY + b.clientY) / 2 - r.top - plate.offsetTop;
      // Keep the point that was under the fingers under them.
      tx = mx - pinch.at.x * z;
      ty = my - pinch.at.y * z;
      apply();
      quiet();
    } else if (pan && e.touches.length === 1) {
      var t = e.touches[0], dx = t.clientX - pan.x, dy = t.clientY - pan.y;
      if (!pan.moved && Math.hypot(dx, dy) < 8) return;
      e.preventDefault();
      pan.moved = true;
      tx = pan.tx + dx;
      ty = pan.ty + dy;
      apply();
      quiet();
    }
  }, { passive: false });

  box.addEventListener("touchend", function (e) {
    if (e.touches.length < 2) pinch = null;
    if (e.touches.length === 0) {
      if (z < 1.05) reset();
      var now = Date.now();
      if (z > 1 && !(pan && pan.moved) && now - lastTap < 300) { reset(); quiet(); }
      lastTap = now;
      pan = null;
    }
  });

  // Hold back the tap that ends a pinch or a pan.
  box.addEventListener("click", function (e) {
    if (Date.now() < quietUntil) { e.stopPropagation(); e.preventDefault(); }
  }, true);
  ["pointerover", "pointerenter", "mouseover"].forEach(function (k) {
    box.addEventListener(k, function (e) {
      if (Date.now() < quietUntil || pinch) e.stopPropagation();
    }, true);
  });

  // The collage is laid out afresh on resize; start that view unzoomed.
  addEventListener("resize", reset);
})();
