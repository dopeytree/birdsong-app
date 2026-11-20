#!/usr/bin/env python3
"""Bring the Birdsong web page into the app.

The app ships dopeytree/birdsong's html/ folder unchanged, in assets/web/.
Everything the app does differently is added at serve time by
lib/server/local_server.dart, so updating is a copy plus a check that the
parts the app hooks into are still there (tool/web_contract.json).

  python3 tool/sync_web.py                 # latest main from GitHub
  python3 tool/sync_web.py --ref v0.43     # a tag, branch or commit
  python3 tool/sync_web.py --from ~/birdsong   # a local checkout, as it is
  python3 tool/sync_web.py --check         # only check the current copy

It writes assets/web/UPSTREAM.json (repo, commit, version) and prints what
changed upstream since the last sync. Exit 1 means a hook or endpoint
broke: see the report.
"""
import argparse
import filecmp
import json
import os
import re
import shutil
import subprocess
import sys

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEB = os.path.join(APP, "assets", "web")
CONTRACT = os.path.join(APP, "tool", "web_contract.json")
STAMP = os.path.join(WEB, "UPSTREAM.json")
CACHE = os.path.join(APP, ".upstream", "birdsong")
REPO = "https://github.com/dopeytree/birdsong.git"


def git(cwd, *args, check=True):
    r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    if check and r.returncode:
        sys.exit("git %s failed:\n%s" % (" ".join(args), r.stderr.strip()))
    return r.stdout.strip()


def fetch(ref):
    if not os.path.isdir(os.path.join(CACHE, ".git")):
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        print("Cloning %s ..." % REPO)
        subprocess.run(["git", "clone", "-q", REPO, CACHE], check=True)
    git(CACHE, "fetch", "-q", "--tags", "origin")
    target = ref if git(CACHE, "rev-parse", "-q", "--verify", ref + "^{commit}", check=False) \
        else "origin/" + ref
    git(CACHE, "checkout", "-q", "--detach", target)
    return CACHE


def answers(served, used):
    """Exact path, or under a served folder ("/api/v2/audio/" + id), or the
    page's own folder prefix it builds paths from."""
    return used == served or (served.endswith("/") and used.startswith(served)) \
        or (used.endswith("/") and served.startswith(used))


def check(html, contract):
    problems, notes = [], []
    for h in contract["hooks"]:
        n = html.count(h["find"])
        if n == 0:
            problems.append("missing  %-40s <- %s" % (h["find"], h["used_by"]))
        elif n > 1 and h["find"].startswith("id="):
            notes.append("twice    %s" % h["find"])
    used = set(re.findall(r'/api/v2/[A-Za-z0-9_/]*[A-Za-z0-9_/]', html))
    served = contract["endpoints"]
    for u in sorted(used):
        if not any(answers(e, u) for e in served):
            problems.append("endpoint %-40s <- new call; listen mode doesn't answer it "
                            "(lib/server/local_api.dart + local_server.dart _local)" % u)
    for e in served:
        if not any(answers(e, u) for u in used):
            notes.append("unused   %s (the page no longer calls it)" % e)
    return problems, notes


def fonts_declared():
    pub = open(os.path.join(APP, "pubspec.yaml")).read()
    return set(re.findall(r"assets/web/fonts/([^\s]+\.ttf)", pub))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", default="main")
    ap.add_argument("--from", dest="src")
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    contract = json.load(open(CONTRACT))
    old = json.load(open(STAMP)) if os.path.exists(STAMP) else {}

    if not a.check:
        src = os.path.abspath(os.path.expanduser(a.src)) if a.src else fetch(a.ref)
        html_dir = os.path.join(src, "html")
        if not os.path.isfile(os.path.join(html_dir, "index.html")):
            sys.exit("No html/index.html in %s" % src)
        added, changed = [], []
        for root, _, files in os.walk(html_dir):
            for f in files:
                s = os.path.join(root, f)
                rel = os.path.relpath(s, html_dir)
                d = os.path.join(WEB, rel)
                if not os.path.exists(d):
                    added.append(rel)
                elif filecmp.cmp(s, d, shallow=False):
                    continue
                else:
                    changed.append(rel)
                os.makedirs(os.path.dirname(d), exist_ok=True)
                shutil.copyfile(s, d)
        gone = []
        for root, _, files in os.walk(WEB):
            for f in files:
                rel = os.path.relpath(os.path.join(root, f), WEB)
                if rel != "UPSTREAM.json" and not os.path.exists(os.path.join(html_dir, rel)):
                    gone.append(rel)
        is_git = os.path.isdir(os.path.join(src, ".git"))
        commit = git(src, "rev-parse", "HEAD") if is_git else "local"
        dirty = is_git and bool(git(src, "status", "--porcelain", "--", "html"))
        version = open(os.path.join(src, "VERSION")).read().strip() \
            if os.path.exists(os.path.join(src, "VERSION")) else "?"
        stamp = {"repo": "dopeytree/birdsong", "commit": commit + ("+local" if dirty else ""),
                 "version": version,
                 "date": git(src, "log", "-1", "--format=%cI") if is_git else None}
        json.dump(stamp, open(STAMP, "w"), indent=2)
        open(STAMP, "a").write("\n")

        print("Birdsong %s (%s), was %s (%s)" % (version, commit[:7], old.get("version", "-"),
                                               str(old.get("commit", "-"))[:7]))
        print("changed: %s" % (", ".join(changed) or "nothing"))
        if added:
            print("new:     %s" % ", ".join(added))
        if gone:
            print("gone upstream (left in place, remove by hand): %s" % ", ".join(gone))
        new_fonts = [f for f in added if f.startswith("fonts/") and f.endswith(".ttf")
                     and f[6:] not in fonts_declared()]
        if new_fonts:
            print("fonts not in pubspec.yaml (native screens won't have them): %s"
                  % ", ".join(new_fonts))
        prev = str(old.get("commit", "")).split("+")[0]
        if is_git and prev and prev != "local" and prev != commit:
            log = git(src, "log", "--oneline", "%s..%s" % (prev, commit), "--", "html", check=False)
            if log:
                print("\nUpstream changes to the page:\n" + log)

    html = open(os.path.join(WEB, "index.html"), encoding="utf-8").read()
    problems, notes = check(html, contract)
    print()
    for n in notes:
        print("note     " + n)
    if problems:
        print("BROKEN — the app relies on these:")
        for p in problems:
            print("  " + p)
        sys.exit(1)
    print("Contract OK: %d hooks, %d endpoints." % (len(contract["hooks"]), len(contract["endpoints"])))


if __name__ == "__main__":
    main()
