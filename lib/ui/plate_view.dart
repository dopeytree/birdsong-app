import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app_state.dart';
import '../settings.dart';

/// Birdsong's own page, served by the app's local server.
class PlateView extends StatefulWidget {
  const PlateView({super.key, required this.app});

  final AppState app;

  @override
  State<PlateView> createState() => _PlateViewState();
}

class _PlateViewState extends State<PlateView> {
  late final WebViewController _web;
  late AppMode _mode;
  late String _plateModel;
  late String _station;

  Settings get _s => widget.app.settings;

  @override
  void initState() {
    super.initState();
    _mode = _s.mode;
    _plateModel = _s.plateModel;
    _station = '${_s.birdnetBase}|${_s.stationDigits}';
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse('${widget.app.server.origin}/'));
    _s.addListener(_settingsChanged);
  }

  @override
  void dispose() {
    _s.removeListener(_settingsChanged);
    super.dispose();
  }

  // The page reads its source once, so reload when the source changes.
  void _settingsChanged() {
    final station = '${_s.birdnetBase}|${_s.stationDigits}';
    if (_s.mode != _mode || _s.plateModel != _plateModel || station != _station) {
      _mode = _s.mode;
      _plateModel = _s.plateModel;
      _station = station;
      _web.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _web),
        Positioned(
          right: 8,
          top: 8,
          child: IconButton.filledTonal(
            tooltip: 'Reload the plate',
            icon: const Icon(Icons.refresh),
            onPressed: () => _web.reload(),
          ),
        ),
      ],
    );
  }
}
