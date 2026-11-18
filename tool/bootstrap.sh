#!/usr/bin/env bash
# One-time set-up on a Mac: makes the iOS, macOS and Android projects,
# applies Birdsong's platform settings and fetches the Dart packages.
# Safe to run again.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v flutter >/dev/null 2>&1; then
  cat <<'EOF'
Flutter isn't installed. On a Mac with Homebrew:

    brew install --cask flutter

or follow https://docs.flutter.dev/get-started/install/macos
Then run this script again.
EOF
  exit 1
fi

echo "Flutter: $(flutter --version 2>/dev/null | head -1)"

# ONNX Runtime, the microphone plugin and the web view all ship Swift
# packages, so no CocoaPods is needed. (This is a Flutter-wide setting.)
flutter config --enable-swift-package-manager >/dev/null

if [ ! -d ios ] || [ ! -d macos ] || [ ! -d android ]; then
  echo "Creating platform projects"
  flutter create --org uk.co.edstone --project-name birdsong_app \
    --platforms=ios,macos,android . >/dev/null
fi

# flutter create adds a counter-app test that doesn't apply here.
if [ -f test/widget_test.dart ] && grep -q "MyApp" test/widget_test.dart; then
  rm test/widget_test.dart
fi

python3 tool/patch_platforms.py
flutter pub get

cat <<'EOF'

Ready.
  Mac:     flutter run -d macos
  iPhone:  open ios/Runner.xcworkspace, pick your Apple ID team under
           Runner > Signing & Capabilities, then:
           flutter run --release -d <your iPhone>   (see: flutter devices)
  Tests:   flutter test
EOF
