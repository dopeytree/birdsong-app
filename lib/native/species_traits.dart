import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'bird_records.dart';

/// Biological traits for one species, fetched lazily from open sources
/// (Wikidata for body mass / length / wingspan / IUCN conservation status;
/// GBIF for global occurrence count) and cached on disk so each species is
/// only ever looked up once.
class SpeciesTrait {
  const SpeciesTrait({
    this.massGrams,
    this.lengthCm,
    this.wingspanCm,
    this.iucnRank,
    this.gbifCount,
  });

  final double? massGrams;
  final double? lengthCm;
  final double? wingspanCm;

  /// Higher = more threatened: CR=5, EN=4, VU=3, NT=2, LC=1, unknown=null.
  final int? iucnRank;

  /// Total occurrence records in GBIF (fewer = rarer).
  final int? gbifCount;

  /// Comparable size score (prefers body mass in grams; falls back to length
  /// or wingspan scaled into an approximate mass order so raptors/swans sit at
  /// one end and wrens/goldcrests at the other).
  double? get sizeScore {
    if (massGrams != null && massGrams! > 0) return massGrams!;
    if (lengthCm != null && lengthCm! > 0) return lengthCm! * lengthCm! * lengthCm! * 0.008;
    if (wingspanCm != null && wingspanCm! > 0) return wingspanCm! * wingspanCm! * 0.05;
    return null;
  }

  /// Comparable rarity score: lower = rarer (threatened IUCN species first,
  /// then fewest GBIF records). Null when not yet fetched.
  double? get rarityScore {
    if (gbifCount == null && iucnRank == null) return null;
    // Threat tier (CR=0 .. LC=4, unknown=4.5) dominates, then log occurrence count.
    final tier = iucnRank != null ? (5 - iucnRank!).toDouble() : 4.5;
    final occ = (gbifCount ?? 10000000).clamp(0, 100000000).toDouble();
    return tier * 1e9 + occ;
  }

  Map<String, dynamic> toJson() => {
        if (massGrams != null) 'massGrams': massGrams,
        if (lengthCm != null) 'lengthCm': lengthCm,
        if (wingspanCm != null) 'wingspanCm': wingspanCm,
        if (iucnRank != null) 'iucnRank': iucnRank,
        if (gbifCount != null) 'gbifCount': gbifCount,
      };

  static SpeciesTrait fromJson(Map<String, dynamic> j) => SpeciesTrait(
        massGrams: (j['massGrams'] as num?)?.toDouble(),
        lengthCm: (j['lengthCm'] as num?)?.toDouble(),
        wingspanCm: (j['wingspanCm'] as num?)?.toDouble(),
        iucnRank: (j['iucnRank'] as num?)?.toInt(),
        gbifCount: (j['gbifCount'] as num?)?.toInt(),
      );
}

/// On-disk cached trait & rarity lookup for species sorting.
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

  /// Request biological size & IUCN data from Wikidata for [scis].
  void wantSizeAndIucn(Iterable<String> scis) {
    var added = false;
    for (final sci in scis) {
      final cur = _cache[sci];
      if ((cur?.sizeScore != null && cur?.iucnRank != null) || _wikiAsked.contains(sci)) continue;
      _wikiAsked.add(sci);
      _wikiQueue.add(sci);
      added = true;
    }
    if (added && !_wikiBusy) unawaited(_drainWiki());
  }

  /// Request real occurrence counts from GBIF (and IUCN from Wikidata) for [scis].
  void wantRarity(Iterable<String> scis) {
    wantSizeAndIucn(scis);
    var added = false;
    for (final sci in scis) {
      if (_cache[sci]?.gbifCount != null || _gbifAsked.contains(sci)) continue;
      _gbifAsked.add(sci);
      _gbifQueue.add(sci);
      added = true;
    }
    if (added && !_gbifBusy) unawaited(_drainGbif());
  }

  Future<void> _drainWiki() async {
    _wikiBusy = true;
    try {
      while (_wikiQueue.isNotEmpty) {
        final batch = _wikiQueue.take(40).toList();
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
    // Query mass (P2067), length (P2043), wingspan (P2050), and IUCN status (P141)
    // in normalized SI units (grams/metres via psv/psn).
    final sparql = '''
SELECT ?sci
  (SAMPLE(?massKg) AS ?mass)
  (SAMPLE(?lenM) AS ?len)
  (SAMPLE(?spanM) AS ?span)
  (SAMPLE(?iucn) AS ?status)
WHERE {
  VALUES ?sci { $values }
  ?item wdt:P225 ?sci .
  OPTIONAL { ?item p:P2067/psn:P2067/wikibase:quantityAmount ?massKg . }
  OPTIONAL { ?item p:P2043/psn:P2043/wikibase:quantityAmount ?lenM . }
  OPTIONAL { ?item p:P2050/psn:P2050/wikibase:quantityAmount ?spanM . }
  OPTIONAL { ?item wdt:P141 ?iucn . }
}
GROUP BY ?sci
''';
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final uri = Uri.https('query.wikidata.org', '/sparql', {'format': 'json', 'query': sparql});
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, 'BirdsongApp/0.1 (https://github.com/dopeytree/birdsongs.ai)');
      req.headers.set(HttpHeaders.acceptHeader, 'application/sparql-results+json');
      final res = await req.close().timeout(const Duration(seconds: 20));
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
        // Wikidata SI normalized mass is in kg -> convert to grams; lengths are in m -> cm.
        final massKg = numOf('mass');
        final lenM = numOf('len');
        final spanM = numOf('span');
        final iucnUrl = (row['status'] as Map?)?['value'] as String?;
        final iucn = _parseIucn(iucnUrl);
        final prev = _cache[sci];
        _cache[sci] = SpeciesTrait(
          massGrams: massKg != null ? massKg * 1000.0 : prev?.massGrams,
          lengthCm: lenM != null ? lenM * 100.0 : prev?.lengthCm,
          wingspanCm: spanM != null ? spanM * 100.0 : prev?.wingspanCm,
          iucnRank: iucn ?? prev?.iucnRank,
          gbifCount: prev?.gbifCount,
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
    if (url.endsWith('Q219127')) return 5; // Critically Endangered (CR)
    if (url.endsWith('Q11394')) return 4; // Endangered (EN)
    if (url.endsWith('Q278113')) return 3; // Vulnerable (VU)
    if (url.endsWith('Q719675')) return 2; // Near Threatened (NT)
    if (url.endsWith('Q211005')) return 1; // Least Concern (LC)
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
                final key = await BirdRecords.keyFor(sci);
                if (key == null) return;
                final uri = Uri.https('api.gbif.org', '/v1/occurrence/count', {'taxonKey': '$key'});
                final req = await client.getUrl(uri);
                req.headers.set(HttpHeaders.userAgentHeader, 'Birdsong/0.1 github.com/dopeytree/birdsong');
                final res = await req.close().timeout(const Duration(seconds: 12));
                if (res.statusCode != 200) return;
                final count = int.tryParse((await res.transform(utf8.decoder).join()).trim());
                if (count == null) return;
                final prev = _cache[sci];
                _cache[sci] = SpeciesTrait(
                  massGrams: prev?.massGrams,
                  lengthCm: prev?.lengthCm,
                  wingspanCm: prev?.wingspanCm,
                  iucnRank: prev?.iucnRank,
                  gbifCount: count,
                );
                changed = true;
              } catch (e) {
                debugPrint('gbif count $sci: $e');
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
