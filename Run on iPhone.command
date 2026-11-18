#!/bin/zsh -l
# Double-click in Finder with the iPhone plugged in and unlocked. Builds a
# release build, installs it and starts it. Output is saved to ios-log.txt.
cd "$(dirname "$0")"
{
  echo "=== $(date)"
  [ -f ~/.zshrc ] && source ~/.zshrc >/dev/null 2>&1
  export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
  python3 tool/patch_platforms.py
  flutter pub get >/dev/null
  python3 tool/patch_platforms.py
  flutter devices
  DEVICE=$(flutter devices --machine 2>/dev/null | python3 -c "
import json,sys
ds=[d for d in json.load(sys.stdin) if d.get('targetPlatform','').startswith('ios') and not d.get('emulator')]
print(ds[0]['id'] if ds else '')")
  if [ -z "$DEVICE" ]; then
    echo "STATUS: no-iphone  (plug it in, unlock it, trust this Mac, turn on Developer Mode)"
  else
    echo "Using device $DEVICE"
    flutter build ios --release && echo "STATUS: ios-build-ok"
    flutter install --release -d "$DEVICE" && echo "STATUS: ios-install-ok"
  fi
  echo "=== done $(date)"
} 2>&1 | tee ios-log.txt
echo
echo "Log saved to ios-log.txt. Open Birdsong on the iPhone. You can close this window."
