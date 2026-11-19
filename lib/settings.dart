import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

enum AppMode { station, listen }

/// Everything the user can change, saved as JSON beside the app's data.
class Settings extends ChangeNotifier {
  Settings._(this._file);

  final File _file;

  /// False until the welcome screens have been finished or skipped.
  bool onboarded = false;

  AppMode mode = AppMode.listen;

  /// Station mode: BirdNET-Go address, e.g. http://192.168.1.50:8080
  String birdnetUrl = '';

  /// Station mode: a public BirdWeather station number instead.
  String birdweatherStation = '';

  /// Listen here: minimum score for a detection.
  double threshold = 0.65;

  /// Listen here: seconds between analyses.
  double hopSeconds = 1.0;

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

  /// What the plate shows, 1 to 7 (see [plateModes]), from its number button.
  int plateMode = 1;

  /// Models that listen. Each window goes through every one of them.
  Set<String> activeModels = {'bnl-v3-10k'};

  /// Which model's detections the plate draws, or 'all'.
  String plateModel = 'bnl-v3-10k';

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
    birdnetUrl = (j['birdnetUrl'] as String?) ?? birdnetUrl;
    birdweatherStation = (j['birdweatherStation'] as String?) ?? birdweatherStation;
    threshold = (j['threshold'] as num?)?.toDouble() ?? threshold;
    hopSeconds = (j['hopSeconds'] as num?)?.toDouble() ?? hopSeconds;
    repeatSeconds = (j['repeatSeconds'] as num?)?.toDouble() ?? repeatSeconds;
    animalsOnly = (j['animalsOnly'] as bool?) ?? animalsOnly;
    useGeomodel = (j['useGeomodel'] as bool?) ?? useGeomodel;
    latitude = (j['latitude'] as num?)?.toDouble();
    longitude = (j['longitude'] as num?)?.toDouble();
    geoThreshold = (j['geoThreshold'] as num?)?.toDouble() ?? geoThreshold;
    useCoreMl = (j['useCoreMl'] as bool?) ?? useCoreMl;
    recordWeather = (j['recordWeather'] as bool?) ?? recordWeather;
    plateMode = ((j['plateMode'] as num?)?.toInt() ?? plateMode).clamp(1, plateModes.length);
    final active = j['activeModels'];
    if (active is List) activeModels = active.whereType<String>().toSet();
    plateModel = (j['plateModel'] as String?) ?? plateModel;
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
        'locationFilter': useGeomodel,
        if (useGeomodel) 'locationFilterThreshold': geoThreshold,
        'coreMl': useCoreMl,
        'plateModel': plateModel,
      };

  Map<String, dynamic> toJson() => {
        'defaults': 2,
        'onboarded': onboarded,
        'mode': mode.name,
        'birdnetUrl': birdnetUrl,
        'birdweatherStation': birdweatherStation,
        'threshold': threshold,
        'hopSeconds': hopSeconds,
        'repeatSeconds': repeatSeconds,
        'animalsOnly': animalsOnly,
        'useGeomodel': useGeomodel,
        'latitude': latitude,
        'longitude': longitude,
        'geoThreshold': geoThreshold,
        'useCoreMl': useCoreMl,
        'recordWeather': recordWeather,
        'plateMode': plateMode,
        'activeModels': activeModels.toList(),
        'plateModel': plateModel,
      };

  void update(void Function(Settings s) change) {
    change(this);
    notifyListeners();
    _file.writeAsString(const JsonEncoder.withIndent('  ').convert(toJson())).catchError(
        (Object e) {
      debugPrint('settings: could not save ($e)');
      return _file;
    });
  }

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

/// The plate's modes, numbered on its button. 1 to 3 size the collage; 4 to 7
/// use the page's own Home Assistant card views (?view=, ?hide=).
class PlateMode {
  const PlateMode(this.name, {this.sizeBy, this.query = '', this.currentOnly = false});

  final String name;

  /// For 1 to 3: the page's Size by (calls, time, equal).
  final String? sizeBy;

  /// Extra address parameters for the page.
  final String query;

  /// Shows the current session only: no session arrows (6 and 7).
  final bool currentOnly;
}

const plateModes = <PlateMode>[
  PlateMode('Noisiest species', sizeBy: 'calls'),
  PlateMode('Recent ramblings', sizeBy: 'time'),
  PlateMode('No pecking order', sizeBy: 'equal'),
  PlateMode('The collage, no index', query: 'hide=index'),
  PlateMode('The index alone', query: 'view=index&show=title,date'),
  PlateMode('The latest bird, and when',
      query: 'view=latest&show=time,title,date', currentOnly: true),
  PlateMode('Most heard this session', query: 'view=top&show=title,date', currentOnly: true),
];
