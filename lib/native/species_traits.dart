import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Circular mean hour of day (`0.0` to `< 24.0`) from a 24-hour count histogram.
/// Uses circular statistics so nocturnal birds active at 23:00 and 01:00 average
/// cleanly to ~00:00 instead of 12:00 noon. Returns null if [hours] has no calls.
double? circularMeanHour(List<int> hours) {
  if (hours.length < 24) return null;
  var sinSum = 0.0, cosSum = 0.0, total = 0;
  for (var h = 0; h < 24; h++) {
    final c = hours[h];
    if (c <= 0) continue;
    // Use the middle of each hour bin (h + 0.5).
    final rad = ((h + 0.5) / 24.0) * 2.0 * math.pi;
    sinSum += c * math.sin(rad);
    cosSum += c * math.cos(rad);
    total += c;
  }
  if (total == 0) return null;
  var angle = math.atan2(sinSum, cosSum);
  if (angle < 0) angle += 2.0 * math.pi;
  return (angle / (2.0 * math.pi)) * 24.0;
}

/// Format a mean activity hour (`0..24`) for the bird card, e.g. `around 06:30 (dawn)`.
String formatActiveHour(double hour) {
  final totalMin = ((hour % 24) * 60).round() % (24 * 60);
  final h = totalMin ~/ 60;
  final m = (totalMin % 60 ~/ 5) * 5; // nearest 5 min reads naturally
  final hh = h.toString().padLeft(2, '0');
  final mm = m.toString().padLeft(2, '0');
  final band = switch (h) {
    >= 4 && < 8 => 'dawn',
    >= 8 && < 12 => 'morning',
    >= 12 && < 17 => 'afternoon',
    >= 17 && < 21 => 'dusk',
    _ => 'night',
  };
  return 'around $hh:$mm ($band)';
}

/// Format body mass in grams cleanly (e.g. `18 g`, `420 g`, `1.4 kg`).
String formatWeight(double grams) {
  if (grams >= 1000) return '${(grams / 1000).toStringAsFixed(1)} kg';
  if (grams >= 10) return '${grams.round()} g';
  return '${grams.toStringAsFixed(1)} g';
}

/// Format wingspan in cm cleanly (e.g. `22 cm`, `135 cm`).
String formatWingspan(double cm) {
  if (cm >= 10) return '${cm.round()} cm';
  return '${cm.toStringAsFixed(1)} cm';
}

/// Biological traits for one species, fetched lazily from open sources
/// (Wikidata for weight, wingspan, length, native range, IUCN status; GBIF for
/// order, family, and global occurrence count) and cached on disk.
class SpeciesTrait {
  const SpeciesTrait({
    this.massGrams,
    this.lengthCm,
    this.wingspanCm,
    this.iucnRank,
    this.gbifCount,
    this.order,
    this.family,
    this.region,
  });

  final double? massGrams;
  final double? lengthCm;
  final double? wingspanCm;

  /// Higher = more threatened: CR=5, EN=4, VU=3, NT=2, LC=1, unknown=null.
  final int? iucnRank;

  /// Total occurrence records in GBIF (fewer = rarer).
  final int? gbifCount;

  /// Taxonomic order and family (from GBIF), e.g. Passeriformes / Turdidae.
  final String? order;
  final String? family;

  /// Native range / endemic region (from Wikidata), e.g. "Europe", "Palearctic".
  final String? region;

  /// Comparable rarity score: lower = rarer (threatened IUCN species first,
  /// then fewest GBIF records). Null when not yet fetched.
  double? get rarityScore {
    if (gbifCount == null && iucnRank == null) return null;
    final tier = iucnRank != null ? (5 - iucnRank!).toDouble() : 4.5;
    final occ = (gbifCount ?? 10000000).clamp(0, 100000000).toDouble();
    return tier * 1e9 + occ;
  }

  /// Taxonomic sort key grouping related birds together (Order | Family | Sci).
  String taxonomicKey(String sci) {
    final o = (order ?? 'zzz').toLowerCase();
    final f = (family ?? 'zzz').toLowerCase();
    return '$o|$f|${sci.toLowerCase()}';
  }

  Map<String, dynamic> toJson() => {
        if (massGrams != null) 'massGrams': massGrams,
        if (lengthCm != null) 'lengthCm': lengthCm,
        if (wingspanCm != null) 'wingspanCm': wingspanCm,
        if (iucnRank != null) 'iucnRank': iucnRank,
        if (gbifCount != null) 'gbifCount': gbifCount,
        if (order != null) 'order': order,
        if (family != null) 'family': family,
        if (region != null) 'region': region,
      };

  static SpeciesTrait fromJson(Map<String, dynamic> j) => SpeciesTrait(
        massGrams: (j['massGrams'] as num?)?.toDouble(),
        lengthCm: (j['lengthCm'] as num?)?.toDouble(),
        wingspanCm: (j['wingspanCm'] as num?)?.toDouble(),
        iucnRank: (j['iucnRank'] as num?)?.toInt(),
        gbifCount: (j['gbifCount'] as num?)?.toInt(),
        order: j['order'] as String?,
        family: j['family'] as String?,
        region: j['region'] as String?,
      );
}

/// On-disk cached trait, taxonomy & rarity lookup for species sorting and cards.
class SpeciesTraits extends ChangeNotifier {
  SpeciesTraits._(this._file);

  final File _file;
  final Map<String, SpeciesTrait> _cache = {};
  final Set<String> _wikiAsked = {};
  final Set<String> _gbifAsked = {};
  bool _wikiBusy = false;
  bool _gbifBusy = false;
  final List<String> _wikiQueue = [];
  final List<String> _gbifQueue = [];
  Timer? _saveTimer;

  static Future<SpeciesTraits> open() async {
    final base = await getApplicationCacheDirectory();
    final file = File('${base.path}/species_traits.json');
    final store = SpeciesTraits._(file);
    try {
      if (await file.exists()) {
        final raw = jsonDecode(await file.readAsString());
        if (raw is Map) {
          for (final e in raw.entries) {
            if (e.key is String && e.value is Map) {
              store._cache[e.key as String] =
                  SpeciesTrait.fromJson((e.value as Map).cast<String, dynamic>());
            }
          }
        }
      }
    } catch (e) {
      debugPrint('species_traits read: $e');
    }
    return store;
  }

  SpeciesTrait? of(String sci) => _cache[sci];

  /// Fetch all available Wikidata + GBIF fields for [scis] (used by BirdCard).
  void wantAll(Iterable<String> scis) {
    wantWikidata(scis);
    wantGbif(scis);
  }

  /// Fetch weight, wingspan, length, region & IUCN status from Wikidata.
  void wantWikidata(Iterable<String> scis) {
    var added = false;
    for (final sci in scis) {
      final cur = _cache[sci];
      final complete = cur != null &&
          cur.massGrams != null &&
          cur.wingspanCm != null &&
          cur.region != null &&
          cur.iucnRank != null;
      if (complete || _wikiAsked.contains(sci)) continue;
      _wikiAsked.add(sci);
      _wikiQueue.add(sci);
      added = true;
    }
    if (added && !_wikiBusy) unawaited(_drainWiki());
  }

  /// Fetch taxonomic order, family & occurrence count from GBIF.
  void wantGbif(Iterable<String> scis) {
    var added = false;
    for (final sci in scis) {
      final cur = _cache[sci];
      if ((cur?.gbifCount != null && cur?.family != null) || _gbifAsked.contains(sci)) continue;
      _gbifAsked.add(sci);
      _gbifQueue.add(sci);
      added = true;
    }
    if (added && !_gbifBusy) unawaited(_drainGbif());
  }

  void wantRarity(Iterable<String> scis) => wantAll(scis);
  void wantSizeAndIucn(Iterable<String> scis) => wantWikidata(scis);

  Future<void> _drainWiki() async {
    _wikiBusy = true;
    try {
      while (_wikiQueue.isNotEmpty) {
        final batch = _wikiQueue.take(35).toList();
        _wikiQueue.removeRange(0, batch.length);
        await _fetchWikidataBatch(batch);
      }
    } finally {
      _wikiBusy = false;
    }
  }

  Future<void> _fetchWikidataBatch(List<String> scis) async {
    final values = scis
        .map((s) => '"${s.replaceAll(r'\', '').replaceAll('"', '')}"')
        .join(' ');
    final sparql = '''
SELECT ?sci
  (SAMPLE(?massKg) AS ?mass)
  (SAMPLE(?lenM) AS ?len)
  (SAMPLE(?spanM) AS ?span)
  (SAMPLE(?iucn) AS ?status)
  (SAMPLE(?rangeLabel) AS ?range)
  (SAMPLE(?endemicLabel) AS ?endemic)
WHERE {
  VALUES ?sci { $values }
  ?item wdt:P225 ?sci .
  OPTIONAL { ?item p:P2067/psn:P2067/wikibase:quantityAmount ?massKg . }
  OPTIONAL { ?item p:P2043/psn:P2043/wikibase:quantityAmount ?lenM . }
  OPTIONAL { ?item p:P2050/psn:P2050/wikibase:quantityAmount ?spanM . }
  OPTIONAL { ?item wdt:P141 ?iucn . }
  OPTIONAL {
    ?item wdt:P9714 ?r .
    ?r rdfs:label ?rangeLabel .
    FILTER(LANG(?rangeLabel) = "en")
  }
  OPTIONAL {
    ?item wdt:P183 ?e .
    ?e rdfs:label ?endemicLabel .
    FILTER(LANG(?endemicLabel) = "en")
  }
}
GROUP BY ?sci
''';
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final uri = Uri.https('query.wikidata.org', '/sparql', {'format': 'json', 'query': sparql});
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, 'BirdsongApp/0.1 (https://github.com/dopeytree/birdsongs.ai)');
      req.headers.set(HttpHeaders.acceptHeader, 'application/sparql-results+json');
      final res = await req.close().timeout(const Duration(seconds: 22));
      if (res.statusCode != 200) return;
      final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final bindings = ((body['results'] as Map?)?['bindings'] as List?) ?? const [];
      var changed = false;
      for (final row in bindings) {
        if (row is! Map) continue;
        final sci = (row['sci'] as Map?)?['value'] as String?;
        if (sci == null) continue;
        double? numOf(String k) {
          final v = (row[k] as Map?)?['value'];
          return v is String ? double.tryParse(v) : null;
        }
        String? strOf(String k) {
          final v = (row[k] as Map?)?['value'];
          return v is String && v.trim().isNotEmpty ? v.trim() : null;
        }

        final massKg = numOf('mass');
        final lenM = numOf('len');
        final spanM = numOf('span');
        final iucn = _parseIucn(strOf('status'));
        final region = strOf('endemic') ?? strOf('range');
        final prev = _cache[sci];
        _cache[sci] = SpeciesTrait(
          massGrams: massKg != null ? massKg * 1000.0 : prev?.massGrams,
          lengthCm: lenM != null ? lenM * 100.0 : prev?.lengthCm,
          wingspanCm: spanM != null ? spanM * 100.0 : prev?.wingspanCm,
          iucnRank: iucn ?? prev?.iucnRank,
          gbifCount: prev?.gbifCount,
          order: prev?.order,
          family: prev?.family,
          region: region ?? prev?.region,
        );
        changed = true;
      }
      if (changed) {
        _scheduleSave();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('wikidata traits: $e');
    } finally {
      client.close();
    }
  }

  int? _parseIucn(String? url) {
    if (url == null) return null;
    if (url.endsWith('Q219127')) return 5; // CR
    if (url.endsWith('Q11394')) return 4; // EN
    if (url.endsWith('Q278113')) return 3; // VU
    if (url.endsWith('Q719675')) return 2; // NT
    if (url.endsWith('Q211005')) return 1; // LC
    return null;
  }

  Future<void> _drainGbif() async {
    _gbifBusy = true;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      while (_gbifQueue.isNotEmpty) {
        final batch = _gbifQueue.take(6).toList();
        _gbifQueue.removeRange(0, batch.length);
        var changed = false;
        await Future.wait([
          for (final sci in batch)
            () async {
              try {
                final matchUri =
                    Uri.https('api.gbif.org', '/v1/species/match', {'name': sci, 'kingdom': 'Animalia'});
                final mReq = await client.getUrl(matchUri);
                mReq.headers.set(HttpHeaders.userAgentHeader, 'Birdsong/0.1 github.com/dopeytree/birdsong');
                final mRes = await mReq.close().timeout(const Duration(seconds: 12));
                if (mRes.statusCode != 200) return;
                final mJson = jsonDecode(await mRes.transform(utf8.decoder).join()) as Map<String, dynamic>;
                if (mJson['matchType'] == 'NONE' || mJson['matchType'] == null) return;
                final key = (mJson['speciesKey'] ?? mJson['acceptedUsageKey'] ?? mJson['usageKey']) as int?;
                final order = mJson['order'] as String?;
                final family = mJson['family'] as String?;
                int? count;
                if (key != null) {
                  final cUri = Uri.https('api.gbif.org', '/v1/occurrence/count', {'taxonKey': '$key'});
                  final cReq = await client.getUrl(cUri);
                  cReq.headers.set(HttpHeaders.userAgentHeader, 'Birdsong/0.1 github.com/dopeytree/birdsong');
                  final cRes = await cReq.close().timeout(const Duration(seconds: 12));
                  if (cRes.statusCode == 200) {
                    count = int.tryParse((await cRes.transform(utf8.decoder).join()).trim());
                  }
                }
                final prev = _cache[sci];
                _cache[sci] = SpeciesTrait(
                  massGrams: prev?.massGrams,
                  lengthCm: prev?.lengthCm,
                  wingspanCm: prev?.wingspanCm,
                  iucnRank: prev?.iucnRank,
                  gbifCount: count ?? prev?.gbifCount,
                  order: order ?? prev?.order,
                  family: family ?? prev?.family,
                  region: prev?.region,
                );
                changed = true;
              } catch (e) {
                debugPrint('gbif trait $sci: $e');
              }
            }(),
        ]);
        if (changed) {
          _scheduleSave();
          notifyListeners();
        }
      }
    } finally {
      client.close();
      _gbifBusy = false;
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () async {
      try {
        final out = {for (final e in _cache.entries) e.key: e.value.toJson()};
        await _file.writeAsString(jsonEncode(out));
      } catch (e) {
        debugPrint('species_traits save: $e');
      }
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
