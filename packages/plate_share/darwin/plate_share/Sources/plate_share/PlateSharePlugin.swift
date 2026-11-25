// Takes a picture of the app's web view (the plate) with WKWebView's own
// snapshot, which leaves out the Flutter buttons drawn over it, writes it
// as a PNG and opens the system share sheet with it. The plate drawn by
// Flutter sends its own picture instead (the png argument).

#if os(iOS)
import Flutter
import UIKit
#elseif os(macOS)
import FlutterMacOS
import AppKit
#endif
import AVFoundation
import Photos
import WebKit

public class PlateSharePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
    let messenger = registrar.messenger()
    #else
    let messenger = registrar.messenger
    #endif
    let channel = FlutterMethodChannel(
      name: "uk.co.edstone.birdsong/plate_share", binaryMessenger: messenger)
    registrar.addMethodCallDelegate(PlateSharePlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let png = (args["png"] as? FlutterStandardTypedData)?.data
    if call.method == "save" {
      DispatchQueue.main.async { self.save(png: png, result: result) }
      return
    }
    if call.method == "fullBleed" {
      DispatchQueue.main.async { self.fullBleed(result: result) }
      return
    }
    if call.method == "encodeAac" {
      guard let inputPath = args["inputPath"] as? String,
            let outputPath = args["outputPath"] as? String else {
        result(false)
        return
      }
      let bitrate = (args["bitrate"] as? Int) ?? 128000
      DispatchQueue.global(qos: .utility).async {
        self.encodeAac(inputPath: inputPath, outputPath: outputPath, bitrate: bitrate) { ok in
          DispatchQueue.main.async { result(ok) }
        }
      }
      return
    }
    if call.method == "icloudContainerPath" {
      let containerId = args["containerId"] as? String
      DispatchQueue.global(qos: .utility).async {
        let url = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
        guard let docs = url?.appendingPathComponent("Documents") else {
          DispatchQueue.main.async { result(nil) }
          return
        }
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        DispatchQueue.main.async { result(docs.path) }
      }
      return
    }
    if call.method == "icloudStartDownload" {
      guard let path = args["path"] as? String else {
        result(false)
        return
      }
      DispatchQueue.global(qos: .utility).async {
        do {
          try FileManager.default.startDownloadingUbiquitousItem(at: URL(fileURLWithPath: path))
          DispatchQueue.main.async { result(true) }
        } catch {
          DispatchQueue.main.async { result(false) }
        }
      }
      return
    }
    guard call.method == "share" else {
      result(FlutterMethodNotImplemented)
      return
    }
    let text = args["text"] as? String
    let anchor = CGRect(
      x: (args["x"] as? Double) ?? 0, y: (args["y"] as? Double) ?? 0,
      width: (args["w"] as? Double) ?? 1, height: (args["h"] as? Double) ?? 1)
    DispatchQueue.main.async { self.share(text: text, anchor: anchor, png: png, result: result) }
  }

  /// Encodes a WAV file into an AAC (.m4a) file using AVAssetReader + AVAssetWriter.
  private func encodeAac(inputPath: String, outputPath: String, bitrate: Int, done: @escaping (Bool) -> Void) {
    let inputUrl = URL(fileURLWithPath: inputPath)
    let outputUrl = URL(fileURLWithPath: outputPath)
    let tmpUrl = outputUrl.deletingLastPathComponent()
      .appendingPathComponent(".\(outputUrl.lastPathComponent).tmp.m4a")
    try? FileManager.default.removeItem(at: tmpUrl)
    let asset = AVURLAsset(url: inputUrl)
    guard let track = asset.tracks(withMediaType: .audio).first else {
      done(false)
      return
    }
    var sampleRate: Double = 48000
    var channels: Int = 1
    if let desc = track.formatDescriptions.first {
      let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc as! CMAudioFormatDescription)?.pointee
      if let asbd = asbd {
        if asbd.mSampleRate > 0 { sampleRate = asbd.mSampleRate }
        if asbd.mChannelsPerFrame > 0 { channels = Int(asbd.mChannelsPerFrame) }
      }
    }
    do {
      let reader = try AVAssetReader(asset: asset)
      let readerSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
      ]
      let readerOut = AVAssetReaderTrackOutput(track: track, outputSettings: readerSettings)
      guard reader.canAdd(readerOut) else { done(false); return }
      reader.add(readerOut)

      let writer = try AVAssetWriter(outputURL: tmpUrl, fileType: .m4a)
      let writerSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVEncoderBitRateKey: bitrate,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: channels,
      ]
      let writerIn = AVAssetWriterInput(mediaType: .audio, outputSettings: writerSettings)
      writerIn.expectsMediaDataInRealTime = false
      guard writer.canAdd(writerIn) else { done(false); return }
      writer.add(writerIn)

      guard reader.startReading(), writer.startWriting() else {
        try? FileManager.default.removeItem(at: tmpUrl)
        done(false)
        return
      }
      writer.startSession(atSourceTime: .zero)

      let queue = DispatchQueue(label: "uk.co.edstone.birdsong.aac")
      writerIn.requestMediaDataWhenReady(on: queue) {
        while writerIn.isReadyForMoreMediaData {
          if let buf = readerOut.copyNextSampleBuffer() {
            writerIn.append(buf)
          } else {
            writerIn.markAsFinished()
            writer.finishWriting {
              if writer.status == .completed {
                do {
                  try? FileManager.default.removeItem(at: outputUrl)
                  try FileManager.default.moveItem(at: tmpUrl, to: outputUrl)
                  done(true)
                } catch {
                  try? FileManager.default.removeItem(at: tmpUrl)
                  done(false)
                }
              } else {
                try? FileManager.default.removeItem(at: tmpUrl)
                done(false)
              }
            }
            return
          }
        }
      }
    } catch {
      try? FileManager.default.removeItem(at: tmpUrl)
      done(false)
    }
  }

  /// The picture to share or save: the one Flutter sent, else the web view's.
  private func picture(_ png: Data?, _ done: @escaping (URL?) -> Void) {
    if let png = png {
      done(pngFile(png))
    } else {
      snapshot(done)
    }
  }

  private func pngFile(_ data: Data?) -> URL? {
    guard let data = data else { return nil }
    let stamp = Int(Date().timeIntervalSince1970)
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("Birdsong-\(stamp).png")
    do {
      try data.write(to: url, options: .atomic)
      return url
    } catch {
      return nil
    }
  }

  /// Adds the plate's picture to Photos (add-only access).
  private func save(png: Data?, result: @escaping FlutterResult) {
    picture(png) { url in
      guard let url = url else {
        result("failed")
        return
      }
      let add = {
        PHPhotoLibrary.shared().performChanges({
          PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
        }) { ok, _ in DispatchQueue.main.async { result(ok ? "saved" : "failed") } }
      }
      if #available(iOS 14, macOS 11, *) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
          if status == .authorized || status == .limited {
            add()
          } else {
            DispatchQueue.main.async { result("denied") }
          }
        }
      } else {
        PHPhotoLibrary.requestAuthorization { status in
          if status == .authorized { add() } else { DispatchQueue.main.async { result("denied") } }
        }
      }
    }
  }

  #if os(iOS)

  private func keyWindow() -> UIWindow? {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    return windows.first { $0.isKeyWindow } ?? windows.first
  }

  private func findWebView(_ v: UIView) -> WKWebView? {
    if let w = v as? WKWebView { return w }
    for s in v.subviews { if let w = findWebView(s) { return w } }
    return nil
  }

  private func fullBleed(result: @escaping FlutterResult) {
    guard let window = keyWindow(), let web = findWebView(window) else {
      result(false)
      return
    }
    web.scrollView.contentInsetAdjustmentBehavior = .never
    let paper = UIColor(red: 0xEE / 255.0, green: 0xE5 / 255.0, blue: 0xCE / 255.0, alpha: 1)
    web.backgroundColor = paper
    web.scrollView.backgroundColor = paper
    if #available(iOS 15.0, *) { web.underPageBackgroundColor = paper }
    result(true)
  }

  private func snapshot(_ done: @escaping (URL?) -> Void) {
    guard let window = keyWindow(), let web = findWebView(window) else {
      done(nil)
      return
    }
    web.takeSnapshot(with: nil) { image, _ in done(self.pngFile(image?.pngData())) }
  }

  private func share(text: String?, anchor: CGRect, png: Data?, result: @escaping FlutterResult) {
    guard let window = keyWindow() else {
      result(false)
      return
    }
    picture(png) { url in
      guard let url = url else {
        result(false)
        return
      }
      var items: [Any] = [url]
      if let text = text { items.append(text) }
      let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
      if let pop = sheet.popoverPresentationController {
        pop.sourceView = window
        pop.sourceRect = anchor
      }
      var top = window.rootViewController
      while let next = top?.presentedViewController { top = next }
      top?.present(sheet, animated: true)
      result(true)
    }
  }

  #elseif os(macOS)

  private func fullBleed(result: @escaping FlutterResult) { result(true) }

  private func findWebView(_ v: NSView) -> WKWebView? {
    if let w = v as? WKWebView { return w }
    for s in v.subviews { if let w = findWebView(s) { return w } }
    return nil
  }

  private func snapshot(_ done: @escaping (URL?) -> Void) {
    guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first,
      let view = window.contentView, let web = findWebView(view)
    else {
      done(nil)
      return
    }
    web.takeSnapshot(with: nil) { image, _ in
      guard let tiff = image?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
        done(nil)
        return
      }
      done(self.pngFile(rep.representation(using: .png, properties: [:])))
    }
  }

  private func share(text: String?, anchor: CGRect, png: Data?, result: @escaping FlutterResult) {
    guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first,
      let view = window.contentView
    else {
      result(false)
      return
    }
    picture(png) { url in
      guard let url = url else {
        result(false)
        return
      }
      var items: [Any] = [url]
      if let text = text { items.append(text) }
      let picker = NSSharingServicePicker(items: items)
      // Flutter gives the button from the top left; AppKit may count from
      // the bottom.
      var rect = anchor
      if !view.isFlipped { rect.origin.y = view.bounds.height - anchor.maxY }
      picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
      result(true)
    }
  }

  #endif
}
