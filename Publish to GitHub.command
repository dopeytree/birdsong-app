#!/bin/zsh -l
# Double-click in Finder. Creates the private GitHub repo dopeytree/birdsongs.ai
# (once) with your own GitHub CLI login, then pushes every branch to it.
# Run it again any time to push new work. Log: github-log.txt beside this file.
cd "$(dirname "$0")"
{
  echo "=== $(date)"
  [ -f ~/.zshrc ] && source ~/.zshrc >/dev/null 2>&1
  export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
  if ! command -v gh >/dev/null 2>&1; then
    echo "STATUS: no-gh  (brew install gh, then: gh auth login)"
  elif ! gh auth status >/dev/null 2>&1; then
    echo "STATUS: gh-not-logged-in  (run: gh auth login)"
    gh auth status 2>&1 | sed 's/^/  gh: /'
    # git may still hold a sign-in of its own: try, without stopping to ask
    GIT_TERMINAL_PROMPT=0 git push -u origin --all && git push origin --tags && echo "STATUS: pushed"
  else
    gh auth setup-git >/dev/null 2>&1
    if ! git remote get-url origin >/dev/null 2>&1; then
      if gh repo view dopeytree/birdsongs.ai >/dev/null 2>&1; then
        git remote add origin https://github.com/dopeytree/birdsongs.ai.git
      else
        gh repo create dopeytree/birdsongs.ai --private \
          --description "Birdsong as an iPhone, iPad, Mac and Android app: the plate, with BirdNET on the device" \
          --source=. --remote=origin && echo "STATUS: repo-created"
      fi
    fi
    git push -u origin --all && git push origin --tags && echo "STATUS: pushed"
    gh repo view dopeytree/birdsongs.ai --json visibility,url,defaultBranchRef \
      -q '"visibility: \(.visibility)  default: \(.defaultBranchRef.name)  \(.url)"'
    git branch -vv
  fi
  echo "=== done $(date)"
} 2>&1 | tee github-log.txt
