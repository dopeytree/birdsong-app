/* Birdsong app: map mode for the plate page.
   The collage is swapped for a map of the walk: a dotted trail from start to
   end, and a ✕ where each species was first heard (or every call). The title,
   date, place, totals and the Index of species stay as they are; tapping a ✕
   opens the plate's own card for that bird.

   Written so it can move into dopeytree/birdsong later: everything comes in
   through window.birdsongMap*() hooks and one feature-detected feed,
   /app/walk.json (lib/server/local_api.dart walk()), which a page without the
   app simply doesn't have. tool/web_contract.json lists what this relies on
   in the page (#plate, #caption, #tip, openDetail, species, measureOthers).

   Hooks the app calls (lib/ui/plate_view.dart):
     birdsongMap(true|false)         show the map in place of the collage
     birdsongMapOptions({birds, extras})
         birds:  "first" (default) one ✕ per species where first heard,
                 "all"   a ✕ for every detection
         extras: true to add peaks' neighbours: listed buildings, scheduled
                 monuments, protected nature sites and Wikipedia places, and
                 a "Passed on the way" list. Off by default: these send the
                 walk's area to Historic England, Natural England and
                 Wikipedia.
     birdsongMapRefresh()            fetch the walk again (new birds, trail)

   The map itself (MapLibre, d3 for contours) loads from a CDN the first time
   map mode opens; tiles come from OpenFreeMap and elevation from the Mapzen
   terrain tiles on AWS, so the map needs a connection. */
(function () {
  "use strict";
  var plateEl = document.getElementById("plate");
  if (!plateEl) return;
  var caption = document.getElementById("caption");
  var tipEl = document.getElementById("tip");

  var MAPLIBRE = "https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl";
  var D3 = "https://cdnjs.cloudflare.com/ajax/libs/d3/7.9.0/d3.min.js";
  var TILES = "https://tiles.openfreemap.org/planet";
  var GLYPHS = "https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf";
  var DEM = "https://elevation-tiles-prod.s3.amazonaws.com/terrarium/";
  var FONT = ["Noto Sans Regular"], FONT_IT = ["Noto Sans Italic"];

  function get(k, d) { try { var v = localStorage.getItem("birdplate.bsMap." + k); return v == null ? d : JSON.parse(v); } catch (e) { return d; } }
  function put(k, v) { try { localStorage.setItem("birdplate.bsMap." + k, JSON.stringify(v)); } catch (e) {} }
  function esc(s) { return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; }); }
  function cssVar(n, d) { var v = getComputedStyle(document.documentElement).getPropertyValue(n).trim(); return v || d; }

  var S = { on: false, birds: get("birds", "first"), extras: get("extras", false) };
  var C = {};          // the page's palette, read once the page's CSS is in
  var host, canvas, note, map, ready = false, libs = null, walk = null, walkKey = "", fitted = false;
  var captionWas = null;

  /* ---------- styles ---------- */
  var style = document.createElement("style");
  style.textContent =
    "#bsMap{position:absolute;inset:0;z-index:50;display:none;background:var(--paper)}" +
    "body.bs-map #bsMap{display:block}" +
    "body.bs-map #plate>.bird,body.bs-map #plate>#status{visibility:hidden}" +
    // collage switched off in Display: the map still takes its place
    "body.bs-map.no-plate #plate{display:block}" +
    "#bsMapCanvas{position:absolute;inset:0}" +
    "#bsMapNote{position:absolute;left:.5rem;bottom:.4rem;right:3rem;z-index:2;font-style:italic;font-size:.8rem;" +
    "color:var(--sepia);pointer-events:none;text-shadow:0 0 3px var(--paper),0 0 3px var(--paper)}" +
    "#bsMapNote:empty{display:none}" +
    "#bsMap .maplibregl-ctrl-attrib{background:rgba(238,229,206,.85)!important;font-size:10px;font-family:var(--serif)}" +
    "#bsMap .maplibregl-ctrl-group{background:var(--paper);box-shadow:none;border:1px solid var(--paper-deep)}" +
    "#bsPassed{display:none}body.bs-map.bs-extras #bsPassed{display:block}" +
    "#bsPassed ol{list-style:none;padding:0;margin:0;columns:16rem auto;column-gap:2rem}" +
    "#bsPassed li{break-inside:avoid;cursor:pointer;padding:.1rem 0}" +
    "#bsPassed li:hover .n{color:var(--madder)}" +
    "#bsPassed .k{color:var(--sepia);font-style:italic;font-size:.85em}" +
    "#bsPassed .d{color:var(--sepia);font-size:.8em;margin-left:.3em}" +
    "#bsPassed .st{color:var(--sepia);font-style:italic;font-size:.8em}";
  document.head.appendChild(style);

  /* ---------- the hooks ---------- */
  window.birdsongMap = function (on) {
    on = !!on;
    if (on === S.on) { if (on) refreshSoon(0); return; }
    S.on = on;
    document.body.classList.toggle("bs-map", on);
    if (caption) {
      if (on) { captionWas = captionWas == null ? caption.textContent : captionWas; caption.textContent = captionText(); }
      else if (captionWas != null) caption.textContent = captionWas;
    }
    if (on) { build(); sizePlate(); }
    dispatchEvent(new Event("resize"));   // the page lays out afresh; zoom resets
    if (on) start();
  };
  window.birdsongMapOptions = function (o) {
    o = o || {};
    var birdsChanged = false, extrasChanged = false;
    if (o.birds && o.birds !== S.birds) { S.birds = o.birds === "all" ? "all" : "first"; put("birds", S.birds); birdsChanged = true; }
    if (o.extras != null && !!o.extras !== S.extras) { S.extras = !!o.extras; put("extras", S.extras); extrasChanged = true; }
    document.body.classList.toggle("bs-extras", S.extras);
    if (caption && S.on) caption.textContent = captionText();
    if (!ready) return;
    if (birdsChanged) drawWalk();
    if (extrasChanged) { showExtras(); if (S.extras) loadPlaces(true); }
  };
  window.birdsongMapRefresh = function () { if (S.on) refreshSoon(1500); };
  document.body.classList.toggle("bs-extras", S.extras);

  function captionText() {
    return S.birds === "all"
      ? "The way you walked, with a cross wherever a bird was heard. Select one to see its plate and its hours."
      : "The way you walked, with a cross where each bird was first heard. Select one to see its plate and its hours.";
  }

  /* ---------- the box on the plate ---------- */
  function build() {
    if (host) return;
    host = document.createElement("div"); host.id = "bsMap";
    canvas = document.createElement("div"); canvas.id = "bsMapCanvas";
    note = document.createElement("div"); note.id = "bsMapNote";
    host.append(canvas, note);
    plateEl.appendChild(host);
    // The map takes its own pinches and drags: keep them from the collage's
    // pinch zoom (plate-extras.js listens on a box around #plate).
    ["touchstart", "touchmove", "touchend", "wheel"].forEach(function (k) {
      host.addEventListener(k, function (e) { e.stopPropagation(); }, { passive: true });
    });
    // "Passed on the way", under the Index of species (extras only).
    var sec = document.createElement("section"); sec.id = "bsPassed";
    sec.innerHTML = "<h2>Passed on the way</h2><ol></ol><p class='st'></p>";
    var ix = document.querySelector("main section");
    if (ix) ix.after(sec); else document.querySelector("main").appendChild(sec);
  }

  // With the collage switched off in Display the page gives #plate no
  // height of its own, so the map sizes it as the collage would.
  function sizePlate() {
    if (!S.on || !document.body.classList.contains("no-plate")) return;
    var h = innerHeight;
    try { h = innerHeight - measureOthers(); } catch (e) {}
    plateEl.style.height = Math.max(260, h) + "px";
  }
  addEventListener("resize", function () {
    if (!S.on) return;
    sizePlate();
    if (map) setTimeout(function () { map.resize(); }, 60);
  });

  function say(t) { if (note) note.textContent = t || ""; }

  /* ---------- loading MapLibre and d3, once ---------- */
  function script(src) {
    return new Promise(function (ok, no) {
      var s = document.createElement("script"); s.src = src; s.onload = ok; s.onerror = function () { no(new Error(src)); };
      document.head.appendChild(s);
    });
  }
  function loadLibs() {
    if (!libs) {
      var l = document.createElement("link"); l.rel = "stylesheet"; l.href = MAPLIBRE + ".css"; document.head.appendChild(l);
      libs = Promise.all([window.maplibregl ? null : script(MAPLIBRE + ".js"), window.d3 ? null : script(D3)])
        .catch(function (e) { libs = null; throw e; });
    }
    return libs;
  }

  function start() {
    if (map) { setTimeout(function () { map.resize(); }, 60); refreshSoon(0); return; }
    say("Drawing the map…");
    loadLibs().then(makeMap).catch(function () {
      say("The map needs an internet connection the first time it opens.");
    });
  }

  /* ---------- the map ---------- */
  var EMPTY = { type: "FeatureCollection", features: [] };
  var NATURE_LAYERS = ["grass", "wetland", "wetland-reeds", "wood-bleed", "wood", "wood-trees", "park", "water-bleed", "water", "waterway"];
  var EXTRA_LAYERS = ["nature-fill", "nature-edge", "nature-label", "sched-fill", "sched-edge", "sched-label", "listed", "wiki"];

  function mapStyle() {
    var paper = C.paper, sepia = C.sepia, ink = C.ink, madder = C.madder;
    return {
      version: 8,
      glyphs: GLYPHS,
      sources: {
        omt: { type: "vector", url: TILES },
        contours: { type: "geojson", data: EMPTY },
        "nature-sites": { type: "geojson", data: EMPTY },
        "he-sched": { type: "geojson", data: EMPTY },
        "he-listed": { type: "geojson", data: EMPTY },
        wiki: { type: "geojson", data: EMPTY },
        trail: { type: "geojson", data: EMPTY },
        ends: { type: "geojson", data: EMPTY },
        birds: { type: "geojson", data: EMPTY }
      },
      layers: [
        { id: "paper", type: "background", paint: { "background-color": paper } },
        // nature: washes, little trees, reeds, water
        { id: "grass", type: "fill", source: "omt", "source-layer": "landcover", filter: ["in", ["get", "class"], ["literal", ["grass", "farmland"]]], paint: { "fill-color": "#e3dcbc", "fill-opacity": 0.55 } },
        { id: "wetland", type: "fill", source: "omt", "source-layer": "landcover", filter: ["==", ["get", "class"], "wetland"], paint: { "fill-color": "#d6dcc6", "fill-opacity": 0.7 } },
        { id: "wetland-reeds", type: "fill", source: "omt", "source-layer": "landcover", filter: ["==", ["get", "class"], "wetland"], paint: { "fill-pattern": "reeds", "fill-opacity": 0.8 } },
        { id: "wood-bleed", type: "line", source: "omt", "source-layer": "landcover", filter: ["==", ["get", "class"], "wood"], paint: { "line-color": "#a9b98a", "line-width": 6, "line-blur": 6, "line-opacity": 0.45 } },
        { id: "wood", type: "fill", source: "omt", "source-layer": "landcover", filter: ["==", ["get", "class"], "wood"], paint: { "fill-color": "#c2cc9f", "fill-opacity": 0.75 } },
        { id: "wood-trees", type: "fill", source: "omt", "source-layer": "landcover", filter: ["==", ["get", "class"], "wood"], paint: { "fill-pattern": "trees" } },
        { id: "park", type: "fill", source: "omt", "source-layer": "park", paint: { "fill-color": "#d3d8b3", "fill-opacity": 0.5 } },
        { id: "water-bleed", type: "line", source: "omt", "source-layer": "water", paint: { "line-color": "#8fb0b0", "line-width": 7, "line-blur": 7, "line-opacity": 0.4 } },
        { id: "water", type: "fill", source: "omt", "source-layer": "water", paint: { "fill-color": "#bccfca", "fill-opacity": 0.9 } },
        { id: "waterway", type: "line", source: "omt", "source-layer": "waterway", layout: { "line-cap": "round", "line-join": "round" },
          paint: { "line-color": "#7fa3a4", "line-opacity": 0.85,
            // zoom must be the outermost expression
            "line-width": ["interpolate", ["linear"], ["zoom"], 11, ["match", ["get", "class"], "river", 1.2, 0.4], 16, ["match", ["get", "class"], "river", 3.5, 1.3]] } },
        // people: quiet, in the paper's own browns
        { id: "buildings", type: "fill", source: "omt", "source-layer": "building", minzoom: 13.5,
          paint: { "fill-color": "#e0d3b6", "fill-outline-color": "#cbbb9b", "fill-opacity": ["interpolate", ["linear"], ["zoom"], 13.5, 0, 15, 0.85] } },
        { id: "rail", type: "line", source: "omt", "source-layer": "transportation", minzoom: 11, filter: ["==", ["get", "class"], "rail"],
          paint: { "line-color": "#b9a888", "line-width": 1, "line-dasharray": [5, 3], "line-opacity": 0.8 } },
        { id: "roads", type: "line", source: "omt", "source-layer": "transportation",
          filter: ["in", ["get", "class"], ["literal", ["motorway", "trunk", "primary", "secondary", "tertiary", "minor", "service"]]],
          layout: { "line-cap": "round", "line-join": "round" },
          paint: {
            "line-color": ["match", ["get", "class"], ["motorway", "trunk", "primary"], "#c9b28b", ["secondary", "tertiary"], "#d1bd9a", "#d9c9ab"],
            "line-width": ["interpolate", ["linear"], ["zoom"],
              10, ["match", ["get", "class"], ["motorway", "trunk", "primary"], 0.8, ["secondary", "tertiary"], 0.5, 0],
              13, ["match", ["get", "class"], ["motorway", "trunk", "primary"], 1.8, ["secondary", "tertiary"], 1.2, "service", 0.3, 0.6],
              16, ["match", ["get", "class"], ["motorway", "trunk", "primary"], 4, ["secondary", "tertiary"], 3, "service", 1, 2]],
            "line-opacity": 0.9 } },
        { id: "tracks", type: "line", source: "omt", "source-layer": "transportation", minzoom: 12.5, filter: ["==", ["get", "class"], "track"],
          layout: { "line-cap": "round" }, paint: { "line-color": "#bba580", "line-width": ["interpolate", ["linear"], ["zoom"], 12.5, 0.6, 16, 1.3], "line-dasharray": [3, 2] } },
        { id: "paths", type: "line", source: "omt", "source-layer": "transportation", minzoom: 13, filter: ["==", ["get", "class"], "path"],
          layout: { "line-cap": "round" }, paint: { "line-color": "#b09870", "line-width": ["interpolate", ["linear"], ["zoom"], 13, 0.6, 16, 1.2], "line-dasharray": [0.8, 2] } },
        // extras (off unless asked for): protected nature sites, scheduled monuments
        { id: "nature-fill", type: "fill", source: "nature-sites", paint: { "fill-color": "#7f9a6a", "fill-opacity": 0.07 } },
        { id: "nature-edge", type: "line", source: "nature-sites", layout: { "line-join": "round" }, paint: { "line-color": "#5f7d4c", "line-opacity": 0.7, "line-width": 1.2, "line-dasharray": [3, 2] } },
        { id: "nature-label", type: "symbol", source: "nature-sites",
          layout: { "symbol-placement": "line", "text-field": ["get", "label"], "text-font": FONT_IT, "text-size": 10, "symbol-spacing": 420, "text-max-angle": 30, "text-offset": [0, -0.8] },
          paint: { "text-color": "#5f7d4c", "text-halo-color": paper, "text-halo-width": 1.5 } },
        { id: "sched-fill", type: "fill", source: "he-sched", paint: { "fill-pattern": "hatch", "fill-opacity": 0.9 } },
        { id: "sched-edge", type: "line", source: "he-sched", paint: { "line-color": "#8a5a3a", "line-width": 0.9, "line-dasharray": [1, 1.5] } },
        // contours, traced here from the elevation tiles (see contours())
        { id: "contour-minor", type: "line", source: "contours", filter: ["==", ["get", "major"], 0], layout: { "line-join": "round" },
          paint: { "line-color": "#9b7d5a", "line-opacity": 0.5, "line-width": ["interpolate", ["linear"], ["zoom"], 11, 0.4, 16, 0.9] } },
        { id: "contour-major", type: "line", source: "contours", filter: ["==", ["get", "major"], 1], layout: { "line-join": "round" },
          paint: { "line-color": sepia, "line-opacity": 0.8, "line-width": ["interpolate", ["linear"], ["zoom"], 11, 0.9, 16, 1.8] } },
        { id: "contour-label", type: "symbol", source: "contours", filter: ["==", ["get", "major"], 1],
          layout: { "symbol-placement": "line", "text-field": ["concat", ["to-string", ["get", "ele"]], " m"], "text-font": FONT, "text-size": 10, "text-max-angle": 25, "symbol-spacing": 300 },
          paint: { "text-color": sepia, "text-halo-color": paper, "text-halo-width": 1.6 } },
        { id: "place-label", type: "symbol", source: "omt", "source-layer": "place", filter: ["in", ["get", "class"], ["literal", ["town", "village", "hamlet"]]],
          layout: { "text-field": ["get", "name"], "text-font": FONT_IT, "text-size": ["match", ["get", "class"], "town", 15, 12], "text-letter-spacing": 0.14, "text-transform": "uppercase" },
          paint: { "text-color": sepia, "text-halo-color": paper, "text-halo-width": 2 } },
        // peaks come with the base tiles, so they are always shown
        { id: "peaks", type: "symbol", source: "omt", "source-layer": "mountain_peak", filter: ["all", ["==", ["get", "class"], "peak"], ["has", "name"]],
          layout: { "icon-image": "peak", "icon-allow-overlap": true, "icon-anchor": "bottom",
            "text-field": ["case", ["has", "ele"], ["concat", ["get", "name"], "\n", ["to-string", ["get", "ele"]], " m"], ["get", "name"]],
            "text-font": FONT_IT, "text-size": 11, "text-anchor": "top", "text-offset": [0, 0.3], "text-optional": true },
          paint: { "text-color": ink, "text-halo-color": paper, "text-halo-width": 1.8 } },
        { id: "sched-label", type: "symbol", source: "he-sched", minzoom: 13.5,
          layout: { "text-field": ["get", "label"], "text-font": FONT_IT, "text-size": 10, "text-max-width": 9 },
          paint: { "text-color": "#8a5a3a", "text-halo-color": paper, "text-halo-width": 1.5 } },
        { id: "listed", type: "symbol", source: "he-listed",
          layout: { "icon-image": "bldg", "icon-allow-overlap": true, "icon-size": ["case", ["==", ["get", "Grade"], "I"], 1.15, 0.9],
            "text-field": ["step", ["zoom"], "", 14.5, ["get", "label"]], "text-font": FONT_IT, "text-size": 10, "text-anchor": "left", "text-offset": [0.9, 0], "text-max-width": 9, "text-optional": true },
          paint: { "text-color": "#6b4a33", "text-halo-color": paper, "text-halo-width": 1.5 } },
        { id: "wiki", type: "symbol", source: "wiki",
          layout: { "icon-image": "wiki", "icon-allow-overlap": true,
            "text-field": ["step", ["zoom"], "", 14, ["get", "title"]], "text-font": FONT_IT, "text-size": 10, "text-anchor": "left", "text-offset": [0.8, 0], "text-max-width": 9, "text-optional": true },
          paint: { "text-color": "#3d5566", "text-halo-color": paper, "text-halo-width": 1.5 } },
        // the walk
        { id: "trail-halo", type: "line", source: "trail", layout: { "line-cap": "round", "line-join": "round" }, paint: { "line-color": paper, "line-width": 7, "line-opacity": 0.8 } },
        { id: "trail", type: "line", source: "trail", layout: { "line-cap": "round", "line-join": "round" }, paint: { "line-color": ink, "line-width": 3, "line-dasharray": [0.01, 2.2] } },
        { id: "ends", type: "symbol", source: "ends",
          layout: { "icon-image": ["get", "icon"], "icon-allow-overlap": true, "text-field": ["get", "label"], "text-font": FONT_IT, "text-size": 11,
            "text-anchor": "top", "text-offset": [0, 1], "text-optional": true },
          paint: { "text-color": ink, "text-halo-color": paper, "text-halo-width": 1.6 } },
        { id: "birds", type: "symbol", source: "birds",
          layout: { "icon-image": "x-mark", "icon-allow-overlap": true, "icon-size": ["case", ["to-boolean", ["get", "first"]], 1, 0.75],
            "symbol-sort-key": ["case", ["to-boolean", ["get", "first"]], 1, 0],
            "text-field": ["get", "label"], "text-font": FONT_IT, "text-size": 11, "text-offset": [0, 1.4], "text-anchor": "top", "text-optional": true },
          paint: { "text-color": madder, "text-halo-color": paper, "text-halo-width": 1.6 } }
      ]
    };
  }

  /* little hand-drawn pictures, made here so the page needs no image files */
  function pic(size, draw) {
    var c = document.createElement("canvas"); c.width = c.height = size;
    var g = c.getContext("2d"); g.lineCap = "round"; g.lineJoin = "round"; draw(g, size);
    return g.getImageData(0, 0, size, size);
  }
  var PICS = {
    "x-mark": function () { return pic(48, function (g) {
      function s(col, w) { g.strokeStyle = col; g.lineWidth = w; g.beginPath(); g.moveTo(12, 13); g.quadraticCurveTo(24, 23, 36, 35); g.moveTo(35, 12); g.quadraticCurveTo(25, 25, 13, 36); g.stroke(); }
      s(C.paper, 13); s(C.madder, 6); }); },
    "start": function () { return pic(36, function (g) {
      g.fillStyle = C.paper; g.strokeStyle = C.ink; g.lineWidth = 3; g.beginPath(); g.arc(18, 18, 9, 0, Math.PI * 2); g.fill(); g.stroke(); }); },
    "end": function () { return pic(36, function (g) {
      g.fillStyle = C.paper; g.strokeStyle = C.ink; g.lineWidth = 2.5; g.beginPath(); g.arc(18, 18, 10, 0, Math.PI * 2); g.fill(); g.stroke();
      g.fillStyle = C.ink; g.beginPath(); g.arc(18, 18, 5, 0, Math.PI * 2); g.fill(); }); },
    "trees": function () { return pic(64, function (g) {
      function tree(x, y, r) { g.strokeStyle = "#5f7146"; g.lineWidth = 1.6; g.beginPath(); g.moveTo(x, y + r * 0.6); g.lineTo(x, y + r * 1.9); g.stroke();
        g.fillStyle = "rgba(122,145,92,.55)"; g.beginPath(); g.ellipse(x, y, r, r * 1.05, 0, 0, Math.PI * 2); g.fill(); g.stroke(); }
      tree(14, 14, 6); tree(44, 22, 5); tree(26, 44, 6.5); tree(56, 52, 4.5); tree(6, 52, 4); }); },
    "reeds": function () { return pic(48, function (g) {
      g.strokeStyle = "#7b8c63"; g.lineWidth = 1.3;
      function tuft(x, y) { g.beginPath(); g.moveTo(x - 4, y - 5); g.lineTo(x - 1, y); g.moveTo(x, y - 7); g.lineTo(x, y); g.moveTo(x + 4, y - 5); g.lineTo(x + 1, y); g.moveTo(x - 6, y); g.lineTo(x + 6, y); g.stroke(); }
      tuft(12, 16); tuft(36, 30); tuft(18, 42); }); },
    "peak": function () { return pic(40, function (g) {
      g.fillStyle = C.paper; g.strokeStyle = C.ink; g.lineWidth = 2.2;
      g.beginPath(); g.moveTo(6, 34); g.lineTo(19.5, 7); g.lineTo(21, 8); g.lineTo(34, 34); g.closePath(); g.fill(); g.stroke();
      g.lineWidth = 1.2; g.beginPath(); g.moveTo(21, 13); g.lineTo(13, 30); g.moveTo(24, 19); g.lineTo(18, 32); g.moveTo(27, 25); g.lineTo(23, 33); g.stroke(); }); },
    "bldg": function () { return pic(32, function (g) {
      g.fillStyle = C.paper; g.strokeStyle = "#6b4a33"; g.lineWidth = 2;
      g.beginPath(); g.moveTo(8, 27); g.lineTo(8, 15); g.lineTo(16, 8); g.lineTo(24, 15); g.lineTo(24, 27); g.closePath(); g.fill(); g.stroke();
      g.beginPath(); g.moveTo(16, 8); g.lineTo(16, 3); g.moveTo(13.5, 5); g.lineTo(18.5, 5); g.moveTo(14, 27); g.lineTo(14, 20); g.lineTo(18, 20); g.lineTo(18, 27); g.stroke(); }); },
    "wiki": function () { return pic(28, function (g) {
      g.fillStyle = C.paper; g.strokeStyle = "#3d5566"; g.lineWidth = 2; g.beginPath(); g.arc(14, 14, 8, 0, Math.PI * 2); g.fill(); g.stroke();
      g.fillStyle = "#3d5566"; g.beginPath(); g.arc(14, 14, 2.6, 0, Math.PI * 2); g.fill(); }); },
    "hatch": function () { return pic(16, function (g) {
      g.strokeStyle = "rgba(138,90,58,.55)"; g.lineWidth = 1.2;
      g.beginPath(); g.moveTo(-2, 6); g.lineTo(6, -2); g.moveTo(-2, 14); g.lineTo(14, -2); g.moveTo(6, 18); g.lineTo(18, 6); g.stroke(); }); }
  };

  function makeMap() {
    C = { paper: cssVar("--paper", "#eee5ce"), ink: cssVar("--ink", "#2a241c"), sepia: cssVar("--sepia", "#6b5338"), madder: cssVar("--madder", "#8c3b2a") };
    map = new maplibregl.Map({
      container: canvas, style: mapStyle(), center: [-1.5, 52.5], zoom: 5, maxPitch: 0, dragRotate: false,
      attributionControl: { compact: true, customAttribution: "Elevation: Mapzen Terrain Tiles (AWS) · OpenFreeMap © OpenMapTiles © OpenStreetMap" }
    });
    map.touchZoomRotate.disableRotation();
    map.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-left");
    map.on("styleimagemissing", function (e) { var f = PICS[e.id]; if (f && !map.hasImage(e.id)) map.addImage(e.id, f(), { pixelRatio: 2 }); });
    map.on("error", function (e) { if (window.console) console.warn("map:", e && e.error && e.error.message || e); });
    map.on("load", function () {
      ready = true;
      showExtras();
      map.on("moveend", contoursSoon);
      map.on("dragstart", function () { fitted = true; });
      wireTaps();
      say("");
      refreshSoon(0);
    });
  }

  function vis(ids, on) { ids.forEach(function (id) { if (map.getLayer(id)) map.setLayoutProperty(id, "visibility", on ? "visible" : "none"); }); }
  function showExtras() { if (ready) vis(EXTRA_LAYERS, S.extras); }

  /* ---------- the walk ---------- */
  var refreshTimer = null, lastFetch = 0;
  function refreshSoon(ms) {
    if (!ready) return;
    clearTimeout(refreshTimer);
    // at most every few seconds while listening: the app nudges after every bird
    var wait = Math.max(ms, 3000 - (Date.now() - lastFetch));
    refreshTimer = setTimeout(refresh, Math.max(0, wait));
  }
  function refresh() {
    lastFetch = Date.now();
    fetch("/app/walk.json", { cache: "no-store" }).then(function (r) { return r.ok ? r.json() : null; }).catch(function () { return null; })
      .then(function (w) {
        if (!w || !w.available) { walk = null; drawWalk(); say("No walk to show: the map draws sessions recorded while listening here."); return; }
        var key = (w.sessions || []).join(",");
        if (key !== walkKey) { walkKey = key; fitted = false; places = null; }
        walk = w;
        drawWalk();
        if (!fitted) fitWalk();
        if (S.extras) loadPlaces(false);
      });
  }

  function birdFeatures() {
    var ds = (walk && walk.detections) || [], seen = {}, out = [];
    ds.forEach(function (d) {
      var first = !seen[d.scientificName]; seen[d.scientificName] = true;
      if (S.birds !== "all" && !first) return;
      out.push({ type: "Feature", properties: { sci: d.scientificName, common: d.commonName, first: first, label: first ? d.commonName : "" },
        geometry: { type: "Point", coordinates: [d.longitude, d.latitude] } });
    });
    return out;
  }

  function drawWalk() {
    if (!ready) return;
    var t = (walk && walk.trail) || [];
    var line = t.map(function (p) { return [p[0], p[1]]; });
    map.getSource("trail").setData(line.length > 1
      ? { type: "FeatureCollection", features: [{ type: "Feature", properties: {}, geometry: { type: "LineString", coordinates: line } }] } : EMPTY);
    var ends = [];
    var a = line[0] || (walk && walk.place);
    if (a) ends.push({ type: "Feature", properties: { icon: "start", label: "Start" }, geometry: { type: "Point", coordinates: a } });
    if (line.length > 1) ends.push({ type: "Feature", properties: { icon: "end", label: walk.live ? "Now" : "End" }, geometry: { type: "Point", coordinates: line[line.length - 1] } });
    map.getSource("ends").setData({ type: "FeatureCollection", features: ends });
    map.getSource("birds").setData({ type: "FeatureCollection", features: birdFeatures() });
    var msg = "";
    if (walk && !line.length && !(walk.detections || []).length) {
      msg = walk.place ? "No trail for this walk: only where it began was noted. Walks recorded from now on show the way you went."
        : "No positions for this walk. With location allowed, the trail is drawn as you listen.";
    } else if (walk && walk.unplaced) {
      msg = walk.unplaced === 1 ? "One call came before the first position fix and isn't on the map."
        : walk.unplaced + " calls came before the first position fix and aren't on the map.";
    }
    say(msg);
  }

  function fitWalk() {
    var pts = [];
    ((walk && walk.trail) || []).forEach(function (p) { pts.push([p[0], p[1]]); });
    ((walk && walk.detections) || []).forEach(function (d) { pts.push([d.longitude, d.latitude]); });
    if (!pts.length && walk && walk.place) { map.jumpTo({ center: walk.place, zoom: 14 }); fitted = true; return; }
    if (!pts.length) return;
    var b = new maplibregl.LngLatBounds(pts[0], pts[0]);
    pts.forEach(function (p) { b.extend(p); });
    var pad = Math.min(60, Math.round(Math.min(canvas.clientWidth, canvas.clientHeight) / 6));
    map.fitBounds(b, { padding: pad, maxZoom: 16, duration: 0 });
    fitted = true;
  }

  /* ---------- taps ---------- */
  function wireTaps() {
    map.on("click", "birds", function (e) {
      var p = e.features[0].properties;
      openBird(p.sci, p.common);
    });
    map.on("click", "ends", function (e) {
      var p = e.features[0].properties, w = walk || {};
      tip("<b>" + esc(p.label) + "</b><i>" + esc(p.icon === "start" ? (w.start || "").slice(11, 16) : (w.end || "").slice(11, 16)) + "</i>", e.point);
    });
    [["peaks", function (p) { return [p.name, p.ele != null ? p.ele + " m" : "Summit"]; }],
     ["listed", function (p) { return [p.label, "Listed building, Grade " + (p.Grade || "")]; }],
     ["sched-fill", function (p) { return [p.label, "Scheduled monument"]; }],
     ["nature-fill", function (p) { return [p.label, p.full]; }],
     ["wiki", function (p) { return [p.title, p.desc || "Wikipedia"]; }]].forEach(function (x) {
      map.on("click", x[0], function (e) {
        if (map.queryRenderedFeatures(e.point, { layers: ["birds"] }).length) return;
        var t = x[1](e.features[0].properties);
        tip("<b>" + esc(t[0]) + "</b><i>" + esc(t[1]) + "</i>", e.point);
      });
    });
    ["birds", "ends", "peaks", "listed", "wiki"].forEach(function (id) {
      map.on("mouseenter", id, function () { map.getCanvas().style.cursor = "pointer"; });
      map.on("mouseleave", id, function () { map.getCanvas().style.cursor = ""; });
    });
    map.on("movestart", function () { if (tipEl) tipEl.classList.remove("on"); });
  }

  // The page's own name label (#tip), for things on the map that aren't birds.
  function tip(html, pt) {
    if (!tipEl) return;
    var r = canvas.getBoundingClientRect(), x = r.left + pt.x, y = r.top + pt.y;
    tipEl.innerHTML = html; tipEl.classList.add("on");
    var w = tipEl.offsetWidth, h = tipEl.offsetHeight;
    tipEl.style.left = Math.max(8, Math.min(innerWidth - w - 8, x - w / 2)) + "px";
    tipEl.style.top = (y - h - 18 < 8 ? y + 22 : y - h - 18) + "px";
    clearTimeout(tip.t); tip.t = setTimeout(function () { tipEl.classList.remove("on"); }, 3500);
  }

  // The plate's own card for that bird; the page's row for it when it has
  // one (this session), else what the walk knows (a bird from an earlier or
  // later part of the same walk).
  function openBird(sci, common) {
    var sp = null;
    try { sp = (species || []).find(function (s) { return s.sci === sci; }) || null; } catch (e) {}
    if (!sp) {
      var n = ((walk && walk.detections) || []).filter(function (d) { return d.scientificName === sci; }).length;
      sp = { sci: sci, common: common, count: n };
    }
    try { openDetail(sp); } catch (e) {}
  }

  /* ---------- contours, traced here from terrain-RGB tiles ---------- */
  var tileCache = new Map(), contourRun = 0, lastContourKey = "", contourTimer = null;
  function contoursSoon() { clearTimeout(contourTimer); contourTimer = setTimeout(contours, 150); }
  function demTile(z, x, y) {
    var key = z + "/" + x + "/" + y;
    if (!tileCache.has(key)) {
      tileCache.set(key, fetch(DEM + key + ".png").then(function (r) { if (!r.ok) throw new Error("elevation " + key + ": " + r.status); return r.blob(); })
        .then(function (b) { return createImageBitmap(b); })
        .catch(function (e) { tileCache.delete(key); throw e; }));
      if (tileCache.size > 160) tileCache.delete(tileCache.keys().next().value);
    }
    return tileCache.get(key);
  }
  function tileRange(f, z) {
    var n = Math.pow(2, z);
    function lx(l) { return (l + 180) / 360 * n; }
    function ly(la) { var r = la * Math.PI / 180; return (1 - Math.log(Math.tan(r) + 1 / Math.cos(r)) / Math.PI) / 2 * n; }
    return { x0: Math.floor(lx(f[0])), x1: Math.floor(lx(f[2])), y0: Math.floor(ly(f[3])), y1: Math.floor(ly(f[1])) };
  }
  function intervalFor(zoom) {
    return zoom >= 15 ? [5, 25] : zoom >= 12.5 ? [10, 50] : zoom >= 11 ? [20, 100] : zoom >= 10 ? [25, 100] : zoom >= 9 ? [50, 250] : [100, 500];
  }
  function contours() {
    if (!ready || !S.on || !window.d3) return;
    var zoom = map.getZoom();
    if (zoom < 7) { map.getSource("contours").setData(EMPTY); lastContourKey = ""; return; }
    var b = map.getBounds(), dx = (b.getEast() - b.getWest()) * 0.15, dy = (b.getNorth() - b.getSouth()) * 0.15;
    var frame = [b.getWest() - dx, Math.max(-80, b.getSouth() - dy), b.getEast() + dx, Math.min(80, b.getNorth() + dy)];
    var z = Math.min(14, Math.max(5, Math.floor(zoom) + 1));
    while (z > 5) { var r0 = tileRange(frame, z); if ((r0.x1 - r0.x0 + 1) * (r0.y1 - r0.y0 + 1) <= 36) break; z--; }
    var iv = intervalFor(zoom), r = tileRange(frame, z);
    var key = z + ":" + r.x0 + "-" + r.x1 + ":" + r.y0 + "-" + r.y1 + ":" + iv;
    if (key === lastContourKey) return;
    lastContourKey = key;
    var run = ++contourRun;
    trace(r, z, iv).then(function (fc) { if (run === contourRun) map.getSource("contours").setData(fc); })
      .catch(function () { if (run === contourRun) lastContourKey = ""; });
  }
  function trace(r, z, iv) {
    var T = 256, n = Math.pow(2, z), W = (r.x1 - r.x0 + 1) * T, H = (r.y1 - r.y0 + 1) * T;
    var cv = document.createElement("canvas"); cv.width = W; cv.height = H;
    var g = cv.getContext("2d", { willReadFrequently: true }), jobs = [];
    for (var x = r.x0; x <= r.x1; x++) for (var y = r.y0; y <= r.y1; y++) (function (x, y) {
      jobs.push(demTile(z, x, y).then(function (img) { g.drawImage(img, (x - r.x0) * T, (y - r.y0) * T); }));
    })(x, y);
    return Promise.all(jobs).then(function () {
      var px = g.getImageData(0, 0, W, H).data, s = 2, w = W / s, h = H / s, v = new Float32Array(w * h);
      for (var j = 0; j < h; j++) for (var i = 0; i < w; i++) { var o = ((j * s) * W + i * s) * 4; v[j * w + i] = px[o] * 256 + px[o + 1] + px[o + 2] / 256 - 32768; }
      function blur(src, rad) {
        var tmp = new Float32Array(w * h), out = new Float32Array(w * h), i, j, sm, c;
        for (j = 0; j < h; j++) { sm = 0; c = 0; for (i = -rad; i < w; i++) { if (i + rad < w) { sm += src[j * w + i + rad]; c++; } if (i - rad - 1 >= 0) { sm -= src[j * w + i - rad - 1]; c--; } if (i >= 0) tmp[j * w + i] = sm / c; } }
        for (i = 0; i < w; i++) { sm = 0; c = 0; for (j = -rad; j < h; j++) { if (j + rad < h) { sm += tmp[(j + rad) * w + i]; c++; } if (j - rad - 1 >= 0) { sm -= tmp[(j - rad - 1) * w + i]; c--; } if (j >= 0) out[j * w + i] = sm / c; } }
        return out;
      }
      v = z >= 13 ? blur(blur(blur(v, 3), 3), 3) : blur(blur(v, 2), 2);
      var lo = Infinity, hi = -Infinity;
      for (var k = 0; k < v.length; k++) { if (v[k] < lo) lo = v[k]; if (v[k] > hi) hi = v[k]; }
      lo = Math.max(lo, 0.5);
      var levels = []; for (var t = Math.ceil(lo / iv[0]) * iv[0]; t <= hi; t += iv[0]) levels.push(t);
      var polys = d3.contours().size([w, h]).thresholds(levels)(v), features = [];
      function ll(X, Y) { var gx = r.x0 * T + X * s, gy = r.y0 * T + Y * s; return [gx / (n * T) * 360 - 180, Math.atan(Math.sinh(Math.PI * (1 - 2 * gy / (n * T)))) * 180 / Math.PI]; }
      function edge(p) { return p[0] <= 1 || p[1] <= 1 || p[0] >= w - 1 || p[1] >= h - 1; }
      polys.forEach(function (c) {
        var major = Math.round(c.value) % iv[1] === 0 ? 1 : 0;
        c.coordinates.forEach(function (poly) { poly.forEach(function (ring) {
          var line = [];
          function flush() { if (line.length > 3) features.push({ type: "Feature", properties: { ele: Math.round(c.value), major: major }, geometry: { type: "LineString", coordinates: line } }); line = []; }
          ring.forEach(function (p) { if (edge(p)) flush(); else line.push(ll(p[0], p[1])); });
          flush();
        }); });
      });
      return { type: "FeatureCollection", features: features };
    });
  }

  /* ---------- extras: heritage, nature sites, Wikipedia (only when asked) ---------- */
  var HE = "https://services-eu1.arcgis.com/ZOdPfBS3aqqDYPUQ/arcgis/rest/services/National_Heritage_List_for_England_NHLE_v02_VIEW/FeatureServer";
  var NE = "https://services.arcgis.com/JJzESW51TqeY9uat/arcgis/rest/services";
  var NATURE = [
    { kind: "SPA", full: "Special Protection Area (birds)", url: NE + "/Special_Protection_Areas_England/FeatureServer/0" },
    { kind: "SSSI", full: "Site of Special Scientific Interest", url: NE + "/SSSI_England/FeatureServer/0" },
    { kind: "NNR", full: "National Nature Reserve", url: NE + "/National_Nature_Reserves_England/FeatureServer/0" },
    { kind: "LNR", full: "Local Nature Reserve", url: NE + "/Local_Nature_Reserves_England/FeatureServer/0" }
  ];
  var places = null;   // the walk these were looked up for

  function nameOf(p) { for (var k in p) if (/(^|_)name$/i.test(k) && p[k]) return p[k]; return "Unnamed"; }
  function arc(url, frame, where, simplify) {
    var q = new URLSearchParams({ where: where || "1=1", geometry: frame.join(","), geometryType: "esriGeometryEnvelope", inSR: "4326",
      spatialRel: "esriSpatialRelIntersects", outFields: "*", outSR: "4326", returnGeometry: "true", f: "geojson" });
    if (simplify) { q.set("maxAllowableOffset", simplify); q.set("geometryPrecision", "6"); }
    return fetch(url + "/query?" + q).then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); }).then(function (j) {
      if (j.type === "FeatureCollection") return j.features || [];
      q.set("f", "json");
      return fetch(url + "/query?" + q).then(function (r) { return r.json(); }).then(function (j2) {
        if (j2.error) throw new Error(j2.error.message || "query failed");
        return (j2.features || []).filter(function (f) { return f.geometry; }).map(function (f) {
          return { type: "Feature", properties: f.attributes, geometry: f.geometry.rings ? { type: "Polygon", coordinates: f.geometry.rings } : { type: "Point", coordinates: [f.geometry.x, f.geometry.y] } };
        });
      });
    });
  }
  function wikiNear(frame) {
    var q = new URLSearchParams({ action: "query", format: "json", origin: "*", generator: "geosearch",
      ggsbbox: frame[3] + "|" + frame[0] + "|" + frame[1] + "|" + frame[2], ggslimit: "20",
      prop: "coordinates|description", colimit: "20" });
    return fetch("https://en.wikipedia.org/w/api.php?" + q).then(function (r) { return r.json(); }).then(function (j) {
      var pages = (j.query && j.query.pages) || {};
      return Object.keys(pages).map(function (k) { return pages[k]; }).filter(function (p) { return p.coordinates; }).map(function (p) {
        return { type: "Feature", properties: { title: p.title, desc: p.description || "", pageid: p.pageid },
          geometry: { type: "Point", coordinates: [p.coordinates[0].lon, p.coordinates[0].lat] } };
      });
    });
  }

  function hav(a, b) { var R = 6371000, r = Math.PI / 180, dA = (b[1] - a[1]) * r, dO = (b[0] - a[0]) * r;
    var s = Math.pow(Math.sin(dA / 2), 2) + Math.cos(a[1] * r) * Math.cos(b[1] * r) * Math.pow(Math.sin(dO / 2), 2); return 2 * R * Math.asin(Math.sqrt(s)); }
  function coords(g) { return g.type === "Point" ? [g.coordinates] : g.type === "Polygon" ? [].concat.apply([], g.coordinates) : g.type === "MultiPolygon" ? [].concat.apply([], [].concat.apply([], g.coordinates)) : []; }
  function inRing(pt, ring) { var ins = false; for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) { var xi = ring[i][0], yi = ring[i][1], xj = ring[j][0], yj = ring[j][1];
    if (((yi > pt[1]) !== (yj > pt[1])) && pt[0] < (xj - xi) * (pt[1] - yi) / (yj - yi) + xi) ins = !ins; } return ins; }
  function inPoly(pt, g) { var ps = g.type === "Polygon" ? [g.coordinates] : g.type === "MultiPolygon" ? g.coordinates : [];
    return ps.some(function (rs) { return inRing(pt, rs[0]) && !rs.slice(1).some(function (h) { return inRing(pt, h); }); }); }

  function loadPlaces(force) {
    if (!ready || !walk || !S.extras) return;
    if (places === walkKey && !force) return;
    var path = (walk.trail || []).map(function (p) { return [p[0], p[1]]; }).concat((walk.detections || []).map(function (d) { return [d.longitude, d.latitude]; }));
    if (!path.length && walk.place) path = [walk.place];
    if (!path.length) return;
    places = walkKey;
    var x0 = 180, y0 = 90, x1 = -180, y1 = -90;
    path.forEach(function (p) { x0 = Math.min(x0, p[0]); x1 = Math.max(x1, p[0]); y0 = Math.min(y0, p[1]); y1 = Math.max(y1, p[1]); });
    var px = Math.max(0.004, (x1 - x0) * 0.2), py = Math.max(0.003, (y1 - y0) * 0.2);
    var frame = [x0 - px, y0 - py, x1 + px, y1 + py];
    var probe = path.filter(function (_, i) { return i % Math.max(1, Math.floor(path.length / 150)) === 0; });
    function near(pt) { return Math.min.apply(null, probe.map(function (p) { return hav(p, pt); })); }
    var passed = [], status = [];
    var list = document.querySelector("#bsPassed ol"), st = document.querySelector("#bsPassed .st");
    if (list) list.innerHTML = ""; if (st) st.textContent = "Looking up what the walk passed…";
    var jobs = [
      arc(HE + "/0", frame, "Grade IN ('I','II*')").then(function (fs) {
        fs.forEach(function (f) { f.properties.label = nameOf(f.properties); var d = near(f.geometry.coordinates);
          if (d <= 120) passed.push({ name: f.properties.label, kind: "Listed building, Grade " + f.properties.Grade, at: f.geometry.coordinates, d: d, o: 1 }); });
        map.getSource("he-listed").setData({ type: "FeatureCollection", features: fs });
      }).catch(function () { status.push("Historic England (buildings)"); }),
      arc(HE + "/6", frame, null, 0.00002).then(function (fs) {
        fs.forEach(function (f) { f.properties.label = nameOf(f.properties); var cs = coords(f.geometry);
          var inside = probe.some(function (p) { return inPoly(p, f.geometry); }), d = inside ? 0 : Math.min.apply(null, cs.filter(function (_, i) { return i % Math.max(1, Math.floor(cs.length / 100)) === 0; }).map(near));
          if (d <= 200) passed.push({ name: f.properties.label, kind: "Scheduled monument", at: cs[0], d: d, o: 1 }); });
        map.getSource("he-sched").setData({ type: "FeatureCollection", features: fs });
      }).catch(function () { status.push("Historic England (monuments)"); }),
      Promise.all(NATURE.map(function (s) {
        return arc(s.url, frame, null, 0.0001).then(function (fs) {
          fs.forEach(function (f) { f.properties.label = nameOf(f.properties); f.properties.kind = s.kind; f.properties.full = s.full; });
          return fs;
        }).catch(function () { status.push("Natural England (" + s.kind + ")"); return []; });
      })).then(function (all) {
        var fs = [].concat.apply([], all), seen = {};
        fs.forEach(function (f) { var k = f.properties.kind + f.properties.label; if (seen[k]) return; seen[k] = 1;
          if (probe.some(function (p) { return inPoly(p, f.geometry); })) passed.push({ name: f.properties.label, kind: f.properties.full, at: null, d: 0, o: 0 }); });
        map.getSource("nature-sites").setData({ type: "FeatureCollection", features: fs });
      }),
      wikiNear(frame).then(function (fs) {
        fs.forEach(function (f) { var d = near(f.geometry.coordinates);
          if (d <= 400) passed.push({ name: f.properties.title, kind: f.properties.desc || "Wikipedia", at: f.geometry.coordinates, d: d, o: 2 }); });
        map.getSource("wiki").setData({ type: "FeatureCollection", features: fs });
      }).catch(function () { status.push("Wikipedia"); })
    ];
    Promise.all(jobs).then(function () {
      passed.sort(function (a, b) { return a.o - b.o || a.d - b.d; });
      if (list) list.replaceChildren.apply(list, passed.map(function (p) {
        var li = document.createElement("li");
        li.innerHTML = "<span class='n'>" + esc(p.name) + "</span> <span class='k'>" + esc(p.kind) + "</span>"
          + "<span class='d'>" + (p.at ? Math.round(p.d) + " m" : "walked through") + "</span>";
        li.addEventListener("click", function () { if (p.at) map.flyTo({ center: p.at, zoom: Math.max(map.getZoom(), 15.5) }); });
        return li;
      }));
      if (st) st.textContent = (passed.length ? "" : "Nothing listed along the way. ") + (status.length ? "Couldn't reach: " + status.join(", ") + "." : "");
    });
  }
})();
