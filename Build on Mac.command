#!/bin/zsh -l
# Double-click in Finder. Sets the project up, checks it, builds the Mac app
# and opens it. Everything is also written to build-log.txt beside this file.
cd "$(dirname "$0")"
LOG="build-log.txt"
{
  echo "=== $(date)"
  [ -f ~/.zshrc ] && source ~/.zshrc >/dev/null 2>&1
  export PATH="$HOME/development/flutter/bin:$HOME/flutter/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
  echo "flutter: $(command -v flutter || echo MISSING)"
  echo "brew: $(command -v brew || echo MISSING)"
  echo "xcode: $(xcodebuild -version 2>&1 | head -1)"
  if ! command -v flutter >/dev/null 2>&1; then
    echo "STATUS: no-flutter"
    echo "Install Flutter first:  brew install --cask flutter"
  else
    ./tool/bootstrap.sh && echo "STATUS: bootstrap-ok"
    flutter analyze --no-fatal-infos --no-fatal-warnings && echo "STATUS: analyze-ok"
    flutter test && echo "STATUS: test-ok"
    flutter build macos --debug && echo "STATUS: build-ok"
    APP=$(ls -d build/macos/Build/Products/Debug/*.app 2>/dev/null | head -1)
    [ -n "$APP" ] && open "$APP" && echo "STATUS: opened $APP"
  fi
  echo "=== done $(date)"
} 2>&1 | tee "$LOG"
echo
echo "Log saved to $(pwd)/$LOG. You can close this window."
