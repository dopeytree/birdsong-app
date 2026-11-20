import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// A picture of one species, on this device.
class PlateArt {
  const PlateArt(this.file, {required this.ready, required this.credit, this.page});

  final File file;

  /// A transparent cut-out, drawn as it is. Otherwise a plate still on its
  /// paper, which the screen tints into the page (multiply with the paper).
  final bool ready;
  final String credit;

  /// Where the picture is described, for the card's credit.
  final String? page;
}

/// Finds a plate for a species and keeps it on the device, so each picture
/// is fetched once: the Fugleramme cut-outs first, then the engraved plates
/// on Wikimedia Commons, as the web page chooses them (a shorter version of
/// its scoreCandidate and commonsPlates).
///
/// Everything lives in the app's cache folder under plates/: the pictures,
/// the cut-outs' manifest (kept a week) and found.json, which remembers what
/// Commons answered for each species (kept 30 days).
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
    ..userAgent = 'BirdsongApp/0.1 (https://github.com/dopeytree/birdsong-app)';

  final Map<String, Future<PlateArt?>> _asked = {};
  Future<void>? _manifestLoad;
  final Map<String, List<String>> _cutouts = {}; // slug -> manifest keys, best first
  final Map<String, String> _cutoutSource = {}; // manifest key -> artist key
  final Map<String, String> _cutoutPage = {};
  Map<String, dynamic> _alias = {};
  Map<String, dynamic> _found = {};

  static Future<PlateLibrary> open() async {
    final base = await getApplicationCacheDirectory();
    final dir = Directory('${base.path}/plates');
    await dir.create(recursive: true);
    final lib = PlateLibrary._(dir);
    try {
      final f = File('${dir.path}/found.json');
      if (await f.exists()) lib._found = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {}
    return lib;
  }

  /// The plate for a species, or null when none was found (or there is no
  /// connection and it isn't on the device yet). Asked once a run.
  Future<PlateArt?> plateFor(String sci, String common) =>
      _asked[sci] ??= _find(sci, common).catchError((Object e) {
        debugPrint('plate $sci: $e');
        return null;
      });

  Future<PlateArt?> _find(String sci, String common) async {
    await (_manifestLoad ??= _loadManifest());
    final slug = _slug(sci);
    final aliased = _alias[sci];
    final keys = _cutouts[slug] ?? (aliased is String ? _cutouts[_slug(aliased)] : null);
    if (keys != null && keys.isNotEmpty) {
      final key = keys.first;
      final who = _artists[_cutoutSource[key]] ?? '';
      return PlateArt(
        await _fetch('$_art/artwork/classic/$key'),
        ready: true,
        credit: '${who.isEmpty ? '' : 'After $who. '}Cut-out from the Fugleramme project, CC BY-SA 4.0.',
        page: _cutoutPage[key],
      );
    }
    final hit = await _commonsPlate(sci, common);
    if (hit == null) return null;
    return PlateArt(await _fetch(hit['url'] as String),
        ready: false, credit: hit['credit'] as String, page: hit['page'] as String?);
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

  /// What Commons has for a species: {url, credit, page}, or null. The
  /// species' own illustrations category first, then its genus'.
  Future<Map<String, dynamic>?> _commonsPlate(String sci, String common) async {
    final had = _found[sci];
    final now = DateTime.now().millisecondsSinceEpoch;
    if (had is Map && now - ((had['t'] as num?) ?? 0) < 30 * 86400000) {
      final v = had['v'];
      return v is Map ? v.cast<String, dynamic>() : null;
    }
    final genus = sci.split(RegExp(r'\s+')).first;
    Map<String, dynamic>? best;
    for (final (name, kin) in [(sci, ''), (genus, ' A plate of the same genus.')]) {
      for (final cat in ['$name (illustrations)', '$name illustrations']) {
        best = await _commonsCategory(cat, sci, common, kin);
        if (best != null) break;
      }
      if (best != null) break;
    }
    _found[sci] = {'t': now, 'v': best};
    try {
      await File('${dir.path}/found.json').writeAsString(jsonEncode(_found));
    } catch (_) {}
    return best;
  }

  Future<Map<String, dynamic>?> _commonsCategory(String cat, String sci, String common, String kin) async {
    final u = '$_commons/w/api.php?format=json&action=query&generator=categorymembers&gcmtype=file'
        '&gcmlimit=50&prop=imageinfo&iiprop=url|size|mime&iiurlwidth=500'
        '&gcmtitle=${Uri.encodeQueryComponent('Category:$cat')}';
    final j = jsonDecode(utf8.decode(await _bytes(u)));
    final pages = (j is Map ? j['query'] : null) is Map ? (j['query']['pages'] as Map?) : null;
    if (pages == null) return null;
    Map<String, dynamic>? best;
    var bestScore = -1;
    for (final p in pages.values) {
      final ii = (p['imageinfo'] as List?)?.firstOrNull;
      if (ii is! Map) continue;
      final mime = ii['mime'] as String? ?? '';
      if (!RegExp(r'^image/(jpeg|png|tiff)$').hasMatch(mime)) continue;
      if (((ii['width'] as num?) ?? 0) < 400 || ii['thumburl'] is! String) continue;
      final title = (p['title'] as String).replaceFirst(RegExp(r'^File:'), '');
      final score = scorePlate(title, sci, common, wide: kin.isNotEmpty);
      if (score <= bestScore) continue;
      bestScore = score;
      best = {
        'url': ii['thumburl'],
        'page': ii['descriptionurl'],
        'credit': '${title.replaceFirst(RegExp(r'\.\w+$'), '')}. Wikimedia Commons.$kin',
      };
    }
    return best;
  }

  /// How well a Commons file suits the plate: -1 to pass it over. After the
  /// web page's scoreCandidate, without its "parts" (eggs, skulls) option.
  @visibleForTesting
  static int scorePlate(String title, String sci, String common, {bool wide = false}) {
    final low = title.toLowerCase(), squashed = low.replaceAll(RegExp(r'[\s_-]'), '');
    if (RegExp(r'crossley|\bmap\b|stamp|mural|distribution|taxiderm|\.svg$|\.ogg$|\.pdf$|\.webm$| & |\begg|skull|skeleton|\bnest\b')
        .hasMatch(low)) {
      return -1;
    }
    bool has(String re) => RegExp(re).hasMatch(low);
    var s = 0;
    if (has(r'albin|selby|frivald|bewick|edwards|donovan|lewin|martinet|natural history of birds|nederlandsche vogelen')) {
      s += 100; // figures on plain paper
    } else if (has('buffon')) {
      s += has('oiseaux|birds') ? 100 : 55;
    } else if (has('keulemans')) {
      s += 80;
    } else if (has('naumann')) {
      s += 75;
    } else if (has('gould|jardine|macgillivray')) {
      s += 60;
    } else if (has('lilford|thorburn|audubon')) {
      s += 55;
    } else if (has('brehm|lydekker|joseph wolf')) {
      s += 50;
    } else if (has('wellcome|engraving|lithograph')) {
      s += 40;
    }
    // Which animal it is matters more than who drew it.
    final name = common.toLowerCase().replaceFirst(RegExp(r'\s*/.*$'), '').trim();
    final genus = sci.split(RegExp(r'\s+')).first.toLowerCase();
    if (squashed.contains(sci.toLowerCase().replaceAll(' ', ''))) {
      s += wide ? 150 : 50;
    } else if (name.isNotEmpty && squashed.contains(name.replaceAll(RegExp(r'[\s_-]'), ''))) {
      s += wide ? 120 : 25;
    } else if (wide && genus.length > 5 && low.contains(genus.substring(0, 6))) {
      s += 40;
    }
    if (has(' (and|et|und) ')) s -= 35; // two creatures to a page, as a rule
    return s < 0 ? 0 : s;
  }

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
