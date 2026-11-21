import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

enum AppMode { station, listen }

/// Everything the user can change, saved as JSON beside the app's data.
class Settings extends ChangeNotifier {
  Settings._(this._file);

  final File _file;

  /// False until the welcome screens have been finished or skipped.
  bool onboarded = false;

  AppMode mode = AppMode.listen;

  /// Remote stations the user has saved; [stationId] is the one in use.
  List<Station> stations = [];
  String? stationId;

  /// The station a remote plate shows: the chosen one, else the first.
  Station? get station {
    for (final x in stations) {
      if (x.id == stationId) return x;
    }
    return stations.isEmpty ? null : stations.first;
  }

  /// The station in use, as the rest of the app asks for it.
  String get birdnetUrl => station?.birdnetUrl ?? '';
  String get birdweatherStation => station?.birdweather ?? '';

  /// The plate's station button: from Listen here, the station last shown;
  /// on a station, the next saved one, round again.
  void nextStation() => update((x) {
        if (x.stations.isEmpty) return;
        if (x.mode == AppMode.listen) {
          x.mode = AppMode.station;
          x.stationId = x.station!.id;
          return;
        }
        final i = x.stations.indexWhere((st) => st.id == x.station?.id);
        x.stationId = x.stations[(i + 1) % x.stations.length].id;
      });

  /// Where the station button goes next, for its tooltip.
  String get nextStationName {
    if (stations.isEmpty) return 'Add a station';
    if (mode == AppMode.listen) return station!.name;
    final i = stations.indexWhere((st) => st.id == station?.id);
    return stations[(i + 1) % stations.length].name;
  }

  /// Saves a new station, or [replace]s one, and switches to it.
  void putStation(Station st, {String? replace}) => update((x) {
        final i = x.stations.indexWhere((o) => o.id == (replace ?? st.id));
        if (i >= 0) {
          x.stations[i] = st;
        } else {
          x.stations.add(st);
        }
        x.stationId = st.id;
        x.mode = AppMode.station;
      });

  /// Forgets a station; a plate that was showing it moves to the next one,
  /// or to Listen here when none is left.
  void removeStation(String id) => update((x) {
        final i = x.stations.indexWhere((o) => o.id == id);
        if (i < 0) return;
        final wasShown = x.station?.id == id;
        x.stations.removeAt(i);
        if (!wasShown) return;
        if (x.stations.isEmpty) {
          x.stationId = null;
          x.mode = AppMode.listen;
        } else {
          x.stationId = x.stations[i.clamp(0, x.stations.length - 1)].id;
        }
      });

  /// Listen here: minimum score for a detection.
  double threshold = 0.65;

  /// Listen here: seconds between analyses.
  double hopSeconds = 1.0;

  /// Listen here: which microphone hears the birds. 'phone' (the phone's
  /// own: full range, and music keeps playing in high quality on Bluetooth
  /// headphones) or 'headset' (headphones' or a headset's: Bluetooth sends
  /// it at call quality, which loses the higher songs and turns music to
  /// call quality too). Other apps' audio keeps playing either way.
  String micSource = 'phone';

  /// Listen here: the same species from the same model within this many
  /// seconds counts as the same call.
  double repeatSeconds = 10.0;

  bool animalsOnly = true;

  bool useGeomodel = false;
  double? latitude;
  double? longitude;
  double geoThreshold = 0.03;

  /// Run models on Apple's Core ML (Neural Engine or GPU) instead of the CPU.
  bool useCoreMl = false;

  /// Note the weather when a session starts (MET Norway, rough position).
  bool recordWeather = true;

  /// What the plate shows: its place, 1 to 7, in [plateModes], lettered a to
  /// g in the order the view button steps through them. Saved by the mode's [PlateMode.key], so a new order of
  /// the modes keeps the one chosen.
  int plateMode = defaultPlateMode;

  /// Models that listen. Each window goes through every one of them.
  Set<String> activeModels = {'bnl-v3-10k'};

  /// Which model's detections the plate draws, or 'all'.
  String plateModel = 'bnl-v3-10k';

  /// Experimental: in Listen here, the plate drawn by Flutter itself
  /// (lib/native/native_plate.dart) instead of the web page.
  bool nativePlate = false;

  /// The Flutter plate's collage: 'calls' (noisiest species), 'time'
  /// (recent ramblings) or 'equal' (no pecking order).
  String nativeSizeBy = 'calls';

  /// The Flutter plate: what is done to a plate still on its paper:
  /// 'cutout' (lifted off the page, as the web plate does), 'tint' or
  /// 'plain' (PlateStyle in lib/native/plate_library.dart).
  String nativePlateStyle = 'cutout';

  /// The Flutter plate: how the creature heard last is marked: 'centre' (a
  /// dot over it), 'below' (a dot under it, the app's choice for the web
  /// plate in Listen here), 'fade' (the rest faded) or 'none'.
  String nativeMarkAt = 'below';

  /// The Flutter plate: the collage takes what the heading and index leave
  /// of the screen, as the web plate's "Fit everything on one screen".
  bool nativeFit = true;

  /// The Flutter plate: the index folded away under its heading (the web
  /// plate keeps this as birdplate.bsIndexFolded).
  bool nativeIndexFolded = true;

  /// The Flutter plate: offer plates of skulls, wings and eggs among a
  /// bird's other plates (never chosen first), as the web plate's option.
  bool nativeParts = false;

  /// The Flutter plate: draw and list only the [nativeLimit] most heard
  /// species; 0 for all (the web plate's Limit species).
  int nativeLimit = 0;

  /// The Flutter plate: the heading's "22 species from 90 calls" line. Off
  /// unless chosen; the index's heading carries the number of species.
  bool nativeTotals = false;

  /// The Flutter plate: the whole heading (title, number, date, place,
  /// weather) in small capitals, as Index of Species is set (the default),
  /// or in the page's serif and italic.
  bool nativeTitleCaps = true;

  /// The Flutter plate: the lines under the title (session number, date,
  /// place, weather) in the title's ink (the default) or in sepia.
  bool nativeHeadingInk = true;

  /// Listen here: show the walk on a map in place of the collage.
  bool showMap = false;

  /// The map's crosses: 'first' (where each species was first heard) or
  /// 'all' (every call).
  String mapBirds = 'first';

  /// The map's extras: listed buildings, scheduled monuments, protected
  /// nature sites and Wikipedia places along the walk. Off by default, as
  /// they send the walk's area to Historic England, Natural England and
  /// Wikipedia.
  bool mapExtras = false;

  static Future<Settings> load(Directory dir) async {
    final s = Settings._(File('${dir.path}/settings.json'));
    try {
      if (await s._file.exists()) {
        s._fromJson(jsonDecode(await s._file.readAsString()) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('settings: could not read, using defaults ($e)');
    }
    return s;
  }

  void _fromJson(Map<String, dynamic> j) {
    onboarded = (j['onboarded'] as bool?) ?? onboarded;
    mode = j['mode'] == 'station' ? AppMode.station : AppMode.listen;
    final list = j['stations'];
    if (list is List) {
      stations = list.whereType<Map<String, dynamic>>().map(Station.fromJson).toList();
      stationId = j['station'] as String?;
    } else {
      // Settings from before saved stations: one BirdNET-Go address and/or
      // one BirdWeather number, the number winning when both were set.
      final url = ((j['birdnetUrl'] as String?) ?? '').trim();
      final bw = ((j['birdweatherStation'] as String?) ?? '').trim();
      if (url.isNotEmpty) stations.add(Station(id: 'birdnet', name: 'BirdNET-Go', birdnetUrl: url));
      if (bw.isNotEmpty) stations.add(Station(id: 'birdweather', name: 'BirdWeather $bw', birdweather: bw));
      stationId = stations.isEmpty ? null : stations.last.id;
    }
    threshold = (j['threshold'] as num?)?.toDouble() ?? threshold;
    hopSeconds = (j['hopSeconds'] as num?)?.toDouble() ?? hopSeconds;
    micSource = j['micSource'] == 'headset' ? 'headset' : 'phone';
    repeatSeconds = (j['repeatSeconds'] as num?)?.toDouble() ?? repeatSeconds;
    animalsOnly = (j['animalsOnly'] as bool?) ?? animalsOnly;
    useGeomodel = (j['useGeomodel'] as bool?) ?? useGeomodel;
    latitude = (j['latitude'] as num?)?.toDouble();
    longitude = (j['longitude'] as num?)?.toDouble();
    geoThreshold = (j['geoThreshold'] as num?)?.toDouble() ?? geoThreshold;
    useCoreMl = (j['useCoreMl'] as bool?) ?? useCoreMl;
    recordWeather = (j['recordWeather'] as bool?) ?? recordWeather;
    // plateView, by key; or plateMode, its number in the first order (1 to 7).
    const firstOrder = ['calls', 'time', 'equal', 'noindex', 'index', 'latest', 'top'];
    final oldN = (j['plateMode'] as num?)?.toInt();
    final key = j['plateView'] as String? ??
        (oldN != null && oldN >= 1 && oldN <= firstOrder.length ? firstOrder[oldN - 1] : null);
    final at = plateModes.indexWhere((m) => m.key == key);
    if (at >= 0) plateMode = at + 1;
    final active = j['activeModels'];
    if (active is List) activeModels = active.whereType<String>().toSet();
    plateModel = (j['plateModel'] as String?) ?? plateModel;
    nativePlate = (j['nativePlate'] as bool?) ?? nativePlate;
    nativePlateStyle = const ['cutout', 'tint', 'plain'].contains(j['nativePlateStyle'])
        ? j['nativePlateStyle'] as String
        : nativePlateStyle;
    nativeMarkAt = const ['centre', 'below', 'fade', 'none'].contains(j['nativeMarkAt'])
        ? j['nativeMarkAt'] as String
        : nativeMarkAt;
    nativeFit = (j['nativeFit'] as bool?) ?? nativeFit;
    nativeIndexFolded = (j['nativeIndexFolded'] as bool?) ?? nativeIndexFolded;
    nativeParts = (j['nativeParts'] as bool?) ?? nativeParts;
    nativeLimit = math.max(0, (j['nativeLimit'] as num?)?.toInt() ?? nativeLimit);
    nativeTotals = (j['nativeTotals'] as bool?) ?? nativeTotals;
    nativeTitleCaps = (j['nativeTitleCaps'] as bool?) ?? nativeTitleCaps;
    nativeHeadingInk = (j['nativeHeadingInk'] as bool?) ?? nativeHeadingInk;
    nativeSizeBy = const ['calls', 'time', 'equal'].contains(j['nativeSizeBy'])
        ? j['nativeSizeBy'] as String
        : nativeSizeBy;
    showMap = (j['showMap'] as bool?) ?? showMap;
    mapBirds = j['mapBirds'] == 'all' ? 'all' : 'first';
    mapExtras = (j['mapExtras'] as bool?) ?? mapExtras;
    // Settings saved before defaults v2 still carry the first test build's
    // defaults (3 s, 50 %); move those, and only those, to the new ones.
    if (((j['defaults'] as num?) ?? 1) < 2) {
      if (hopSeconds == 3.0) hopSeconds = 1.0;
      if (threshold == 0.5) threshold = 0.65;
    }
  }

  /// The listening settings saved with each session, so its results can be
  /// read later knowing how they were made.
  Map<String, dynamic> get listeningSnapshot => {
        'confidenceThreshold': threshold,
        'hopSeconds': hopSeconds,
        'repeatSeconds': repeatSeconds,
        'animalsOnly': animalsOnly,
        'microphone': micSource,
        'locationFilter': useGeomodel,
        if (useGeomodel) 'locationFilterThreshold': geoThreshold,
        'coreMl': useCoreMl,
        'plateModel': plateModel,
      };

  Map<String, dynamic> toJson() => {
        'defaults': 2,
        'onboarded': onboarded,
        'mode': mode.name,
        'stations': [for (final st in stations) st.toJson()],
        'station': stationId,
        // the station in use, as builds before saved stations read it
        'birdnetUrl': birdnetUrl,
        'birdweatherStation': birdweatherStation,
        'threshold': threshold,
        'hopSeconds': hopSeconds,
        'micSource': micSource,
        'repeatSeconds': repeatSeconds,
        'animalsOnly': animalsOnly,
        'useGeomodel': useGeomodel,
        'latitude': latitude,
        'longitude': longitude,
        'geoThreshold': geoThreshold,
        'useCoreMl': useCoreMl,
        'recordWeather': recordWeather,
        'plateView': plateModes[plateMode - 1].key,
        'activeModels': activeModels.toList(),
        'plateModel': plateModel,
        'nativePlate': nativePlate,
        'nativeSizeBy': nativeSizeBy,
        'nativePlateStyle': nativePlateStyle,
        'nativeMarkAt': nativeMarkAt,
        'nativeFit': nativeFit,
        'nativeIndexFolded': nativeIndexFolded,
        'nativeParts': nativeParts,
        'nativeLimit': nativeLimit,
        'nativeTotals': nativeTotals,
        'nativeTitleCaps': nativeTitleCaps,
        'nativeHeadingInk': nativeHeadingInk,
        'showMap': showMap,
        'mapBirds': mapBirds,
        'mapExtras': mapExtras,
      };

  void update(void Function(Settings s) change) {
    change(this);
    notifyListeners();
    // one save after another, so a quick run of changes lands in order
    final json = const JsonEncoder.withIndent('  ').convert(toJson());
    _saving = _saving.then((_) => _file.writeAsString(json)).then((_) {}, onError: (Object e) {
      debugPrint('settings: could not save ($e)');
    });
  }

  Future<void> _saving = Future.value();

  /// Done when every change so far is on disk.
  Future<void> get saved => _saving;

  /// BirdNET-Go address without a trailing slash, with http:// if missing.
  String get birdnetBase {
    var u = birdnetUrl.trim();
    if (u.isEmpty) return '';
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  String get stationDigits => birdweatherStation.replaceAll(RegExp(r'\D'), '');
}

/// The plate's modes, lettered a to g ([plateLetter]) in the order the view
/// button (Icons.dashboard_outlined) steps through them. Those
/// with a [PlateMode.sizeBy] set the collage's Size by; the others use the
/// page's own Home Assistant card views (?view=, ?hide=).
class PlateMode {
  const PlateMode(this.key, this.name, {this.sizeBy, this.query = '', this.currentOnly = false});

  /// Saved in settings.json as plateView; never changes.
  final String key;

  final String name;

  /// For a, f and g: the page's Size by (calls, time, equal).
  final String? sizeBy;

  /// Extra address parameters for the page.
  final String query;

  /// A panel of the session being viewed, with no session arrows (d and e):
  /// pick the session in another mode, then come here.
  final bool currentOnly;
}

const plateModes = <PlateMode>[
  PlateMode('calls', 'Noisiest species', sizeBy: 'calls'),                       // a
  PlateMode('latest', 'The latest bird, and when',                                // b
      query: 'view=latest&show=time,title,date', currentOnly: true),
  PlateMode('top', 'Most heard this session',                                     // c
      query: 'view=top&show=title,date', currentOnly: true),
  PlateMode('index', 'The index alone', query: 'view=index&show=title,date'),     // d
  PlateMode('noindex', 'The collage, no index', query: 'hide=index'),             // e
  PlateMode('time', 'Recent ramblings', sizeBy: 'time'),                          // f
  PlateMode('equal', 'No pecking order', sizeBy: 'equal'),                        // g
];

/// The view the app opens on until another is chosen: recent ramblings.
final defaultPlateMode = plateModes.indexWhere((m) => m.key == 'time') + 1;

/// Mode [n] (1 to 7) as its letter, a to g: how the modes are named in the code and tests.
String plateLetter(int n) => String.fromCharCode(0x60 + n);

/// A remote station: a BirdNET-Go address, or a public BirdWeather station.
class Station {
  Station({required this.id, required this.name, this.birdnetUrl = '', this.birdweather = ''});

  /// Reads what someone typed or pasted: a BirdWeather station number or
  /// page (app.birdweather.com/stations/1234), else a BirdNET-Go address.
  factory Station.fromInput(String name, String input, {String? id}) {
    final t = input.trim();
    final bw = RegExp(r'birdweather\.com/stations/(\d+)').firstMatch(t)?.group(1) ??
        (RegExp(r'^\d+$').hasMatch(t) ? t : null);
    final kind = bw != null ? 'BirdWeather $bw' : 'BirdNET-Go';
    return Station(
      id: id ?? 's${DateTime.now().microsecondsSinceEpoch}-${_made++}',
      name: name.trim().isNotEmpty ? name.trim() : kind,
      birdnetUrl: bw == null ? t : '',
      birdweather: bw ?? '',
    );
  }

  static int _made = 0;

  factory Station.fromJson(Map<String, dynamic> j) => Station(
        id: (j['id'] as String?) ?? 's${j.hashCode}',
        name: (j['name'] as String?) ?? 'Station',
        birdnetUrl: (j['birdnetUrl'] as String?) ?? '',
        birdweather: (j['birdweather'] as String?) ?? '',
      );

  final String id;
  final String name;
  final String birdnetUrl;
  final String birdweather;

  bool get isBirdWeather => birdweather.replaceAll(RegExp(r'\D'), '').isNotEmpty;

  /// What sort of station, for a subtitle: "BirdNET-Go" or "BirdWeather 1234".
  String get kind => isBirdWeather ? 'BirdWeather ${birdweather.replaceAll(RegExp(r'\D'), '')}' : 'BirdNET-Go';

  /// What it was set up from, as the user would type it again.
  String get input => isBirdWeather ? birdweather : birdnetUrl;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (birdnetUrl.isNotEmpty) 'birdnetUrl': birdnetUrl,
        if (birdweather.isNotEmpty) 'birdweather': birdweather,
      };
}
