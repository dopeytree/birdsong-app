import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../settings.dart';
import '../store/detection_store.dart';
import 'local_api.dart' as api;

/// A small web server on 127.0.0.1 doing nginx's job from the Docker image:
/// it serves the page and its fonts, writes source.json, and answers /api
/// either by forwarding to BirdNET-Go (Station) or from this device's own
/// detections (Listen here).
class LocalServer {
  LocalServer(this.settings, this.store, {this.plateModel});

  final Settings settings;
  final DetectionStore store;

  /// Which model's detections the plate shows; read on every request.
  final String Function()? plateModel;

  HttpServer? _server;
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  final Map<String, Uint8List> _assets = {};

  int get port => _server?.port ?? 0;
  String get origin => 'http://127.0.0.1:$port';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((req) {
      _handle(req).catchError((Object e) {
        debugPrint('server: ${req.uri} failed: $e');
        try {
          req.response.statusCode = HttpStatus.internalServerError;
          req.response.close();
        } catch (_) {}
      });
    });
    debugPrint('Birdsong page at $origin');
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _client.close(force: true);
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    final path = req.uri.path;
    res.headers.set('Cache-Control', 'no-store');

    if (path == '/' || path == '/index.html') return _page(res);
    if (path.startsWith('/fonts/')) {
      final name = path.substring('/fonts/'.length);
      if (name.contains('..') || name.contains('/')) return _notFound(res);
      return _asset(res, 'assets/web/fonts/$name',
          name.endsWith('.ttf') ? 'font/ttf' : 'text/plain; charset=utf-8');
    }
    // The Support section's cardinal, bundled with the app (the page looks
    // for it in an art folder beside itself, which only the Docker image has).
    if (path == '/art/artwork/classic/birds/cardinalis-cardinalis.webp') {
      return _asset(res, 'assets/app/cardinal.webp', 'image/webp');
    }
    // The app's own additions to the page: folding the index, pinch zoom.
    if (path == '/app/plate-extras.js') {
      return _asset(res, 'assets/app/plate-extras.js', 'text/javascript; charset=utf-8');
    }
    if (path == '/source.json') return _json(res, _source());
    if (path == '/healthz') {
      res.write('ok\n');
      return res.close();
    }
    if (path == '/graphql') return _birdweather(req);
    if (path.startsWith('/api/')) {
      if (settings.mode == AppMode.station) return _forward(req);
      return _local(req);
    }
    // /art/ and anything else: not here. The page then fetches the
    // Fugleramme artwork from GitHub, as it does without a local copy.
    return _notFound(res);
  }

  Map<String, dynamic> _source() {
    if (settings.mode == AppMode.station && settings.stationDigits.isNotEmpty) {
      return {
        'birdweatherStation': settings.stationDigits,
        'proxy': true,
        'birdnet': false,
      };
    }
    if (settings.mode == AppMode.station) {
      return {'birdnet': settings.birdnetBase.isNotEmpty};
    }
    return {'birdnet': true};
  }

  // ---- Listen here: answer from this device's detections -----------------

  Future<void> _local(HttpRequest req) async {
    final res = req.response;
    final q = req.uri.queryParameters;
    final path = req.uri.path;
    // Listen here draws one listening session at a time, picked with the
    // arrows on the plate; the page is told period=all, and the dates it
    // sends are set aside in favour of the session.
    final session = store.selected;
    final all = store.forPlate(plateModel?.call() ?? 'all', session: session);
    final bySession = session != null;
    String? from(String key) => bySession ? null : q[key];

    if (path.startsWith('/api/v2/analytics/species/daily')) {
      return _json(res, api.speciesDaily(all, q['date']));
    }
    if (path.startsWith('/api/v2/analytics/species/summary')) {
      return _json(res, api.speciesSummary(all, from('start_date'), from('end_date')));
    }
    if (path.startsWith('/api/v2/analytics/time/distribution/hourly')) {
      return _json(res, api.hourly(all, q['species'] ?? '', from('start_date'), from('end_date')));
    }
    if (path.startsWith('/api/v2/analytics/time/daily')) {
      return _json(res, api.daily(all, q['species'] ?? '', from('start_date'), from('end_date')));
    }
    if (path.startsWith('/api/v2/detections')) {
      final n = int.tryParse(q['numResults'] ?? '') ?? 5;
      return _json(res, api.detections(all, q['species'] ?? '', n));
    }
    if (path.startsWith('/api/v2/species')) {
      // No taxonomy on the device yet: the card leaves family and order off.
      return _json(res, {'scientific_name': q['scientific_name'] ?? ''});
    }
    if (path.startsWith('/api/v2/audio/')) {
      final id = int.tryParse(path.split('/').last);
      final f = id == null ? null : store.clipFile(id);
      if (f == null || !await f.exists()) return _notFound(res);
      return _file(req, f, 'audio/wav');
    }
    if (path.startsWith('/api/v2/spectrogram/')) {
      final id = int.tryParse(path.split('/').last);
      final f = id == null ? null : store.spectrogramFile(id);
      if (f == null || !await f.exists()) return _notFound(res);
      return _file(req, f, 'image/bmp');
    }
    return _json(res, <Object>[]);
  }

  // ---- Station: forward to BirdNET-Go ------------------------------------

  Future<void> _forward(HttpRequest req) async {
    final res = req.response;
    final base = settings.birdnetBase;
    if (base.isEmpty) {
      res.statusCode = HttpStatus.badGateway;
      return _json(res, {'error': 'No BirdNET-Go address set. Add one in Settings.'});
    }
    final target = Uri.parse('$base${req.uri.path}${req.uri.hasQuery ? '?${req.uri.query}' : ''}');
    try {
      final out = await _client.openUrl(req.method, target);
      out.followRedirects = false;
      final range = req.headers.value(HttpHeaders.rangeHeader);
      if (range != null) out.headers.set(HttpHeaders.rangeHeader, range);
      out.headers.set(HttpHeaders.acceptHeader, req.headers.value(HttpHeaders.acceptHeader) ?? '*/*');
      if (req.method == 'POST' || req.method == 'PUT') {
        await out.addStream(req);
      }
      final back = await out.close();
      res.statusCode = back.statusCode;
      for (final h in [
        HttpHeaders.contentTypeHeader,
        HttpHeaders.contentLengthHeader,
        HttpHeaders.contentRangeHeader,
        HttpHeaders.acceptRangesHeader,
      ]) {
        final v = back.headers.value(h);
        if (v != null) res.headers.set(h, v);
      }
      await res.addStream(back);
      await res.close();
    } catch (e) {
      res.statusCode = HttpStatus.badGateway;
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({'error': 'BirdNET-Go at $base did not answer: $e'}));
      await res.close();
    }
  }

  // ---- Station: BirdWeather's public GraphQL ------------------------------

  Future<void> _birdweather(HttpRequest req) async {
    final res = req.response;
    if (req.method != 'POST') {
      res.statusCode = HttpStatus.methodNotAllowed;
      return res.close();
    }
    try {
      final body = await req.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      final out = await _client.postUrl(Uri.parse('https://app.birdweather.com/graphql'));
      out.headers.contentType = ContentType.json;
      out.headers.set(HttpHeaders.acceptHeader, 'application/json');
      out.add(body);
      final back = await out.close();
      res.statusCode = back.statusCode;
      res.headers.contentType = ContentType.json;
      await res.addStream(back);
      await res.close();
    } catch (e) {
      res.statusCode = HttpStatus.badGateway;
      return _json(res, {'errors': [{'message': 'BirdWeather did not answer: $e'}]});
    }
  }

  // ---- the page, tailored for the app -------------------------------------

  // The app's own Settings tab decides where detections come from, so the
  // page's Station section (a BirdNET-Go address, a BirdWeather number) and
  // its Home Assistant card builder are hidden, and any address typed there
  // in an earlier build is forgotten: left in place it would send the page
  // off to that address instead of asking this app.
  static const _headExtra = '<script>try{localStorage.removeItem("birdplate.server");'
      'localStorage.removeItem("birdplate.station");'
      // Listen here starts with the dot beneath the creature; Display changes it.
      'if(/[?&]bs=listen/.test(location.search)&&localStorage.getItem("birdplate.markAt")==null)'
      'localStorage.setItem("birdplate.markAt",JSON.stringify("below"))}catch(e){}</script>'
      '<style>#stationOpts,#cardOpts{display:none}'
      // No plate number in the app; room on the right for the microphone.
      // The page's Settings/Display button too: its options are in the
      // app's menu (Settings > Display).
      // (Both live in #plateno, so the whole corner goes.)
      '#plateno{display:none!important}'
      // The session number after the title: Birdsong #2/3.
      '#bsCount{margin-left:.35em;color:var(--sepia)}#bsCount:empty{display:none}'
      '#bsPlace:empty{display:none}'
      'html{background:var(--paper)}'
      // plate-extras.js: the folding index and the zoomable collage.
      '.bsIx{cursor:pointer;-webkit-user-select:none;user-select:none}'
      '.bsIxArrow{display:none;text-align:center;line-height:1;margin:0 0 .1rem;cursor:pointer;'
      'font-family:var(--serif);color:var(--sepia);-webkit-user-select:none;user-select:none}'
      'body.bs-noindex .bsIxArrow{display:block}body.bs-noindex #index{display:none}'
      '#bsZoomBox{overflow:hidden;touch-action:pan-x pan-y}body.bs-zoomed #bsZoomBox{touch-action:none}'
      'body{padding:max(env(safe-area-inset-top),var(--bs-top,0px)) max(env(safe-area-inset-right),var(--bs-right,0px))'
      ' max(env(safe-area-inset-bottom),var(--bs-bottom,0px)) max(env(safe-area-inset-left),var(--bs-left,0px))}'

      // A creature being heard right now glows, and the dot on it (over its
      // centre, or beneath it) breathes out a ring, in the plate's madder.
      '@keyframes bsGlow{0%,100%{filter:drop-shadow(0 0 0 rgba(140,59,42,0))}'
      '50%{filter:drop-shadow(0 0 .8rem rgba(140,59,42,.7))}}'
      '@keyframes bsRing{0%{box-shadow:0 0 0 0 rgba(140,59,42,.6),0 0 4px #eee5ce}'
      '100%{box-shadow:0 0 0 .8rem rgba(140,59,42,0),0 0 4px #eee5ce}}'
      '.bird.live{animation:bsGlow 1.6s ease-in-out infinite}'
      '.bird.live::after{animation:bsRing 1.6s ease-out infinite}'
      '@media (prefers-reduced-motion:reduce){.bird.live{animation:none;'
      'filter:drop-shadow(0 0 .6rem rgba(140,59,42,.6))}.bird.live::after{animation:none}}'
      '</style>';

  // window.birdsongLive(["Turdus merula", ...]) marks the creatures being
  // heard; the app calls it after every window it analyses.
  // window.birdsongSession(text) puts the listening session's date, time and
  // place where the page's date line is; the page's own redraws keep it.
  // The plate's own Settings, which in the app only holds what to show, is
  // called Display here, so it isn't confused with the app's Settings.
  static const _bodyExtra = '<script>(function(){var s=document.getElementById("stationOpts"),'
      'o=document.getElementById("showOpts");if(s)s.open=false;if(o)o.open=true;'
      'var b=document.getElementById("openSettings");if(b)b.textContent="Display";'
      'var h=document.querySelector("#settings h3");if(h)h.textContent="Display";'
      'var live=new Set();window.birdsongLive=function(list){live=new Set(list||[]);mark();};'
      'function mark(){try{for(const [sci,f] of figures){if(f&&f.button)'
      'f.button.classList.toggle("live",live.has(sci));}}catch(e){}}'
      'new MutationObserver(function(){if(live.size)mark();})'
      '.observe(document.getElementById("plate")||document.body,{childList:true});'
      'var ses=null,num="",where="";window.birdsongSession=function(x,n,w){ses=x;num=n||"";where=w||"";showSession();};'
      'function showSession(){var d=document.getElementById("subDate");'
      'if(d&&ses){d.textContent=ses;var w=document.getElementById("bsPlace");'
      'if(!w){w=document.createElement("span");w.id="bsPlace";d.after(w);}w.textContent=where;}'
      'var h=document.querySelector("header h1");if(h){var c=document.getElementById("bsCount");'
      'if(!c){c=document.createElement("span");c.id="bsCount";h.appendChild(c);}c.textContent=num;}}'
      // Tell the app when one of the page's pop-ups opens or closes, so its
      // buttons and arrows can step aside.
      'function popups(){var open=!!document.querySelector("dialog[open]");'
      'try{window.BirdsongHost&&BirdsongHost.postMessage(open?"popup-open":"popup-closed");}catch(e){}}'
      'document.querySelectorAll("dialog").forEach(function(d){'
      'new MutationObserver(popups).observe(d,{attributes:true,attributeFilter:["open"]});});'
      // Where the "Index of species" line is on screen, so the app's arrows
      // sit on it, clear of the birds and the names; the collage's middle
      // when the index is hidden.
      'var lastMid=null;function plateMid(){var ix=document.getElementById("index"),'
      'h=ix&&ix.previousElementSibling&&ix.previousElementSibling.tagName==="H2"?ix.previousElementSibling:null,'
      'p=h&&h.getBoundingClientRect().height?h:document.getElementById("plate");if(!p)return;'
      'var r=p.getBoundingClientRect();if(!r.height)return;var m=Math.round(r.top+r.height/2);'
      'if(m===lastMid)return;lastMid=m;'
      'try{window.BirdsongHost&&BirdsongHost.postMessage("plate:"+m);}catch(e){}}'
      'addEventListener("resize",plateMid);addEventListener("scroll",plateMid,{passive:true});'
      'new ResizeObserver(plateMid).observe(document.getElementById("plate")||document.body);'
      'setInterval(plateMid,1000);'
      'try{var rh=renderHeading;renderHeading=function(){rh();showSession();};}catch(e){}'
      // "Fit everything on one screen" measures the header and index but not
      // the body's safe-area padding; count it, so nothing scrolls.
      'try{var mo=measureOthers;measureOthers=function(){var c=getComputedStyle(document.body);'
      'return mo()+Math.ceil(parseFloat(c.paddingTop)+parseFloat(c.paddingBottom));};}catch(e){}'
      '})();</script><script src="/app/plate-extras.js"></script>';

  String? _pageHtml;

  Future<void> _page(HttpResponse res) async {
    var html = _pageHtml;
    if (html == null) {
      html = await rootBundle.loadString('assets/web/index.html');
      html = html.replaceFirst('</head>', '$_headExtra</head>');
      // Lay out under the status bar and the Dynamic Island too; the body
      // is padded clear of them (--bs-* from the app, env() from WebKit).
      html = html.replaceFirst(
          'content="width=device-width, initial-scale=1"',
          'content="width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover"');
      final at = html.lastIndexOf('</body>');
      if (at >= 0) html = html.replaceRange(at, at, _bodyExtra);
      _pageHtml = html;
    }
    res.headers.set(HttpHeaders.contentTypeHeader, 'text/html; charset=utf-8');
    res.add(utf8.encode(html));
    await res.close();
  }

  // ---- helpers ------------------------------------------------------------

  Future<void> _asset(HttpResponse res, String key, String type) async {
    var bytes = _assets[key];
    if (bytes == null) {
      try {
        final data = await rootBundle.load(key);
        bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        _assets[key] = bytes;
      } catch (_) {
        return _notFound(res);
      }
    }
    res.headers.set(HttpHeaders.contentTypeHeader, type);
    res.add(bytes);
    await res.close();
  }

  Future<void> _json(HttpResponse res, Object body) async {
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(body));
    await res.close();
  }

  Future<void> _notFound(HttpResponse res) async {
    res.statusCode = HttpStatus.notFound;
    res.write('not here\n');
    await res.close();
  }

  /// A file, honouring a Range request: Safari's audio player asks for one.
  Future<void> _file(HttpRequest req, File f, String type) async {
    final res = req.response;
    final len = await f.length();
    res.headers.set(HttpHeaders.contentTypeHeader, type);
    res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    final range = req.headers.value(HttpHeaders.rangeHeader);
    final m = range == null ? null : RegExp(r'bytes=(\d*)-(\d*)').firstMatch(range);
    if (m != null) {
      var start = int.tryParse(m.group(1) ?? '') ?? 0;
      var end = int.tryParse(m.group(2) ?? '') ?? (len - 1);
      if ((m.group(1) ?? '').isEmpty && (m.group(2) ?? '').isNotEmpty) {
        start = len - end; // suffix range: the last N bytes
        end = len - 1;
      }
      if (end >= len) end = len - 1;
      if (start < 0 || start > end) {
        res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$len');
        return res.close();
      }
      res.statusCode = HttpStatus.partialContent;
      res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$len');
      res.headers.contentLength = end - start + 1;
      await res.addStream(f.openRead(start, end + 1));
      return res.close();
    }
    res.headers.contentLength = len;
    await res.addStream(f.openRead());
    await res.close();
  }
}
