import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // 横: 4 items × 72px + 24px + 20px × 2 margin = 352
    // 竖: 4 items × 72px + 24px + 60px topBar = 372
    self.minSize = NSSize(width: 352, height: 380)

    super.awakeFromNib()
  }
}
