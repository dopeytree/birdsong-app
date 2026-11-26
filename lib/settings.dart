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

  /// Whether each station's past days are filled in on this device (by
  /// its id): a phone asks first; elsewhere they are, unless switched off.
  Map<String, bool> stationKeepPast = {};

  /// Whether this device fills in [st]'s past days: as answered, else yes
  /// on a computer and not yet on a phone; null on a phone not yet asked.
  bool? keepPastOf(Station st) =>
      stationKeepPast[st.id] ?? (Platform.isIOS || Platform.isAndroid ? null : true);

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
          x.plateMode = defaultPlateMode;
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

  /// Listen here: saved clip audio format — 'aac' (AAC 128 kbps .m4a, default)
  /// or 'wav' (uncompressed PCM .wav).
  String clipFormat = 'aac';

  /// Sync sessions and settings via iCloud Drive on Apple devices.
  bool icloudSync = false;

  /// Listen here: the same species from the same model within this many
  /// seconds counts as the same call.
  double repeatSeconds = 10.0;

  bool animalsOnly = true;

  /// Default species / sound names ignored from detections and the plate.
  static const defaultIgnoredSpecies = <String>[
    'Human',
    'Humans',
    'Dog',
    'Engine',
    'Domestic sounds',
    'Home sounds',
    'Harbor Seal',
  ];

  /// Species or sound names to ignore (case-insensitive whole-word match
  /// against common or scientific name). Editable in Settings > Listening.
  List<String> ignoredSpecies = List<String>.of(defaultIgnoredSpecies);

  String? _ignoredKey;
  List<RegExp> _ignoredRes = const [];

  /// Whether a species or sound label matches [ignoredSpecies].
  bool isIgnoredSpecies(String common, [String sci = '']) {
    if (ignoredSpecies.isEmpty) return false;
    final key = ignoredSpecies.join('\u0000');
    if (key != _ignoredKey) {
      _ignoredKey = key;
      _ignoredRes = [
        for (final raw in ignoredSpecies)
          if (raw.trim().isNotEmpty)
            RegExp(r'\b' + RegExp.escape(raw.trim()) + r'\b', caseSensitive: false),
      ];
    }
    for (final re in _ignoredRes) {
      if (re.hasMatch(common) || (sci.isNotEmpty && re.hasMatch(sci))) return true;
    }
    return false;
  }

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

  /// When installed models were last checked for a newer build, epoch ms.
  /// 0 until the first check succeeds.
  int modelCheckAt = 0;

  /// A manifest path to the epoch ms until which its notice stays hidden.
  Map<String, int> modelSnoozed = {};

  /// Manifest paths the user does not want offered again.
  Set<String> modelSkipped = {};

  /// A newer build taken in place of a catalogue model, keyed by spec id.
  /// The fields are written by ModelUpdates.accept.
  Map<String, Map<String, dynamic>> modelOverrides = {};

  /// The plate as the old web page draws it (assets/web/index.html in a web
  /// view, lib/ui/plate_view.dart) instead of Flutter's own
  /// (lib/native/native_plate.dart, the default since 22 Nov 2026). Saved
  /// as 'webPlate': the old 'nativePlate' key, off in every saved file, is
  /// no longer read, so every install opens on the Flutter plate once.
  bool webPlate = false;

  /// Whether the plate is Flutter's own ([webPlate] off).
  bool get nativePlate => !webPlate;

  /// The Flutter plate's heading: the title line ("Birdsong #3/12") and the
  /// lines under it (when, where, the weather), as the web plate's Title
  /// and Date switches.
  bool nativeShowTitle = true;
  bool nativeShowDate = true;

  /// What runs along the bottom of the plate between the buttons (Listen here):
  /// 'scribble' (sepia pencil line), 'wave' (lighter black waveform for
  /// slower devices), or 'off'.
  String songScribbleMode = 'scribble';

  bool get songScribble => songScribbleMode != 'off';

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

  /// The Flutter plate: show a bird's info ticket on mouse hover (off by
  /// default so clicking opens the bird card, as on touch devices).
  bool nativeHoverInfo = false;

  /// The Flutter plate: show name tickets on all birds in the collage (off by
  /// default, so only the centred hero bird carries its name + badge).
  bool nativeAllNameTickets = false;

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

  /// Whether "Passed on the way" says what each place is (its kind, or its
  /// Wikipedia description) after its name. The name alone is shorter; the
  /// map's label still says it.
  bool mapPassedAbout = true;

  /// Whether the map shows its timing readout (debug builds only).
  bool mapDebugReadout = false;

  /// The map's layers (its layers button): what each kind of extra shows,
  /// and so what is looked up. Heritage: Historic England. Nature sites:
  /// Natural England, NatureScot, Natural Resources Wales. Wikipedia places.
  /// Reserves and Hides & viewpoints: from OpenStreetMap, in the map tiles.
  bool mapShowHeritage = true;
  bool mapShowNature = true;

  /// Ancient woods (Natural England) a shade deeper than other woods.
  bool mapShowAncient = true;
  bool mapShowWiki = true;
  bool mapShowReserves = true;
  bool mapShowHides = true;

  /// The bird whose records (GBIF) are shown on the map, by scientific
  /// name; '' for none.
  String mapRecordsSci = '';

  /// Wildlife pictures on the map: a deer in a wood, a whale at sea, for
  /// decoration (from the map's own tiles; nothing looked up).
  bool mapWildlife = true;

  /// Map button appearance: 'ink' (all-black icons with hover-only background,
  /// default), 'paper' (round warm paper background with madder icons), or
  /// 'madder' (solid madder).
  String mapButtonStyle = 'ink';

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
    final keep = j['stationKeepPast'];
    if (keep is Map) {
      stationKeepPast = {
        for (final e in keep.entries)
          if (e.value is bool) '${e.key}': e.value as bool
      };
    }
    threshold = (j['threshold'] as num?)?.toDouble() ?? threshold;
    hopSeconds = (j['hopSeconds'] as num?)?.toDouble() ?? hopSeconds;
    micSource = j['micSource'] == 'headset' ? 'headset' : 'phone';
    clipFormat = j['clipFormat'] == 'wav' ? 'wav' : 'aac';
    icloudSync = (j['icloudSync'] as bool?) ?? icloudSync;
    repeatSeconds = (j['repeatSeconds'] as num?)?.toDouble() ?? repeatSeconds;
    animalsOnly = (j['animalsOnly'] as bool?) ?? animalsOnly;
    final ignored = j['ignoredSpecies'];
    if (ignored is List) {
      ignoredSpecies = [
        for (final x in ignored.whereType<String>())
          if (x.trim().isNotEmpty) x.trim(),
      ];
    }
    useGeomodel = (j['useGeomodel'] as bool?) ?? useGeomodel;
    latitude = (j['latitude'] as num?)?.toDouble();
    longitude = (j['longitude'] as num?)?.toDouble();
    geoThreshold = (j['geoThreshold'] as num?)?.toDouble() ?? geoThreshold;
    useCoreMl = (j['useCoreMl'] as bool?) ?? useCoreMl;
    recordWeather = (j['recordWeather'] as bool?) ?? recordWeather;
    // plateView, by key; or legacy plateMode numbers from the old 7-view list.
    const firstOrder = ['calls', 'time', 'equal', 'noindex', 'index', 'latest', 'top'];
    final oldN = (j['plateMode'] as num?)?.toInt();
    var key = j['plateView'] as String? ??
        (oldN != null && oldN >= 1 && oldN <= firstOrder.length ? firstOrder[oldN - 1] : null);
    if (key == 'latest' || key == 'top') key = 'spotlight';
    final at = plateModes.indexWhere((m) => m.key == key);
    if (at >= 0) plateMode = at + 1;
    final active = j['activeModels'];
    if (active is List) activeModels = active.whereType<String>().toSet();
    plateModel = (j['plateModel'] as String?) ?? plateModel;
    // A bad value is skipped, never thrown: a throw here would drop every
    // field after this one.
    final checked = j['modelCheckAt'];
    if (checked is num && checked.isFinite) modelCheckAt = math.max(0, checked.toInt());
    final snoozed = j['modelSnoozed'];
    if (snoozed is Map) {
      final next = <String, int>{};
      for (final e in snoozed.entries) {
        if (e.value is! num || !(e.value as num).isFinite) continue;
        next['${e.key}'] = (e.value as num).toInt();
      }
      modelSnoozed = next;
    }
    final skipped = j['modelSkipped'];
    if (skipped is List) modelSkipped = skipped.whereType<String>().toSet();
    final overrides = j['modelOverrides'];
    if (overrides is Map) {
      final next = <String, Map<String, dynamic>>{};
      for (final e in overrides.entries) {
        if (e.value is! Map) continue;
        final inner = <String, dynamic>{};
        for (final f in (e.value as Map).entries) {
          if (f.key is! String) continue;
          inner[f.key as String] = f.value;
        }
        next['${e.key}'] = inner;
      }
      modelOverrides = next;
    }
    webPlate = (j['webPlate'] as bool?) ?? webPlate;
    nativeShowTitle = (j['nativeShowTitle'] as bool?) ?? nativeShowTitle;
    nativeShowDate = (j['nativeShowDate'] as bool?) ?? nativeShowDate;
    final scribbleMode = j['songScribbleMode'];
    if (const ['scribble', 'wave', 'off'].contains(scribbleMode)) {
      songScribbleMode = scribbleMode as String;
    } else if (j['songScribble'] is bool) {
      songScribbleMode = (j['songScribble'] as bool) ? 'scribble' : 'off';
    }
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
    nativeHoverInfo = (j['nativeHoverInfo'] as bool?) ?? nativeHoverInfo;
    nativeAllNameTickets = (j['nativeAllNameTickets'] as bool?) ?? nativeAllNameTickets;
    nativeSizeBy = const ['calls', 'time', 'equal'].contains(j['nativeSizeBy'])
        ? j['nativeSizeBy'] as String
        : nativeSizeBy;
    showMap = (j['showMap'] as bool?) ?? showMap;
    mapBirds = j['mapBirds'] == 'all' ? 'all' : 'first';
    mapExtras = (j['mapExtras'] as bool?) ?? mapExtras;
    mapPassedAbout = (j['mapPassedAbout'] as bool?) ?? mapPassedAbout;
    mapDebugReadout = (j['mapDebugReadout'] as bool?) ?? mapDebugReadout;
    mapShowHeritage = (j['mapShowHeritage'] as bool?) ?? mapShowHeritage;
    mapShowNature = (j['mapShowNature'] as bool?) ?? mapShowNature;
    mapShowAncient = (j['mapShowAncient'] as bool?) ?? mapShowAncient;
    mapShowWiki = (j['mapShowWiki'] as bool?) ?? mapShowWiki;
    mapShowReserves = (j['mapShowReserves'] as bool?) ?? mapShowReserves;
    mapShowHides = (j['mapShowHides'] as bool?) ?? mapShowHides;
    mapRecordsSci = (j['mapRecordsSci'] as String?) ?? mapRecordsSci;
    mapWildlife = (j['mapWildlife'] as bool?) ?? mapWildlife;
    mapButtonStyle = const ['paper', 'ink', 'madder'].contains(j['mapButtonStyle'])
        ? j['mapButtonStyle'] as String
        : mapButtonStyle;
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
        'ignoredSpecies': List<String>.of(ignoredSpecies),
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
        if (stationKeepPast.isNotEmpty) 'stationKeepPast': stationKeepPast,
        // the station in use, as builds before saved stations read it
        'birdnetUrl': birdnetUrl,
        'birdweatherStation': birdweatherStation,
        'threshold': threshold,
        'hopSeconds': hopSeconds,
        'micSource': micSource,
        'clipFormat': clipFormat,
        'icloudSync': icloudSync,
        'repeatSeconds': repeatSeconds,
        'animalsOnly': animalsOnly,
        'ignoredSpecies': List<String>.of(ignoredSpecies),
        'useGeomodel': useGeomodel,
        'latitude': latitude,
        'longitude': longitude,
        'geoThreshold': geoThreshold,
        'useCoreMl': useCoreMl,
        'recordWeather': recordWeather,
        'plateView': plateModes[(plateMode - 1).clamp(0, plateModes.length - 1)].key,
        'activeModels': activeModels.toList(),
        'plateModel': plateModel,
        'modelCheckAt': modelCheckAt,
        'modelSnoozed': modelSnoozed,
        'modelSkipped': modelSkipped.toList(),
        'modelOverrides': modelOverrides,
        'webPlate': webPlate,
        'nativeShowTitle': nativeShowTitle,
        'nativeShowDate': nativeShowDate,
        'songScribble': songScribble,
        'songScribbleMode': songScribbleMode,
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
        'nativeHoverInfo': nativeHoverInfo,
        'nativeAllNameTickets': nativeAllNameTickets,
        'showMap': showMap,
        'mapBirds': mapBirds,
        'mapExtras': mapExtras,
        'mapPassedAbout': mapPassedAbout,
        'mapDebugReadout': mapDebugReadout,
        'mapShowHeritage': mapShowHeritage,
        'mapShowNature': mapShowNature,
        'mapShowAncient': mapShowAncient,
        'mapShowWiki': mapShowWiki,
        'mapShowReserves': mapShowReserves,
        'mapShowHides': mapShowHides,
        'mapRecordsSci': mapRecordsSci,
        'mapWildlife': mapWildlife,
        'mapButtonStyle': mapButtonStyle,
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
  PlateMode('time', 'Recent ramblings', sizeBy: 'time'),                           // a (default): Most recent -> Map
  PlateMode('spotlight', 'Latest & most heard',                                    // b: Combined Latest + Most heard (after Map)
      query: 'view=latest&show=time,title,date', currentOnly: true),
  PlateMode('equal', 'No pecking order', sizeBy: 'equal'),                         // c: Equal size -> back to Most recent
];

/// The view the app opens on until another is chosen: recent ramblings.
final defaultPlateMode = plateModes.indexWhere((m) => m.key == 'time') + 1;

/// Mode [n] (1 to 7) as its letter, a to g: how the modes are named in the code and tests.
String plateLetter(int n) => String.fromCharCode(0x60 + n);

/// A remote station: a BirdNET-Go address, or a public BirdWeather station.
class Station {
  Station({required this.id, required this.name, this.birdnetUrl = '', this.birdweather = ''});

  /// Reads what someone typed or pasted: a BirdWeather station number (with
  /// or without a leading #) or page (app.birdweather.com/stations/1234),
  /// else a BirdNET-Go address.
  factory Station.fromInput(String name, String input, {String? id}) {
    final t = input.trim();
    final bw = RegExp(r'birdweather\.com/stations/#?(\d+)').firstMatch(t)?.group(1) ??
        RegExp(r'^#?\s*(\d+)$').firstMatch(t)?.group(1);
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
