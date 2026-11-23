import 'dart:convert';
import 'dart:io';

/// GBIF's number for a species, from its scientific name (GBIF's species
/// match), for its map of where the species has been recorded. Kept for the
/// run; null when GBIF has no confident match.
class BirdRecords {
  static final Map<String, Future<int?>> _keys = {};

  static Future<int?> keyFor(String sci) => _keys[sci] ??= _match(sci).catchError((Object _) {
        _keys.remove(sci); // ask again next time
        return null;
      });

  static Future<int?> _match(String sci) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.https('api.gbif.org', '/v1/species/match', {'name': sci, 'kingdom': 'Animalia'}));
      req.headers.set(HttpHeaders.userAgentHeader, 'Birdsong/0.1 github.com/dopeytree/birdsong');
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw HttpException('${res.statusCode}');
      return keyOf(jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>);
    } finally {
      client.close();
    }
  }

  /// The species' number from GBIF's match answer: its accepted name's, or
  /// its own; null when the match is only a guess (NONE, or not a species).
  static int? keyOf(Map<String, dynamic> j) {
    if (j['matchType'] == 'NONE' || j['matchType'] == null) return null;
    final rank = j['rank'];
    if (rank != null && rank != 'SPECIES' && rank != 'SUBSPECIES') return null;
    return (j['speciesKey'] ?? j['acceptedUsageKey'] ?? j['usageKey']) as int?;
  }

  /// GBIF's map tiles of where species [key] has been recorded: hexagons,
  /// darker where there are more records.
  static String tiles(int key) => 'https://api.gbif.org/v2/map/occurrence/density/{z}/{x}/{y}@1x.png'
      '?taxonKey=$key&bin=hex&hexPerTile=48&style=classic-noborder.poly';
}
