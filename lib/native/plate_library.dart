import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'cutout.dart';

/// A picture that could stand for a species: where it is, not yet fetched.
class PlateCandidate {
  const PlateCandidate(this.url, {required this.ready, required this.credit, this.page});

  final String url;

  /// A transparent cut-out, drawn as it is. Otherwise a plate still on its
  /// paper, which the screen tints into the page (multiply with the paper).
  final bool ready;
  final String credit;

  /// Where the picture is described, for the card's credit.
  final String? page;

  Map<String, dynamic> toJson() => {'url': url, 'ready': ready, 'credit': credit, if (page != null) 'page': page};

  static PlateCandidate fromJson(Map<String, dynamic> j) => PlateCandidate(j['url'] as String,
      ready: j['ready'] == true, credit: (j['credit'] as String?) ?? '', page: j['page'] as String?);
}

/// What is done to a plate that is still on its paper.
enum PlateStyle {
  /// The bird is lifted off the page on this device, as the web plate does.
  cutout('Cut out'),

  /// The whole plate, multiplied with the page's paper colour.
  tint('Tinted'),

  /// The whole plate, untouched.
  plain('As it comes');

  const PlateStyle(this.label);
  final String label;

  static PlateStyle named(String? name) =>
      values.firstWhere((v) => v.name == name, orElse: () => PlateStyle.cutout);
}

/// A picture of one species, on this device.
class PlateArt {
  const PlateArt(this.file, this.from, this.aspect, {this.tint = false, this.cut = false});

  final File file;
  final PlateCandidate from;

  /// Width over height, for the collage.
  final double aspect;

  /// Draw it multiplied with the paper colour.
  final bool tint;

  /// [file] is the figure cut out of the plate on this device.
  final bool cut;

  String get credit => from.credit;
}

/// Finds plates for a species and keeps them on the device, so each picture
/// is fetched once: the Fugleramme cut-outs first, then the engraved plates
/// on Wikimedia Commons, as the web page chooses them (a shorter version of
/// its scoreCandidate and commonsPlates).
///
/// Everything lives in the app's cache folder under plates/: the pictures,
/// the cut-outs' manifest (kept a week), found.json, which remembers what
/// Commons answered for each species (kept 30 days), and choices.json, the
/// plate picked by hand on a bird's card.
class PlateLibrary {
  PlateLibrary._(this.dir);

  final Directory dir;

  static const _art = 'https://raw.githubusercontent.com/arnegiacomo/fugleramme/main/assets';
  static const _commons = 'https://commons.wikimedia.org';
  static const _artists = {
    'gould': 'John Gould',
    'vonwright': 'The von Wright brothers, Svenska Fåglar',
    'audubon': 'John James Audubon',
    'fuertes': 'Louis Agassiz Fuertes',
    'dresser': 'H. E. Dresser, A History of the Birds of Europe',
    'keulemans': 'J. G. Keulemans',
    'wilson': 'Alexander Wilson',
    'levaillant': 'François Levaillant',
    'swainson': 'William Swainson',
  };

  final _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    // Wikimedia asks for a User-Agent that says who is calling.
    ..userAgent = 'BirdsongApp/0.1 (https://github.com/dopeytree/birdsongs.ai)';

  final Map<String, Future<PlateArt?>> _asked = {};
  Future<void>? _manifestLoad;
  final Map<String, List<String>> _cutouts = {}; // slug -> manifest keys, best first
  final Map<String, String> _cutoutSource = {}; // manifest key -> artist key
  final Map<String, String> _cutoutPage = {};
  Map<String, dynamic> _alias = {};
  Map<String, dynamic> _found = {};
  Map<String, dynamic> _choices = {};
  Map<String, dynamic>? _wiki;

  /// Offer plates of skulls, wings and eggs too (Settings), as the page's
  /// "Offer skulls, wings and eggs among the plates". Never chosen first.
  bool parts = false;

  static Future<PlateLibrary> open() async {
    final base = await getApplicationCacheDirectory();
    final dir = Directory('${base.path}/plates');
    await dir.create(recursive: true);
    final lib = PlateLibrary._(dir);
    lib._found = await lib._readMap('found.json');
    lib._choices = await lib._readMap('choices.json');
    return lib;
  }

  Future<Map<String, dynamic>> _readMap(String name) async {
    try {
      final f = File('${dir.path}/$name');
      if (await f.exists()) return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {}
    return {};
  }

  /// The plate for a species: the one picked on its card, else the best
  /// found, treated in [style]. Null when there is none (or no connection
  /// and it isn't on the device yet). Asked once a run for each style.
  Future<PlateArt?> plateFor(String sci, String common, PlateStyle style) =>
      _asked['${style.name}|${parts ? 'p' : ''}|$sci'] ??= _find(sci, common, style).catchError((Object e) {
        debugPrint('plate $sci: $e');
        return null;
      });

  Future<PlateArt?> _find(String sci, String common, PlateStyle style) async {
    final chosen = _choices[sci];
    if (chosen is Map) {
      try {
        return await load(PlateCandidate.fromJson(chosen.cast<String, dynamic>()), style);
      } catch (e) {
        debugPrint('chosen plate $sci: $e');
      }
    }
    final all = await candidates(sci, common);
    return all.isEmpty ? null : load(all.first, style);
  }

  /// Every plate on offer for a species, best first: its cut-outs, then up
  /// to twelve from Commons, as the page offers. For the card's "other plates".
  Future<List<PlateCandidate>> candidates(String sci, String common) async {
    await (_manifestLoad ??= _loadManifest());
    final aliased = _alias[sci];
    final keys = _cutouts[_slug(sci)] ?? (aliased is String ? _cutouts[_slug(aliased)] : null) ?? const [];
    final out = <PlateCandidate>[
      for (final key in keys)
        PlateCandidate(
          '$_art/artwork/classic/$key',
          ready: true,
          credit: '${_artists[_cutoutSource[key]] == null ? '' : 'After ${_artists[_cutoutSource[key]]}. '}'
              'Cut-out from the Fugleramme project, CC BY-SA 4.0.',
          page: _cutoutPage[key],
        ),
    ];
    try {
      out.addAll(await _commonsPlates(sci, common));
    } catch (e) {
      debugPrint('commons $sci: $e');
    }
    return out;
  }

  /// Fetch a candidate (once), treat it in [style] and measure it. A
  /// ready-made cut-out is the same in every style.
  Future<PlateArt> load(PlateCandidate c, PlateStyle style) async {
    final file = await _fetch(c.url);
    if (!c.ready && style == PlateStyle.cutout) {
      final cut = await _cutOut(file);
      if (cut != null) return PlateArt(cut, c, await _aspect(cut), cut: true);
      // A painted scene, or nothing found: the whole plate, tinted.
      return PlateArt(file, c, await _aspect(file), tint: true);
    }
    return PlateArt(file, c, await _aspect(file), tint: !c.ready && style == PlateStyle.tint);
  }

  /// Width over height, from the picture's header only.
  Future<double> _aspect(File file) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromFilePath(file.path);
      final about = await ui.ImageDescriptor.encoded(buffer);
      final aspect = about.height > 0 ? about.width / about.height : 1.2;
      about.dispose();
      buffer.dispose();
      return aspect;
    } catch (e) {
      debugPrint('measure ${file.path}: $e');
      return 1.2;
    }
  }

  /// The figure cut out of the plate in [file], as a PNG beside it, made
  /// once (cutout.dart, on another isolate). Null when the plate is better
  /// left whole, which is remembered too.
  Future<File?> _cutOut(File file) async {
    final cut = File('${file.path}.cut.png'), whole = File('${file.path}.whole');
    if (await cut.exists() && await cut.length() > 0) return cut;
    if (await whole.exists()) return null;
    try {
      // The page works on a copy at most 420 wide; so does this.
      final buffer = await ui.ImmutableBuffer.fromFilePath(file.path);
      final about = await ui.ImageDescriptor.encoded(buffer);
      final codec = await about.instantiateCodec(targetWidth: about.width > 420 ? 420 : null);
      final frame = (await codec.getNextFrame()).image;
      final pixels = await frame.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      final w = frame.width, h = frame.height;
      frame.dispose();
      codec.dispose();
      about.dispose();
      buffer.dispose();
      if (pixels == null) return null;
      final out = await compute(_cutOutOnIsolate, (pixels.buffer.asUint8List(), w, h));
      if (out == null) {
        await whole.writeAsString('');
        return null;
      }
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(out.rgba, out.width, out.height, ui.PixelFormat.rgba8888, done.complete);
      final image = await done.future;
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (png == null) return null;
      final part = File('${cut.path}.part');
      await part.writeAsBytes(png.buffer.asUint8List(), flush: true);
      return await part.rename(cut.path);
    } catch (e) {
      debugPrint('cut out ${file.path}: $e');
      return null;
    }
  }

  /// A line or two about a species from the opening of its Wikipedia
  /// article (CC BY-SA), and the article's address; as the web plate does
  /// it (blurbFrom in bird_card.dart). Remembered 90 days in wiki.json, a
  /// missing article too. Null with no connection and nothing remembered.
  Future<({String text, String url})?> blurb(String sci) async {
    final wiki = _wiki ??= await _readMap('wiki.json');
    final kept = wiki[sci];
    if (kept is Map &&
        DateTime.now().millisecondsSinceEpoch - ((kept['t'] as num?) ?? 0) < 90 * 86400000) {
      return (text: (kept['text'] as String?) ?? '', url: (kept['url'] as String?) ?? '');
    }
    final url = 'https://en.wikipedia.org/api/rest_v1/page/summary/'
        '${Uri.encodeComponent(sci.replaceAll(' ', '_'))}?redirect=true';
    var text = '', page = '';
    try {
      final req = await _client.getUrl(Uri.parse(url));
      req.headers.set('Accept', 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 15));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 200) {
        final j = jsonDecode(body) as Map<String, dynamic>;
        final extract = j['extract'] as String?;
        if (j['type'] != 'disambiguation' && extract != null && extract.isNotEmpty) {
          text = blurbFrom(extract);
          page = ((j['content_urls'] as Map?)?['desktop'] as Map?)?['page'] as String? ?? '';
        }
      } else if (res.statusCode != 404) {
        return null;
      }
    } catch (_) {
      return null;
    }
    wiki[sci] = {'t': DateTime.now().millisecondsSinceEpoch, 'text': text, 'url': page};
    File('${dir.path}/wiki.json').writeAsString(jsonEncode(wiki)).catchError((Object e) {
      debugPrint('wiki: $e');
      return File('');
    });
    return (text: text, url: page);
  }

  /// Use [c] for a species from now on (its card's choice), and say what it is.
  Future<PlateArt?> choose(String sci, PlateCandidate c, PlateStyle style) {
    _choices[sci] = c.toJson();
    File('${dir.path}/choices.json').writeAsString(jsonEncode(_choices)).catchError((Object e) {
      debugPrint('choices: $e');
      return File('');
    });
    _asked.removeWhere((key, _) => key.endsWith('|$sci'));
    return _asked['${style.name}|$sci'] =
        load(c, style).then<PlateArt?>((a) => a).catchError((Object e) {
      debugPrint('plate $sci: $e');
      return null;
    });
  }

  static String _slug(String name) => name.trim().toLowerCase().replaceAll(' ', '-');

  Future<void> _loadManifest() async {
    try {
      final m = await _json('$_art/artwork/classic/manifest.json', 'manifest.json') as Map<String, dynamic>;
      final keys = m.keys.toList()
        ..sort((a, b) => a.length != b.length ? a.length - b.length : a.compareTo(b));
      final name = RegExp(r'^birds/(.+?)(?:-(\d+))?\.(webp|png)$');
      for (final key in keys) {
        final mm = name.firstMatch(key);
        if (mm == null) continue;
        (_cutouts[mm.group(1)!] ??= []).add(key);
        final info = m[key];
        if (info is Map) {
          if (info['source'] is String) _cutoutSource[key] = info['source'] as String;
          if (info['url'] is String) _cutoutPage[key] = info['url'] as String;
        }
      }
    } catch (e) {
      debugPrint('cut-outs: $e');
    }
    try {
      _alias = await _json('$_art/birdnet_aliases.json', 'aliases.json') as Map<String, dynamic>;
    } catch (_) {}
  }

  /// What Commons has for a species, best first. The species' own
  /// illustrations category, then its genus', then its family's (mammals).
  Future<List<PlateCandidate>> _commonsPlates(String sci, String common) async {
    // kept apart when skulls, wings and eggs are offered, as the page does
    final key = '${parts ? 'p.' : ''}$sci';
    final had = _found[key];
    final now = DateTime.now().millisecondsSinceEpoch;
    if (had is Map && had['v'] is List && now - ((had['t'] as num?) ?? 0) < 30 * 86400000) {
      return [
        for (final v in had['v'] as List)
          if (v is Map) PlateCandidate.fromJson(v.cast<String, dynamic>())
      ];
    }
    final genus = sci.split(RegExp(r'\s+')).first;
    var best = <PlateCandidate>[];
    final family = _family[genus];
    for (final (name, kin) in [
      (sci, ''),
      (genus, ' A plate of the same genus.'),
      if (family != null) (family, ' A plate of the same family.'),
    ]) {
      for (final cat in ['$name (illustrations)', '$name illustrations']) {
        best = await _commonsCategory(cat, sci, common, kin);
        if (best.isNotEmpty) break;
      }
      if (best.isNotEmpty) break;
    }
    _found[key] = {
      't': now,
      'v': [for (final c in best) c.toJson()]
    };
    try {
      await File('${dir.path}/found.json').writeAsString(jsonEncode(_found));
    } catch (_) {}
    return best;
  }

  Future<List<PlateCandidate>> _commonsCategory(String cat, String sci, String common, String kin) async {
    final u = '$_commons/w/api.php?format=json&action=query&generator=categorymembers&gcmtype=file'
        '&gcmlimit=50&prop=imageinfo&iiprop=url|size|mime&iiurlwidth=500'
        '&gcmtitle=${Uri.encodeQueryComponent('Category:$cat')}';
    final j = jsonDecode(utf8.decode(await _bytes(u)));
    final pages = (j is Map ? j['query'] : null) is Map ? (j['query']['pages'] as Map?) : null;
    if (pages == null) return [];
    final scored = <(double, PlateCandidate)>[];
    for (final p in pages.values) {
      final ii = (p['imageinfo'] as List?)?.firstOrNull;
      if (ii is! Map) continue;
      final mime = ii['mime'] as String? ?? '';
      if (!RegExp(r'^image/(jpeg|png|tiff)$').hasMatch(mime)) continue;
      if (((ii['width'] as num?) ?? 0) < 400 || ii['thumburl'] is! String) continue;
      final title = (p['title'] as String).replaceFirst(RegExp(r'^File:'), '');
      final score = scorePlate(title, sci, common, wide: kin.isNotEmpty, parts: parts);
      if (score < 0) continue;
      scored.add((
        score,
        PlateCandidate(ii['thumburl'] as String,
            ready: false,
            credit: '${title.replaceFirst(RegExp(r'\.\w+$'), '')}. Wikimedia Commons.$kin',
            page: ii['descriptionurl'] as String?)
      ));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final s in scored.take(12)) s.$2];
  }

  /// A plate of a part rather than the whole creature: the page's
  /// PLATE_PART. Naming the kinds leaves room to ask for one later.
  static const plateParts = <(String, String)>[
    ('skull', r'\bskulls?\b|\bskelet|\bcrania?\b|\bcranium\b'),
    ('teeth', r'\bteeth\b|\btooth\b|dentition'),
    ('anatomy', r'\bbrains?\b|viscera|anatom|dissect'),
    ('wing', r'\bwings?\b|\bfeathers?\b|\bplumes?\b'),
    ('foot', r'\bfoot\b|\bfeet\b|\bclaws?\b|\btalons?\b'),
    ('head', r'\bheads?\b|\bkop\b|\beyes?\b'),
    ('egg', r'\beggs?\b|\bnests?\b'),
  ];

  /// Which part a file's title says it shows, or '' for the whole creature.
  static String plateKind(String title) {
    for (final (kind, re) in plateParts) {
      if (RegExp(re, caseSensitive: false).hasMatch(title)) return kind;
    }
    return '';
  }

  /// How well a Commons file suits the plate: -1 to pass it over. The web
  /// page's scoreCandidate, line for line. A plate of a part (skull, wing,
  /// egg...) is passed over unless [parts] (Settings: skulls, wings and
  /// eggs), and then offered but never chosen first.
  @visibleForTesting
  static double scorePlate(String title, String sci, String common, {bool wide = false, bool parts = false}) {
    final t = title.replaceFirst(RegExp(r'^File:'), '');
    final low = t.toLowerCase(), squashed = low.replaceAll(RegExp(r'[\s_-]'), '');
    bool has(String re, [String? s]) => RegExp(re, caseSensitive: false).hasMatch(s ?? t);
    if (has(r'crossley|\bmap\b|stamp|mural|distribution|taxiderm|\.svg$|\.ogg$|\.pdf$|\.webm$| & ')) return -1;
    final kind = plateKind(t);
    if (kind.isNotEmpty && !parts) return -1;
    var s = 0.0;
    if (has(r'albin|selby|frivald|bewick|edwards|donovan|lewin|martinet|natural history of birds|nederlandsche vogelen')) {
      s += 100; // figures on plain paper
    } else if (has('buffon')) {
      s += has('oiseaux|birds') ? 100 : 55; // he ran to mammals too, on busier pages
    } else if (has('keulemans onze vogels')) {
      s += 90;
    } else if (has('keulemans')) {
      s += 80;
    } else if (has('naumann')) {
      s += 75;
    } else if (RegExp(r'^[A-Z][a-z]+ [a-z]+ 18\d\d\.jpe?g$').hasMatch(t)) {
      s += 70;
    } else if (has('gould')) {
      s += 60;
    } else if (has('lilford|thorburn')) {
      s += 55;
    } else if (has('audubon')) {
      s += 55;
    } else if (has(r'jardine|naturalist.?s library|british quadrupeds|macgillivray')) {
      s += 60;
    } else if (has(r'british mammals|\bdobson\b|chiroptera')) {
      s += 55;
    } else if (has('brehm|mivart|lydekker|joseph wolf|harrison weir|royal natural history')) {
      s += 50; // the same age, drawing animals
    } else if (has('wellcome|engraving|lithograph')) {
      s += 40;
    } else if (has('zwarts')) {
      s += 30;
    } else if (has('iconographia zoologica')) {
      s += 20;
    }
    // Which animal the plate is of matters more than who drew it: a famous
    // hand on the wrong creature is no use here.
    final name = common.toLowerCase().replaceFirst(RegExp(r'\s*/.*$'), '').trim();
    final genus = sci.split(RegExp(r'\s+')).first.toLowerCase();
    if (squashed.contains(sci.toLowerCase().replaceAll(RegExp(r'\s'), ''))) {
      s += wide ? 150 : 50;
    } else if (name.isNotEmpty && squashed.contains(name.replaceAll(RegExp(r'[\s_-]'), ''))) {
      s += wide ? 120 : 25;
    } else if (wide && genus.length > 5 && low.contains(genus.substring(0, 6))) {
      s += 40;
    }
    if (has(' (and|et|und) ', low)) s -= 35; // two creatures to a page, as a rule
    s = s < 0 ? 0 : s; // only the list above throws a plate out
    return kind.isNotEmpty ? s / 100 : s; // a part is offered, never chosen first
  }

  /// Commons files much of the older work beyond birds by genus or by
  /// family; this is the way back up to them (the page's FAMILY).
  static const _family = {
    'Pipistrellus': 'Vespertilionidae', 'Myotis': 'Vespertilionidae', 'Nyctalus': 'Vespertilionidae',
    'Plecotus': 'Vespertilionidae', 'Eptesicus': 'Vespertilionidae', 'Barbastella': 'Vespertilionidae',
    'Rhinolophus': 'Rhinolophidae',
    'Vulpes': 'Canidae', 'Canis': 'Canidae',
    'Meles': 'Mustelidae', 'Martes': 'Mustelidae', 'Mustela': 'Mustelidae', 'Lutra': 'Mustelidae',
    'Erinaceus': 'Erinaceidae', 'Talpa': 'Talpidae', 'Sorex': 'Soricidae',
    'Sciurus': 'Sciuridae', 'Oryctolagus': 'Leporidae', 'Lepus': 'Leporidae',
    'Capreolus': 'Cervidae', 'Cervus': 'Cervidae', 'Dama': 'Cervidae', 'Muntiacus': 'Cervidae',
    'Apodemus': 'Muridae', 'Rattus': 'Muridae', 'Microtus': 'Cricetidae',
    'Rana': 'Ranidae', 'Bufo': 'Bufonidae', 'Pelophylax': 'Ranidae',
  };

  // ---- fetching, once ------------------------------------------------------

  /// The picture at [url], from the device if it is here already.
  Future<File> _fetch(String url) async {
    final file = File('${dir.path}/${_name(url)}');
    if (await file.exists() && await file.length() > 0) return file;
    final part = File('${file.path}.part');
    await part.writeAsBytes(await _bytes(url), flush: true);
    return part.rename(file.path);
  }

  /// JSON kept a week under [name]; an older copy is better than none.
  Future<dynamic> _json(String url, String name) async {
    final file = File('${dir.path}/$name');
    final fresh = await file.exists() &&
        DateTime.now().difference(await file.lastModified()) < const Duration(days: 7);
    if (!fresh) {
      try {
        await file.writeAsBytes(await _bytes(url), flush: true);
      } catch (e) {
        if (!await file.exists()) rethrow;
      }
    }
    return jsonDecode(await file.readAsString());
  }

  Future<Uint8List> _bytes(String url) async {
    final req = await _client.getUrl(Uri.parse(url));
    final res = await req.close().timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      await res.drain<void>();
      throw HttpException('${res.statusCode}', uri: Uri.parse(url));
    }
    final all = BytesBuilder(copy: false);
    await for (final chunk in res) {
      all.add(chunk);
    }
    return all.takeBytes();
  }

  /// A file name for a URL: two FNV-1a hashes of it, in hex.
  static String _name(String url) {
    int fnv(int seed) {
      var h = seed;
      for (final c in url.codeUnits) {
        h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
      }
      return h;
    }

    String hex(int v) => v.toRadixString(16).padLeft(8, '0');
    return '${hex(fnv(0x811C9DC5))}${hex(fnv(0x9747B28C))}';
  }

  void close() => _client.close(force: true);
}

// compute() takes one argument: the pixels and their size.
CutOut? _cutOutOnIsolate((Uint8List, int, int) a) => cutOutFigure(a.$1, a.$2, a.$3);

/// The page's blurbFrom: the second and third sentences of a Wikipedia
/// summary (the first is mostly other names), or just the second when the
/// two run past 340 characters.
String blurbFrom(String t) {
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  final found = RegExp(r'.+?[a-z\)\]"’”]\.(?=\s+[A-Z]|$)').allMatches(t).map((m) => m.group(0)!.trim()).toList();
  final parts = found.isEmpty ? [t] : found;
  if (parts.length < 2) return parts.first;
  final two = parts[1] + (parts.length > 2 ? ' ${parts[2]}' : '');
  return two.length <= 340 ? two : parts[1];
}
