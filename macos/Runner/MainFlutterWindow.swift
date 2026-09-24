import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // Transparent Flutter surface so the native blur shows through.
    flutterViewController.backgroundColor = .clear

    // Glass: an NSVisualEffectView (behind-window blur) hosts the Flutter view.
    let contentRect = self.contentRect(forFrameRect: self.frame)
    let glass = NSVisualEffectView(frame: NSRect(origin: .zero, size: contentRect.size))
    glass.material = .hudWindow
    glass.blendingMode = .behindWindow
    glass.state = .active
    glass.autoresizingMask = [.width, .height]

    let container = NSViewController()
    container.view = glass
    container.addChild(flutterViewController)
    flutterViewController.view.frame = glass.bounds
    flutterViewController.view.autoresizingMask = [.width, .height]
    glass.addSubview(flutterViewController.view)
    self.contentViewController = container

    // Tabs live in the title bar (Termius style).
    self.styleMask.insert(.fullSizeContentView)
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.isOpaque = false
    self.backgroundColor = .clear
    self.appearance = NSAppearance(named: .darkAqua)
    self.title = "Ur.Terminal"
    self.minSize = NSSize(width: 960, height: 620)
    self.setContentSize(NSSize(width: 1280, height: 820))
    self.center()
    self.setFrameAutosaveName("UrTerminalMainWindow")

    // Window drag / zoom requested from the Flutter tab strip.
    let channel = FlutterMethodChannel(
      name: "ur/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "startDrag":
        if let event = self.currentEvent {
          self.performDrag(with: event)
        }
        result(nil)
      case "zoom":
        self.zoom(nil)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
