import 'dart:convert';

import 'package:webview_flutter/webview_flutter.dart';

/// The plate page's own Display options (what it shows, how creatures are
/// sized and marked), worked from the app's Settings. The page keeps them in
/// its storage; this reads them and sets them through the page's own
/// controls, so the page does exactly what its Display dialog would.
class PageControl {
  PageControl(this._web);

  final WebViewController _web;

  /// Parts of the plate that can be shown or hidden, with their labels.
  static const parts = {
    'title': 'Title',
    'date': 'Date',
    'totals': 'Species and call totals',
    'periods': 'Today / 7 days / 30 days / all',
    'index': 'Index of species',
    'plate': 'The collage of birds',
  };

  static const sizeBy = {
    'calls': 'Noisiest species',
    'time': 'Recent ramblings',
    'equal': 'No pecking order',
  };

  static const markAt = {
    'centre': 'A dot over its centre',
    'below': 'A dot below it',
    'fade': 'The rest faded',
  };

  Future<Map<String, Object?>?> read() async {
    try {
      Object? v = await _web.runJavaScriptReturningResult('JSON.stringify({'
          'fit:!!fit,parts:!!store.get("parts",false),limit:opt.limit||0,'
          'markAt:opt.markAt,sizeBy:opt.sizeBy,mark:!!opt.mark,'
          '${parts.keys.map((k) => '$k:!!opt.$k').join(',')}})');
      // iOS hands back the string itself, Android a JSON encoding of it.
      for (var i = 0; i < 2 && v is String; i++) {
        v = jsonDecode(v);
      }
      return v is Map ? v.cast<String, Object?>() : null;
    } catch (_) {
      return null;
    }
  }

  /// Set one option: [key] is a part name, or fit, parts, limit, mark,
  /// markAt or sizeBy.
  Future<void> set(String key, Object value) {
    final selector = switch (key) {
      'fit' => '#fitOpt',
      'parts' => '#partsOpt',
      'limit' => '#lim',
      'markAt' => '#markAt',
      'sizeBy' => '#sizeBy',
      _ => '#showOpts [data-opt="$key"]',
    };
    return _web
        .runJavaScript('(function(){var e=document.querySelector(${jsonEncode(selector)});'
            'if(!e)return;var v=${jsonEncode(value)};'
            'if(e.type==="checkbox")e.checked=v;else e.value=v;'
            'e.dispatchEvent(new Event("change"))})()')
        .catchError((Object _) {});
  }
}
