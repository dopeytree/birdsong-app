/// Prehistoric sites among Historic England's scheduled monuments, picked
/// out by name for the map's antiquity marks, as old Ordnance Survey maps
/// set them apart (a symbol, and the name in their own lettering).
library;

/// What kind of antiquity, for its symbol.
enum AntiquityKind { circle, stone, row, henge, barrow, longBarrow, cairn, fort, cursus, enclosure }

/// An antiquity: its kind and the name to print.
typedef Antiquity = ({AntiquityKind kind, String label});

// The kind words, and what each kind is called when the record has no
// short name of its own (as the OS printed them).
const _words = <(String, AntiquityKind)>[
  ('stonehenge', AntiquityKind.circle),
  ('stone circle', AntiquityKind.circle),
  ('circles', AntiquityKind.circle),
  ('circle', AntiquityKind.circle),
  ('stone row', AntiquityKind.row),
  ('stone alignment', AntiquityKind.row),
  ('standing stone', AntiquityKind.stone),
  ('monolith', AntiquityKind.stone),
  ('menhir', AntiquityKind.stone),
  ('hengi', AntiquityKind.henge),
  ('henge', AntiquityKind.henge),
  ('long barrow', AntiquityKind.longBarrow),
  ('chambered tomb', AntiquityKind.longBarrow),
  ('barrow', AntiquityKind.barrow),
  ('tumul', AntiquityKind.barrow),
  ('cairn', AntiquityKind.cairn),
  ('hillfort', AntiquityKind.fort),
  ('hill fort', AntiquityKind.fort),
  ('camp', AntiquityKind.fort),
  ('cursus', AntiquityKind.cursus),
  ('causewayed enclosure', AntiquityKind.enclosure),
];

const _called = {
  AntiquityKind.circle: 'Stone Circle',
  AntiquityKind.stone: 'Standing Stone',
  AntiquityKind.row: 'Stone Row',
  AntiquityKind.henge: 'Henge',
  AntiquityKind.barrow: 'Tumulus',
  AntiquityKind.longBarrow: 'Long Barrow',
  AntiquityKind.cairn: 'Cairn',
  AntiquityKind.fort: 'Camp',
  AntiquityKind.cursus: 'Cursus',
  AntiquityKind.enclosure: 'Enclosure',
};

// Not prehistoric, though their names may say camp or circle (when
// before the kind word: "south east of Church Farm" doesn't count).
final _not = RegExp(
    r'\b(roman|medieval|post-medieval|moated|military|war|prisoner|practice|church|chapel|cross|castle|abbey|priory|deserted|motte)\b',
    caseSensitive: false);

// "Two bowl barrows", "18 round barrows", "a round barrow cemetery"
final _many = RegExp(
    r'\b(two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|\d+|barrows|cemetery|group)\b',
    caseSensitive: false);

// "known as `Bush Barrow'", "known as the Old King Barrows"
final _knownAs = RegExp(r"""known as (?:the )?[`'‘"]?([A-Z][A-Za-z' ]*?[A-Za-z])[`'’"]?(?=,| on | and | south| north| east| west| in |$)""");

// a record named by what and where it is ("Bowl barrow 230m west of
// Stonehenge", "Long barrow on Wilsford Down"), not by a name of its own
final _described = RegExp(
    r'\d|\b(of|on|in|near|at|within|and|forming|known|situated|immediately|north|south|east|west)\b|'
    r'^(a|an|the remains|bowl|bell|disc|pond|saucer|round|long|twin|triple|henge|hengi-form|standing|stone|'
    r'two|three|four|five|six|seven|eight|nine|ten|eighteen|cairn|tumulus|barrow|hillfort|enclosure|causewayed|'
    r'chambered|univallate|bivallate|multivallate|slight|large|small|irregular)\b',
    caseSensitive: false);

/// The antiquity [name] (a scheduled monument's) is, by the first kind
/// word in it, or null. "Stonehenge, the Avenue, and three barrows" is a
/// stone circle, called Stonehenge; "Bowl barrow 230m west of Stonehenge"
/// a barrow, called Tumulus.
Antiquity? antiquityOf(String name) {
  final lower = name.toLowerCase();
  AntiquityKind? kind;
  var at = 1 << 30;
  for (final (w, k) in _words) {
    final i = lower.indexOf(w);
    // the earliest word; of two at one place, the longer (listed first)
    if (i >= 0 && i < at) (kind, at) = (k, i);
  }
  if (kind == null) return null;
  // "Roman camp", "Churchyard cross": the other word first
  final not = _not.firstMatch(name);
  if (not != null && not.start <= at) return null;
  return (kind: kind, label: _labelOf(name, kind));
}

String _labelOf(String name, AntiquityKind kind) {
  final known = _knownAs.firstMatch(name);
  if (known != null) return known.group(1)!;
  // its own name, before any list: "Stonehenge, the Avenue, ..."
  final first = name.split(',').first.trim();
  if (first.split(' ').length <= 5 && !_described.hasMatch(first)) return first;
  if (kind == AntiquityKind.barrow && _many.hasMatch(name)) return 'Tumuli';
  return _called[kind]!;
}
