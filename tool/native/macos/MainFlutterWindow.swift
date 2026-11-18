// Written by tool/patch_platforms.py from tool/native/macos/MainFlutterWindow.swift;
// edit that copy, not this one.
import Cocoa
import FlutterMacOS
import WebKit

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    PlateShare.register(
      messenger: flutterViewController.engine.binaryMessenger, view: flutterViewController.view)

    super.awakeFromNib()
  }
}

/// birdsong/plate: "share" snapshots the plate's web view (the page alone,
/// not the app's buttons over it) and opens the share menu with it.
enum PlateShare {
  static var channel: FlutterMethodChannel?
  static weak var root: NSView?

  static func register(messenger: FlutterBinaryMessenger, view: NSView) {
    root = view
    let c = FlutterMethodChannel(name: "birdsong/plate", binaryMessenger: messenger)
    c.setMethodCallHandler { call, result in
      guard call.method == "share" else { return result(FlutterMethodNotImplemented) }
      let args = call.arguments as? [String: Any] ?? [:]
      share(args, result)
    }
    channel = c
  }

  static func find(_ v: NSView) -> WKWebView? {
    if let w = v as? WKWebView { return w }
    for s in v.subviews { if let w = find(s) { return w } }
    return nil
  }

  static func share(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let root = root, let web = find(root.window?.contentView ?? root) else {
      return result(FlutterError(code: "no-plate", message: "The plate isn't showing", details: nil))
    }
    web.takeSnapshot(with: nil) { image, error in
      guard let image = image,
        let tiff = image.tiffRepresentation,
        let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
      else {
        return result(FlutterError(code: "snapshot", message: error?.localizedDescription, details: nil))
      }
      // A named file shares better (Mail, Messages, AirDrop) than a bare image.
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("Birdsong plate.png")
      do { try png.write(to: url) } catch {
        return result(FlutterError(code: "write", message: error.localizedDescription, details: nil))
      }
      var items: [Any] = [url]
      if let text = args["text"] as? String, !text.isEmpty { items.append(text) }
      // Flutter gives the button's rect from the top left; AppKit may count from the bottom.
      let x = args["x"] as? Double ?? 0, y = args["y"] as? Double ?? 0
      let w = args["w"] as? Double ?? 1, h = args["h"] as? Double ?? 1
      let rect = root.isFlipped
        ? NSRect(x: x, y: y, width: w, height: h)
        : NSRect(x: x, y: Double(root.bounds.height) - y - h, width: w, height: h)
      NSSharingServicePicker(items: items).show(relativeTo: rect, of: root, preferredEdge: .minY)
      result(true)
    }
  }
}
