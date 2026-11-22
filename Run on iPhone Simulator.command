#!/bin/zsh
# Build the app for the iPhone Simulator on this Mac, install it and open it.
# Unsigned debug build; never touches a real iPhone or its data.
# Writes sim-log.txt for Claude to read.
cd "$(dirname "$0")"
LOG="sim-log.txt"
{
  echo "=== $(date)"
  [ -f ~/.zshrc ] && source ~/.zshrc >/dev/null 2>&1
  export PATH="$HOME/development/flutter/bin:$HOME/flutter/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
  echo "commit: $(git log --oneline -1)"
  python3 tool/patch_platforms.py
  flutter pub get >/dev/null
  python3 tool/patch_platforms.py

  # A simulator already running, else the newest available iPhone.
  SIM=$(xcrun simctl list devices available -j 2>/dev/null | python3 -c "
import json,sys
ds=[d for rt,l in json.load(sys.stdin)['devices'].items() if 'iOS' in rt for d in l]
on=[d for d in ds if d['state']=='Booted']
ph=[d for d in ds if d['name'].startswith('iPhone')]
pro=[d for d in ph if d['name'].endswith(' Pro')]
pick=(on or pro[::-1] or ph[::-1] or [{}])[0]
print(pick.get('udid',''), pick.get('name',''), sep='|')")
  UDID=${SIM%%|*}
  NAME=${SIM#*|}

  if [ -z "$UDID" ]; then
    echo "STATUS: no-simulator  (Xcode > Settings > Components: get the iOS simulator)"
  else
    echo "Using simulator $NAME ($UDID)"
    xcrun simctl boot "$UDID" 2>/dev/null
    open -a Simulator
    if flutter build ios --simulator --debug; then
      echo "STATUS: sim-build-ok"
      APP=build/ios/iphonesimulator/Runner.app
      BUNDLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")
      xcrun simctl install "$UDID" "$APP" && echo "STATUS: sim-install-ok"
      xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null && echo "STATUS: launched $BUNDLE"
    else
      echo "STATUS: sim-build-failed"
    fi
  fi
  echo "=== done $(date)"
} 2>&1 | tee "$LOG"
echo
echo "Log saved to $(pwd)/$LOG. You can close this window."
