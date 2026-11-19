// Takes a picture of the app's web view (the plate) with WKWebView's own
// snapshot, which leaves out the Flutter buttons drawn over it, writes it
// as a PNG and opens the system share sheet with it.

#if os(iOS)
import Flutter
import UIKit
#elseif os(macOS)
import FlutterMacOS
import AppKit
#endif
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
    if call.method == "save" {
      DispatchQueue.main.async { self.save(result: result) }
      return
    }
    if call.method == "fullBleed" {
      DispatchQueue.main.async { self.fullBleed(result: result) }
      return
    }
    guard call.method == "share" else {
      result(FlutterMethodNotImplemented)
      return
    }
    let args = call.arguments as? [String: Any] ?? [:]
    let text = args["text"] as? String
    let anchor = CGRect(
      x: (args["x"] as? Double) ?? 0, y: (args["y"] as? Double) ?? 0,
      width: (args["w"] as? Double) ?? 1, height: (args["h"] as? Double) ?? 1)
    DispatchQueue.main.async { self.share(text: text, anchor: anchor, result: result) }
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
  private func save(result: @escaping FlutterResult) {
    snapshot { url in
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

  private func share(text: String?, anchor: CGRect, result: @escaping FlutterResult) {
    guard let window = keyWindow() else {
      result(false)
      return
    }
    snapshot { url in
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

  private func share(text: String?, anchor: CGRect, result: @escaping FlutterResult) {
    guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first,
      let view = window.contentView
    else {
      result(false)
      return
    }
    snapshot { url in
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
