import 'dart:convert';
import 'dart:io';

import 'package:birdsong_app/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async => root = await Directory.systemTemp.createTemp('birdsong_settings_'));
  tearDown(() async => root.delete(recursive: true));

  Future<Settings> loadWith(Map<String, dynamic> j) async {
    await File('${root.path}/settings.json').writeAsString(jsonEncode(j));
    return Settings.load(root);
  }

  test('the plate modes run a to g', () {
    expect([for (var i = 1; i <= plateModes.length; i++) plateLetter(i)].join(), 'abcdefg');
    expect(plateModes.map((m) => m.key).toList(),
        ['calls', 'noindex', 'index', 'latest', 'top', 'time', 'equal']);
  });

  test('a mode is kept by its key', () async {
    final s = await loadWith({'plateView': 'top'});
    expect(plateModes[s.plateMode - 1].key, 'top');
    expect(s.toJson()['plateView'], 'top');
  });

  test('a number saved in the first order finds the same mode', () async {
    // 5 was the index alone; it is c now.
    final s = await loadWith({'plateMode': 5});
    expect(plateLetter(s.plateMode), 'c');
    // 2 was recent ramblings; it is f now.
    expect(plateLetter((await loadWith({'plateMode': 2})).plateMode), 'f');
  });
}
