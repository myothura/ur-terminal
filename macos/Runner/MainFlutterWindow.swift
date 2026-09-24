import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Dark chrome that blends with the app, sensible default and minimum size.
    self.appearance = NSAppearance(named: .darkAqua)
    self.titlebarAppearsTransparent = true
    self.backgroundColor = NSColor(red: 0.063, green: 0.078, blue: 0.102, alpha: 1)
    self.title = "Ur.Terminal"
    self.minSize = NSSize(width: 960, height: 620)
    self.setContentSize(NSSize(width: 1280, height: 820))
    self.center()
    self.setFrameAutosaveName("UrTerminalMainWindow")

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
