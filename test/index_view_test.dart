import 'package:birdsong_app/native/index_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('seven names with room for six columns make four columns of two', () {
    // the page's own example (sizeIndex)
    final c = indexColumns(7, 6 * 256 + 5 * 41.6, 256, 41.6);
    expect(c.columns, 4);
    expect(c.perColumn, 2);
  });

  test('a narrow screen is one column, however narrow', () {
    expect(indexColumns(12, 120, 256, 41.6), (columns: 1, perColumn: 12));
  });

  test('a phone fitted on one screen takes two columns of 11rem', () {
    expect(indexColumns(9, 390 - 32, 176, 25.6), (columns: 2, perColumn: 5));
  });

  test('no names, no columns', () {
    expect(indexColumns(0, 800, 256, 41.6).columns, 0);
  });

  test('counts are written with commas', () {
    expect(thousands(7), '7');
    expect(thousands(1234), '1,234');
    expect(thousands(1234567), '1,234,567');
  });
}
