#!/bin/zsh -l
# Double-click in Finder: opens the plate lab (lib/lab/plate_lab.dart) as a
# Mac window. The lab is a test screen, not the app: it tries the plate's
# look (multiply blends, cut-outs) in Flutter's own drawing.
cd "$(dirname "$0")"
[ -f ~/.zshrc ] && source ~/.zshrc >/dev/null 2>&1
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
flutter pub get >/dev/null
flutter run -d macos -t lib/lab/plate_lab.dart
