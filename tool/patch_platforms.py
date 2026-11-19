#!/usr/bin/env python3
"""Apply Birdsong's platform settings to the projects `flutter create` made.

Safe to run again: every change checks before it writes.

iOS and macOS: microphone and local-network wording, background audio (iOS),
App Transport Security for the page served on 127.0.0.1 and plain-HTTP
BirdNET-Go stations, sandbox entitlements (macOS), and the minimum OS
(iOS 18, so iOS 18, 26 and 27; macOS 14, which ONNX Runtime needs).

Android: microphone and internet permissions, plain HTTP to the local page
and LAN stations, the ONNX Runtime ProGuard rule, minSdk 24.

TEST BUILD: NSAllowsArbitraryLoads and cleartext everywhere are for testing
against LAN stations; tighten both before a store release.
"""
import os
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

MIC = ("Birdsong listens for birds and identifies them on this device. "
       "Audio never leaves it.")
LOC = ("Birdsong marks each listening session with where it happened, and leaves "
       "out birds that don't live there.")
LAN = "Birdsong reads detections from your BirdNET-Go station on your home network."

# Built with the iOS 27 SDK; runs on iOS 27 and the two releases before it
# (iOS 26 and iOS 18: Apple went from 18 straight to 26).
IOS_MIN = "18.0"

ATS = {"NSAllowsArbitraryLoads": True, "NSAllowsLocalNetworking": True}


def say(msg):
    print(f"  {msg}")


def patch_plist(path, changes):
    if not path.exists():
        say(f"skip {path.relative_to(ROOT)} (not there)")
        return
    with path.open("rb") as f:
        data = plistlib.load(f)
    before = dict(data)
    for k, v in changes.items():
        data[k] = v
    if data != before:
        with path.open("wb") as f:
            plistlib.dump(data, f)
        say(f"updated {path.relative_to(ROOT)}")


def patch_text(path, pattern, repl, flags=0):
    if not path.exists():
        return
    text = path.read_text()
    new, n = re.subn(pattern, repl, text, flags=flags)
    if new != text:
        path.write_text(new)
        say(f"updated {path.relative_to(ROOT)} ({n} change{'s' if n != 1 else ''})")


PHOTOS = "Birdsong saves pictures of your plates to Photos when you ask it to."


BUNDLE = "uk.co.edstone.birdsongApp"


def ios():
    # BIRDSONG_COPY=<MMDDHHMM> (Run on iPhone as a copy.command): a separate
    # app with its own ID, name and data; unset puts the usual app back.
    copy = os.environ.get("BIRDSONG_COPY", "").strip()
    name = f"Birdsong {copy[4:6]}:{copy[6:8]}" if len(copy) == 8 else "Birdsong"
    patch_text(ROOT / "ios/Runner.xcodeproj/project.pbxproj",
               r"PRODUCT_BUNDLE_IDENTIFIER = " + re.escape(BUNDLE) + r"(\.copy\d+)?;",
               f"PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE}{'.copy' + copy if copy else ''};")
    patch_plist(ROOT / "ios/Runner/Info.plist", {
        "NSPhotoLibraryAddUsageDescription": PHOTOS,
        "CFBundleDisplayName": name,
        "NSMicrophoneUsageDescription": MIC,
        "NSLocalNetworkUsageDescription": LAN,
        "NSLocationWhenInUseUsageDescription": LOC,
        "UIBackgroundModes": ["audio"],
        "NSAppTransportSecurity": ATS,
    })
    podfile = ROOT / "ios/Podfile"
    patch_text(podfile, r"^#?\s*platform :ios, '[\d.]+'", f"platform :ios, '{IOS_MIN}'", re.M)
    patch_text(podfile, r"^(\s*)use_frameworks!\s*$", r"\1use_frameworks! :linkage => :static", re.M)
    patch_text(ROOT / "ios/Runner.xcodeproj/project.pbxproj",
               r"IPHONEOS_DEPLOYMENT_TARGET = [^;]+;", f"IPHONEOS_DEPLOYMENT_TARGET = {IOS_MIN};")
    # Flutter writes the minimum iOS into the Swift package it generates for
    # the plugins; ONNX Runtime refuses anything below 16.
    patch_text(ROOT / "ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift",
               r'\.iOS\("[\d.]+"\)', f'.iOS("{IOS_MIN}")')


PAPER = (0xEE, 0xE5, 0xCE)


def ios_launch():
    """The launch screen: the cardinal on paper, as the app's loading screen
    then shows it, so one hands over to the other."""
    board = ROOT / "ios/Runner/Base.lproj/LaunchScreen.storyboard"
    r, g, b = (round(c / 255, 4) for c in PAPER)
    patch_text(board, r'(<color key="backgroundColor") red="[\d.]+" green="[\d.]+" blue="[\d.]+"',
               rf'\1 red="{r}" green="{g}" blue="{b}"')
    # The cardinal a little above the middle, as the loading screen has it
    # (cardinalLift in lib/ui/splash.dart).
    patch_text(board, r'(<constraint firstItem="YRO-k0-Ey4" firstAttribute="centerY" '
               r'secondItem="Ze5-6b-2t3" secondAttribute="centerY")( constant="[-\d.]+")?',
               r'\1 constant="-56"')
    images = ROOT / "ios/Runner/Assets.xcassets/LaunchImage.imageset"
    if images.is_dir():
        for src in sorted((ROOT / "tool/launch").glob("LaunchImage*.png")):
            dst = images / src.name
            if not dst.exists() or dst.read_bytes() != src.read_bytes():
                dst.write_bytes(src.read_bytes())
                say(f"updated {dst.relative_to(ROOT)}")


def android_launch():
    for d in ("drawable", "drawable-v21"):
        patch_text(ROOT / f"android/app/src/main/res/{d}/launch_background.xml",
                   r'<item android:drawable="[^"]*" />',
                   '<item><color android:color="#EEE5CE" /></item>')


def macos():
    patch_plist(ROOT / "macos/Runner/Info.plist", {
        "NSMicrophoneUsageDescription": MIC,
        "NSLocationUsageDescription": LOC,
        "NSLocationWhenInUseUsageDescription": LOC,
        "NSPhotoLibraryAddUsageDescription": PHOTOS,
        "NSAppTransportSecurity": ATS,
    })
    ent = {
        "com.apple.security.personal-information.photos-library": True,
        "com.apple.security.app-sandbox": True,
        "com.apple.security.network.client": True,
        "com.apple.security.network.server": True,
        "com.apple.security.device.audio-input": True,
        "com.apple.security.personal-information.location": True,
    }
    for name in ("DebugProfile.entitlements", "Release.entitlements"):
        patch_plist(ROOT / "macos/Runner" / name, ent)
    patch_text(ROOT / "macos/Podfile", r"^#?\s*platform :osx, '[\d.]+'", "platform :osx, '14.0'", re.M)
    patch_text(ROOT / "macos/Runner.xcodeproj/project.pbxproj",
               r"MACOSX_DEPLOYMENT_TARGET = [^;]+;", "MACOSX_DEPLOYMENT_TARGET = 14.0;")


def android():
    manifest = ROOT / "android/app/src/main/AndroidManifest.xml"
    if manifest.exists():
        text = manifest.read_text()
        perms = ["android.permission.RECORD_AUDIO", "android.permission.INTERNET",
                 "android.permission.ACCESS_COARSE_LOCATION",
                 "android.permission.ACCESS_FINE_LOCATION"]
        add = "".join(f'    <uses-permission android:name="{p}"/>\n'
                      for p in perms if p not in text)
        if add:
            text = text.replace("<application", add + "    <application", 1)
        if "usesCleartextTraffic" not in text:
            text = text.replace("<application", '<application\n        android:usesCleartextTraffic="true"', 1)
        if text != manifest.read_text():
            manifest.write_text(text)
            say("updated android/app/src/main/AndroidManifest.xml")
    rules = ROOT / "android/app/proguard-rules.pro"
    rule = "-keep class ai.onnxruntime.** { *; }"
    if not rules.exists() or rule not in rules.read_text():
        if rules.parent.exists():
            with rules.open("a") as f:
                f.write(rule + "\n")
            say("updated android/app/proguard-rules.pro")
    for gradle in (ROOT / "android/app/build.gradle.kts", ROOT / "android/app/build.gradle"):
        patch_text(gradle, r"minSdk(Version)?\s*=?\s*flutter\.minSdkVersion", r"minSdk = 24")


def main():
    print("Patching platform projects")
    ios()
    ios_launch()
    macos()
    android()
    android_launch()
    print("Done")


if __name__ == "__main__":
    sys.exit(main())
