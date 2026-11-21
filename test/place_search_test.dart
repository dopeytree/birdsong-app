import 'package:birdsong_app/native/place_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("Photon's places: name, where, point, extent in either corner order", () {
    final found = placesOf({
      'features': [
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [-2.7144, 51.1465]
          },
          'properties': {
            'name': 'Glastonbury',
            'county': 'Somerset',
            'state': 'England',
            'country': 'United Kingdom',
            // Photon's order: west, north, east, south
            'extent': [-2.7451, 51.1611, -2.6866, 51.1337],
          },
        },
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [-2.6987, 51.1442]
          },
          'properties': {'name': 'Glastonbury Tor', 'city': 'Glastonbury', 'country': 'United Kingdom'},
        },
        // the same town again (its boundary): folded into the first
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [-2.7150, 51.1470]
          },
          'properties': {'name': 'Glastonbury', 'county': 'Somerset', 'state': 'England', 'country': 'United Kingdom'},
        },
        {
          'type': 'Feature',
          'geometry': {'type': 'Point', 'coordinates': [0, 0]},
          'properties': <String, dynamic>{},
        },
      ],
    });
    expect(found.length, 2);
    final g = found.first;
    expect(g.where, 'Somerset, England, United Kingdom');
    expect(g.at.latitude, 51.1465);
    expect(g.hasExtent, isTrue);
    expect([g.west, g.south, g.east, g.north], [-2.7451, 51.1337, -2.6866, 51.1611]);
    expect(found[1].where, 'Glastonbury, United Kingdom');
    expect(found[1].hasExtent, isFalse);
  });
}
