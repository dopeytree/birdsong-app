import 'dart:math' as math;
import 'dart:typed_data';

import 'package:birdsong_app/engine/labels.dart';
import 'package:birdsong_app/engine/resampler.dart';
import 'package:birdsong_app/engine/ring_buffer.dart';
import 'package:birdsong_app/server/local_api.dart';
import 'package:birdsong_app/store/detection_store.dart';
import 'package:birdsong_app/store/media.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('labels', () {
    test('BirdNET underscore format, sound classes marked', () {
      final l = parseLabels('Turdus merula_Eurasian Blackbird\nEngine_Engine\nHuman vocal_Human vocal\n');
      expect(l.length, 3);
      expect(l[0].sci, 'Turdus merula');
      expect(l[0].common, 'Eurasian Blackbird');
      expect(l[0].animal, isTrue);
      expect(l[1].animal, isFalse);
      expect(l[2].animal, isFalse);
    });

    test('BirdNET Live CSV with header', () {
      final l = parseLabels('idx;birdnet_id;sci_name;com_name;class\n'
          '0;BN00001;Abeillia abeillei;Emerald-chinned Hummingbird;Aves\n');
      expect(l.single.sci, 'Abeillia abeillei');
      expect(l.single.common, 'Emerald-chinned Hummingbird');
    });

    test('geomodel tab rows', () {
      final l = parseLabels('BN00001\tAbeillia abeillei\tEmerald-chinned Hummingbird\n');
      expect(l.single.sci, 'Abeillia abeillei');
      expect(l.single.common, 'Emerald-chinned Hummingbird');
    });

    test('Perch scientific names only', () {
      final l = parseLabels('Strix aluco\nDog\n');
      expect(l[0].sci, 'Strix aluco');
      expect(l[0].animal, isTrue);
      expect(l[1].animal, isFalse);
      expect(namesOf(parseLabels('Strix aluco_Tawny Owl'))['Strix aluco'], 'Tawny Owl');
    });
  });

  group('resampler', () {
    test('48 kHz to 32 kHz keeps a 1 kHz tone and the length', () {
      final r = Resampler(48000, 32000);
      final input = Float32List(48000);
      for (var i = 0; i < input.length; i++) {
        input[i] = 0.5 * math.sin(2 * math.pi * 1000 * i / 48000);
      }
      // Feed in uneven chunks, as the microphone does.
      final out = <double>[];
      var at = 0;
      for (final n in [1000, 4096, 333, 20000, 22571]) {
        out.addAll(r.process(Float32List.sublistView(input, at, at + n)));
        at += n;
      }
      expect(out.length, closeTo(32000, 40));
      // Amplitude after the filter has settled.
      var peak = 0.0;
      for (final v in out.skip(1000).take(30000)) {
        peak = math.max(peak, v.abs());
      }
      expect(peak, closeTo(0.5, 0.03));
    });
  });

  group('ring buffer', () {
    test('latest wraps round', () {
      final b = RingBuffer(5);
      b.add(Float32List.fromList([1, 2, 3]));
      b.add(Float32List.fromList([4, 5, 6, 7]));
      expect(b.latest(4), [4, 5, 6, 7]);
      expect(b.latest(6), isNull);
    });
  });

  group('local api', () {
    final now = DateTime.now();
    final all = [
      Detection(id: 1, model: 'm', sci: 'Turdus merula', common: 'Blackbird', confidence: 0.9, at: now, hasClip: true),
      Detection(id: 2, model: 'm', sci: 'Turdus merula', common: 'Blackbird', confidence: 0.7, at: now),
      Detection(id: 3, model: 'm', sci: 'Strix aluco', common: 'Tawny Owl', confidence: 0.6, at: now),
    ];

    test('species daily', () {
      final rows = speciesDaily(all, ymd(now));
      expect(rows.first['scientific_name'], 'Turdus merula');
      expect(rows.first['count'], 2);
      expect((rows.first['hourly_counts'] as List).length, 24);
      expect(rows.first['first_heard'], matches(RegExp(r'^\d\d:\d\d:\d\d$')));
    });

    test('summary carries an offset', () {
      final rows = speciesSummary(all, null, null);
      expect(rows.length, 2);
      expect(rows.first['last_heard'], matches(RegExp(r'[+-]\d\d:\d\d$')));
    });

    test('detections newest first, id only with a clip', () {
      final rows = detections(all, 'Turdus merula', 4);
      expect(rows.length, 2);
      expect(rows.first['id'], isNull);
      expect(rows.last['id'], 1);
    });
  });

  group('media', () {
    test('wav header', () {
      final wav = encodeWav(Float32List(100), 48000);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(wav.length, 44 + 200);
    });

    test('spectrogram is a BMP', () {
      final bmp = spectrogramBmp(Float32List(48000), 48000);
      expect(String.fromCharCodes(bmp.sublist(0, 2)), 'BM');
    });
  });

  group('sessions', () {
    test('older detections split at gaps of over 30 minutes', () {
      final t0 = DateTime(2026, 11, 18, 6);
      final times = [
        t0,
        t0.add(const Duration(minutes: 10)),
        t0.add(const Duration(minutes: 35)), // 25 min gap: same session
        t0.add(const Duration(hours: 3)), // new session
      ];
      final spans = groupIntoSpans(times, legacySessionGap);
      expect(spans.length, 2);
      expect(spans.first.$2, times[2]);
      expect(spans.last.$1, times[3]);
    });

    test('a live session holds everything after its start', () {
      final s = Session(id: 1, start: DateTime(2026, 11, 18, 6));
      expect(s.contains(DateTime(2026, 11, 19)), isTrue);
      s.end = DateTime(2026, 11, 18, 7);
      expect(s.contains(DateTime(2026, 11, 18, 8)), isFalse);
      expect(s.contains(DateTime(2026, 11, 18, 6, 30)), isTrue);
    });
  });
}
