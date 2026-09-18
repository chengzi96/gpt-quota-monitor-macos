import AppKit
import SwiftUI

/// 状态栏浮层由自定义透明 NSPanel 承载。 Liquid Glass needs that window
/// to stay transparent so native Liquid Glass (macOS 26+) or the Material
/// fallback (macOS 13–15) can sample the desktop behind the popup.
struct TransparentPopoverWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> PopoverWindowProbe {
        PopoverWindowProbe(frame: .zero)
    }

    func updateNSView(_ view: PopoverWindowProbe, context: Context) {
        view.applyConfiguration()
    }
}

/// Configure only after AppKit has attached the probe to the status panel window.
/// Using viewDidMoveToWindow avoids an escaping DispatchQueue closure capturing
/// NSView, which Swift 6.2 correctly treats as non-Sendable.
@MainActor
final class PopoverWindowProbe: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyConfiguration()
    }

    func applyConfiguration() {
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 1
        window.hasShadow = true
        window.appearance = NSAppearance(named: .darkAqua)

        contentViewClear(window.contentView)
        if let host = window.contentView?.superview {
            host.wantsLayer = true
            host.layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    private func contentViewClear(_ view: NSView?) {
        view?.wantsLayer = true
        view?.layer?.backgroundColor = NSColor.clear.cgColor
    }
}
