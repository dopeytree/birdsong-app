import 'package:birdsong_app/native/antiquities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? label(String n) => antiquityOf(n)?.label;
  AntiquityKind? kind(String n) => antiquityOf(n)?.kind;

  test('Stonehenge and its neighbours, as Historic England names them', () {
    const stonehenge = 'Stonehenge, the Avenue, and three barrows adjacent to the Avenue forming part of a round '
        'barrow cemetery on Countess Farm';
    expect(kind(stonehenge), AntiquityKind.circle);
    expect(label(stonehenge), 'Stonehenge');
    expect(label('Bowl barrow 230m west of Stonehenge forming part of a round barrow cemetery on Stonehenge Down'),
        'Tumuli');
    expect(label('Bowl barrow 650m SSE of Stonehenge'), 'Tumulus');
    expect(label("Bowl barrow known as `Bush Barrow' and two disc barrows south east of Normanton Gorse"), 'Bush Barrow');
    expect(label('Bell barrow known as the Monarch of the Plain on the western edge of Fargo Plantation'),
        'Monarch of the Plain');
    expect(kind('Long barrow on Wilsford Down 300m north of The Diamond'), AntiquityKind.longBarrow);
    expect(label('Long barrow on Wilsford Down 300m north of The Diamond'), 'Long Barrow');
    expect(kind('Henge monument 300m south of Longbarrow Cross Roads, east of A360'), AntiquityKind.henge);
    expect(label('Henge monument 300m south of Longbarrow Cross Roads, east of A360'), 'Henge');
    expect(kind('Hengi-form monument in Fargo Plantation south of The Cursus'), AntiquityKind.henge);
    final cursus = antiquityOf('The Cursus, two round barrows situated within its western end, and a long barrow');
    expect((cursus?.kind, cursus?.label), (AntiquityKind.cursus, 'The Cursus'));
  });

  test('stone circles, standing stones and camps by their own names', () {
    expect(label('Large irregular stone circle at Stanton Drew south east of Church Farm'), 'Stone Circle');
    expect(label('Stanton Drew Great Circle'), 'Stanton Drew Great Circle');
    expect(label('Priddy Circles'), 'Priddy Circles');
    expect(kind('Standing stone 200m east of Lower Farm'), AntiquityKind.stone);
    expect(label('Maes Knoll Camp'), 'Maes Knoll Camp');
    expect(kind('Maes Knoll Camp'), AntiquityKind.fort);
  });

  test('not prehistoric: Roman camps, crosses, moats, linear boundaries', () {
    expect(antiquityOf('Roman camp 400m north of Wall Farm'), isNull);
    expect(antiquityOf('Churchyard cross in St Andrew\'s churchyard'), isNull);
    expect(antiquityOf('Moated site at Manor Farm'), isNull);
    expect(antiquityOf('Linear boundary within Normanton Gorse'), isNull);
  });
}
