#!/bin/zsh -l
# Double-click in Finder: opens the plate lab in Chrome, as Flutter web.
# The first run adds Flutter's web folder to the project. To try the
# WebAssembly build instead, add --wasm to the last line.
cd "$(dirname "$0")"
[ -f ~/.zshrc ] && source ~/.zshrc >/dev/null 2>&1
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if [ ! -d web ]; then
  flutter create --org uk.co.edstone --project-name birdsong_app --platforms=web . >/dev/null
  # flutter create adds a counter-app test that doesn't apply here.
  [ -f test/widget_test.dart ] && grep -q "MyApp" test/widget_test.dart && rm test/widget_test.dart
fi
flutter pub get >/dev/null
flutter run -d chrome -t lib/lab/plate_lab.dart
