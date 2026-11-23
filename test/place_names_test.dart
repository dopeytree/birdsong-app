import 'package:birdsong_app/engine/place_names.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the most local settlement a place has is its name', () {
    expect(placeFromAddress({'village': 'Butleigh', 'county': 'Somerset'}), 'Butleigh');
    expect(placeFromAddress({'town': 'Glastonbury', 'county': 'Somerset'}), 'Glastonbury');
    expect(placeFromAddress({'city': 'Cardiff', 'suburb': 'Roath'}), 'Cardiff');
    expect(placeFromAddress({'county': 'Somerset'}), 'Somerset');
    expect(placeFromAddress({}), '');
  });
}
