# Birdsong app (test build)

Birdsong for iPhone, iPad, Mac and Android. The plate is
[Birdsong](https://github.com/dopeytree/birdsong)'s own `index.html`, shown in
a native web view and fed by a small web server inside the app. That server
does what nginx does in the Docker image, in one of two modes:

- **Station:** `/api` is forwarded to your BirdNET-Go, or `/graphql` to a
  public BirdWeather station.
- **Listen here:** the app listens through the microphone, runs BirdNET (and
  friends) on the device, and answers the same BirdNET-Go endpoints from what
  it heard. Recordings and spectrograms included.

This is a **test build**: it can download every model below so they can be
compared side by side, including ones that can't ship in a paid app.

## Set up on a Mac

You need Xcode (installed) and Flutter.

```sh
brew install --cask flutter      # if `flutter` isn't installed yet
cd ~/birdsong-app
./tool/bootstrap.sh              # makes the iOS/macOS/Android projects, once
```

### Run it on the Mac

```sh
flutter run -d macos
```

### Run it on your iPhone

1. Plug the iPhone in, unlock it, and trust the Mac.
2. On the iPhone: Settings > Privacy & Security > Developer Mode > on (it restarts).
3. `open ios/Runner.xcworkspace`, select **Runner** > **Signing & Capabilities**,
   tick *Automatically manage signing* and choose your Apple ID as the Team
   (Xcode > Settings > Accounts to add it). A free Apple ID works; its builds
   expire after 7 days, so just run again.
4. Back in Terminal: `flutter devices`, then
   `flutter run --release -d <the iPhone's id>`.
   Use `--release` (or `--profile`): debug builds run Dart far slower.
5. First launch on the phone: Settings > General > VPN & Device Management >
   trust your developer certificate, if iOS asks.

### Tests

```sh
flutter test
```

## Using it

0. First launch walks you through it: choose *This device listens* or
   *I have a station*, download a model, switch on Core ML, allow the
   microphone. Settings > *Show the welcome screens again* repeats it.
1. **Models** tab: download one or more models. Start with
   *BirdNET+ V3.0 Global 10K, FP16* (67 MB), the build BirdNET Live ships.
2. Tick **Listen** on each model to run. Every window goes through every
   ticked model, so you can compare speed and results. Choose which model the
   plate draws (**On the plate**), or all of them.
3. **Listen** tab: Start listening. Each model card shows the time per window
   and its top five species. Detections above the threshold are saved, with a
   recording and a spectrogram.
4. **Plate** tab: the familiar plate, cards, recordings and spectrograms.
5. **Settings**: switch between *Station* and *Listen here*, set a
   BirdNET-Go address or a BirdWeather station, the threshold, how often to
   analyse, the location filter, and Core ML (experimental) on Apple devices.

On iPhone the app keeps listening with the screen locked (the orange
microphone dot shows).

## Models

Downloaded by the app at runtime into its own folder; none are committed.

| Model | Size | Licence | In a paid release? |
| --- | --- | --- | --- |
| BirdNET+ V3.0 Global 10K FP16 (BirdNET Live build) | 67 MB | Apache-2.0 | Yes |
| BirdNET+ V3.0 British Isles FP32 | 121 MB | Apache-2.0 | Yes |
| BirdNET+ V3.0 Global FP32 | 361 MB | Apache-2.0 | Yes |
| BirdNET V3.0 preview 3.1 British Isles FP16 | 70 MB | CC BY-SA 4.0 | Yes, superseded |
| Google Perch v2 British Isles FP32 | 68 MB | Apache-2.0 | Yes |
| Google Perch v2 Global FP32 | 413 MB | Apache-2.0 | Yes |
| BirdNET v2.4 FP32 | 54 MB | CC BY-NC-SA 4.0 | **No: testing only** |
| BirdNET+ Geomodel V3.0.4 (location filter) | 8 MB | Apache-2.0 | Yes |

Sources: the BirdNET+ V3.0 10K model and geomodel come from
[BirdNET Live](https://github.com/birdnet-team/birdnet-live-app) (pinned
commit); the rest from the Hugging Face repositories BirdNET-Go's model
gallery uses (`tphakala/BirdNET-Plus-V3.0`, `tphakala/BirdNET-v3.0-Models`,
`tphakala/Perch-v2-Models`, `tphakala/BirdNET-v2.4`). Confirm each licence
with its authors before a release; "Powered by BirdNET" credit is required
for BirdNET models.

## How it fits together

```
lib/
  main.dart, app_state.dart   start-up, shared state
  settings.dart               everything in Settings, saved as JSON
  engine/
    model_catalog.dart        the models above: URLs, rates, windows
    model_manager.dart        downloads, what's installed
    listen_engine.dart        mic -> ring buffers -> models -> detections
    resampler.dart            48 kHz -> 32 kHz polyphase filter
    classifier.dart           ONNX Runtime sessions, scores, geomodel
    labels.dart               every label format in use
  server/
    local_server.dart         127.0.0.1 server: page, source.json, /api
    local_api.dart            the 8 BirdNET-Go endpoints, from local data
  store/
    detection_store.dart      detections (JSON lines) and clips
    media.dart                WAV, FFT, spectrogram BMP
  ui/                         Plate, Listen, Models, Settings
assets/web/                   Birdsong's index.html and fonts (v0.42)
tool/bootstrap.sh             one-time set-up
tool/patch_platforms.py       plist, entitlements, deployment targets
```

The page is a copy of `html/index.html` from the `birdsong` repo. The
Fugleramme artwork isn't bundled yet: the page falls back to fetching it from
GitHub, as it does without a local copy.

## Licence

Code: MIT. Bird cut-outs: Fugleramme, CC BY-SA 4.0. Typeface: IM Fell
English, SIL OFL (`assets/web/fonts/OFL.txt`). Models: see the table above.
