#!/bin/zsh -l
# Double-click in Finder. Copies the latest Birdsong web page (dopeytree/birdsong,
# html/) into the app, checks the app's hooks still fit, and runs the tests.
# Then run "Build on Mac.command". Log: web-log.txt beside this file.
cd "$(dirname "$0")"
LOG="web-log.txt"
{
  echo "=== $(date)"
  [ -f ~/.zshrc ] && source ~/.zshrc >/dev/null 2>&1
  export PATH="$HOME/development/flutter/bin:$HOME/flutter/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
  if python3 tool/sync_web.py "${@:---ref=main}"; then
    echo "STATUS: sync-ok"
    flutter test test/web_contract_test.dart && echo "STATUS: contract-test-ok"
  else
    echo "STATUS: sync-broken"
  fi
  git status --short assets/web
  echo "=== done $(date)"
} 2>&1 | tee "$LOG"
