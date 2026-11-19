#!/bin/zsh -l
# Double-click in Finder with the iPhone plugged in and unlocked. Builds a
# release build and installs it over the Birdsong already on the phone,
# keeping its sessions, recordings and models, then starts it. Output is
# saved to ios-log.txt. (For a separate copy beside it, use
# "Run on iPhone as a copy.command".)
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
    # devicectl upgrades in place, so the app's data stays; flutter install
    # uninstalls first and loses it.
    if xcrun devicectl device install app --device "$DEVICE" build/ios/iphoneos/Runner.app; then
      echo "STATUS: ios-install-ok (data kept)"
      BUNDLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" build/ios/iphoneos/Runner.app/Info.plist)
      xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE" >/dev/null 2>&1 && echo "STATUS: launched $BUNDLE"
    else
      echo "STATUS: ios-install-failed (devicectl); not falling back to flutter install, which would erase the app's data"
    fi
  fi
  echo "=== done $(date)"
} 2>&1 | tee ios-log.txt
# A copy run leaves the project set back to the normal app.
[ -n "$BIRDSONG_COPY" ] && BIRDSONG_COPY= python3 tool/patch_platforms.py >/dev/null
echo
echo "Log saved to ios-log.txt. Open Birdsong on the iPhone. You can close this window."
