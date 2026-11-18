// Written by tool/patch_platforms.py from tool/native/ios/AppDelegate.swift;
// edit that copy, not this one.
import Flutter
import UIKit
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BirdsongPlate") {
      PlateShare.register(messenger: registrar.messenger())
    }
  }
}

/// birdsong/plate: "share" snapshots the plate's web view (the page alone,
/// not the app's buttons over it) and opens the share sheet with it.
enum PlateShare {
  static var channel: FlutterMethodChannel?

  static func register(messenger: FlutterBinaryMessenger) {
    let c = FlutterMethodChannel(name: "birdsong/plate", binaryMessenger: messenger)
    c.setMethodCallHandler { call, result in
      guard call.method == "share" else { return result(FlutterMethodNotImplemented) }
      let args = call.arguments as? [String: Any] ?? [:]
      share(args, result)
    }
    channel = c
  }

  static func window() -> UIWindow? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    return scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
  }

  static func find(_ v: UIView) -> WKWebView? {
    if let w = v as? WKWebView { return w }
    for s in v.subviews { if let w = find(s) { return w } }
    return nil
  }

  static func share(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let win = window(), let root = win.rootViewController, let web = find(win) else {
      return result(FlutterError(code: "no-plate", message: "The plate isn't showing", details: nil))
    }
    web.takeSnapshot(with: nil) { image, error in
      guard let image = image else {
        return result(FlutterError(code: "snapshot", message: error?.localizedDescription, details: nil))
      }
      var items: [Any] = [image]
      if let text = args["text"] as? String, !text.isEmpty { items.append(text) }
      let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
      // iPad shows the sheet as a popover from the share button.
      if let pop = sheet.popoverPresentationController {
        pop.sourceView = root.view
        pop.sourceRect = CGRect(
          x: args["x"] as? Double ?? 0, y: args["y"] as? Double ?? 0,
          width: args["w"] as? Double ?? 1, height: args["h"] as? Double ?? 1)
      }
      var top = root
      while let p = top.presentedViewController { top = p }
      top.present(sheet, animated: true)
      result(true)
    }
  }
}
