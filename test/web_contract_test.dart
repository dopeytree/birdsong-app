import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app serves the Birdsong web page unchanged and hooks into it at serve
/// time. This fails the build if a new copy of the page (tool/sync_web.py)
/// has lost something those hooks need. See tool/web_contract.json.
void main() {
  final html = File('assets/web/index.html').readAsStringSync();
  final contract =
      jsonDecode(File('tool/web_contract.json').readAsStringSync()) as Map<String, dynamic>;

  test('page still has every hook the app uses', () {
    final missing = [
      for (final h in contract['hooks'] as List)
        if (!html.contains(h['find'] as String)) '${h['find']}  <- ${h['used_by']}',
    ];
    expect(missing, isEmpty, reason: 'Update lib/server/local_server.dart and tool/web_contract.json');
  });

  test('listen mode answers every BirdNET-Go call the page makes', () {
    final served = (contract['endpoints'] as List).cast<String>();
    final used = RegExp(r'/api/v2/[A-Za-z0-9_/]*[A-Za-z0-9_/]')
        .allMatches(html)
        .map((m) => m.group(0)!)
        .toSet();
    final unanswered = [
      for (final u in used)
        if (!served.any((e) =>
            u == e || (e.endsWith('/') && u.startsWith(e)) || (u.endsWith('/') && e.startsWith(u))))
          u,
    ];
    expect(unanswered, isEmpty, reason: 'Add them to lib/server/local_api.dart');
  });
}
