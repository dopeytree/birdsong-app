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

  /* ---- Tap "Index of species" to fold the list away (and back) ----------
     Folded, the heading shows a small ^ ; the collage takes the room and is
     laid out afresh either way. */
  if (heading) {
    heading.classList.add("bsIx");
    heading.setAttribute("role", "button");
    heading.setAttribute("tabindex", "0");
    var arrow = document.createElement("span");
    arrow.className = "bsIxArrow";
    arrow.textContent = "⌃";
    arrow.setAttribute("aria-hidden", "true");
    heading.appendChild(arrow);
    var setFolded = function (on) {
      document.body.classList.toggle("bs-noindex", on);
      heading.setAttribute("aria-expanded", String(!on));
      try { localStorage.setItem("birdplate.bsIndexFolded", on ? "1" : "0"); } catch (e) {}
    };
    var folded = false;
    try { folded = localStorage.getItem("birdplate.bsIndexFolded") === "1"; } catch (e) {}
    setFolded(folded);
    var toggle = function () {
      setFolded(!document.body.classList.contains("bs-noindex"));
      relayout();
    };
    heading.addEventListener("click", toggle);
    heading.addEventListener("keydown", function (e) {
      if (e.key === "Enter" || e.key === " ") { e.preventDefault(); toggle(); }
    });
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
