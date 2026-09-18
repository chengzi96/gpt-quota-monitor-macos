import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let store: QuotaStore
    private let statusItem: NSStatusItem
    private let panel: QuotaHoverPanel
    private let hostingController: NSHostingController<AnyView>
    private let onOpenSettings: (SettingsTab) -> Void

    private var statusHoverView: StatusItemHoverView?
    private var poolsCancellable: AnyCancellable?
    private var layoutCancellable: AnyCancellable?
    private var defaultsCancellable: AnyCancellable?
    private var closeTask: Task<Void, Never>?
    private var fadeOutTask: Task<Void, Never>?
    private var pointerOverStatus = false
    private var pointerOverPanel = false
    private var isFadingOut = false

    private static let fadeDuration: TimeInterval = 0.09
    private static let closeGraceNanoseconds: UInt64 = 110_000_000
    private static let panelGap: CGFloat = 5

    init(store: QuotaStore, onOpenSettings: @escaping (SettingsTab) -> Void) {
        self.store = store
        self.onOpenSettings = onOpenSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let root = QuotaPopoverView()
            .environmentObject(store)
            .eraseToAnyView()
        self.hostingController = NSHostingController(rootView: root)

        let panel = QuotaHoverPanel(
            contentRect: NSRect(x: 0, y: 0, width: DesignTokens.panelWidth, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        self.panel = panel

        super.init()

        configureStatusItem()
        configurePanelContent()
        configurePanelWindow()
        observeChanges()
        updateStatusItem()
        updatePanelSize()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.imageHugsTitle = true
        button.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)

        let hoverView = StatusItemHoverView(frame: button.bounds)
        hoverView.translatesAutoresizingMaskIntoConstraints = false
        hoverView.onHoverChanged = { [weak self] inside in
            self?.statusHoverChanged(inside)
        }
        button.addSubview(hoverView)
        NSLayoutConstraint.activate([
            hoverView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hoverView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            hoverView.topAnchor.constraint(equalTo: button.topAnchor),
            hoverView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
        statusHoverView = hoverView
    }

    private func configurePanelContent() {
        let root = QuotaPopoverView(
            onHoverChanged: { [weak self] inside in
                self?.panelHoverChanged(inside)
            },
            onOpenSettings: { [weak self] tab in
                self?.openSettings(tab)
            }
        )
        .environmentObject(store)
        .eraseToAnyView()

        hostingController.rootView = root
    }

    private func configurePanelWindow() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        panel.alphaValue = 0
        panel.animationBehavior = .none
        panel.appearance = NSAppearance(named: .darkAqua)
    }

    private func observeChanges() {
        poolsCancellable = store.$pools
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pools in
                Task { @MainActor [weak self] in
                    self?.updateStatusItem(poolsOverride: pools)
                    self?.updatePanelSize()
                    self?.repositionPanelIfVisible()
                }
            }

        layoutCancellable = store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await Task.yield()
                    self?.updatePanelSize()
                    self?.repositionPanelIfVisible()
                }
            }

        defaultsCancellable = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateStatusItem()
                }
            }
    }

    private func updateStatusItem(poolsOverride: [QuotaPoolID: QuotaPool]? = nil) {
        guard let button = statusItem.button else { return }

        let icon: NSImage?
        if let url = Bundle.main.url(forResource: "MenuBarHourglassTemplate", withExtension: "png"),
           let bundled = NSImage(contentsOf: url) {
            bundled.isTemplate = true
            bundled.size = NSSize(width: 15, height: 15)
            icon = bundled
        } else {
            let configuration = NSImage.SymbolConfiguration(pointSize: 12.5, weight: .semibold)
            let fallback = NSImage(
                systemSymbolName: "hourglass",
                accessibilityDescription: "GPT流量监控"
            )?.withSymbolConfiguration(configuration)
            fallback?.isTemplate = true
            icon = fallback
        }
        button.image = icon

        let showSummary = UserDefaults.standard.object(forKey: "showMenuBarQuotaSummary") as? Bool ?? true
        let pools = poolsOverride ?? store.pools
        let weeklyPercent = pools[.workCodex]?.weeklyWindow?.remainingPercent
        let sessionPercent = pools[.workCodex]?.sessionWindow?.remainingPercent

        func compactPercent(_ value: Double?) -> String {
            guard let value else { return "--%" }
            return "\(Int(value.rounded()))%"
        }

        let weeklyText = "周 \(compactPercent(weeklyPercent))"
        let sessionText = "5h \(compactPercent(sessionPercent))"

        if showSummary {
            let baseFont = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
            let title = NSMutableAttributedString()

            title.append(NSAttributedString(
                string: weeklyText,
                attributes: [.font: baseFont, .foregroundColor: NSColor.labelColor]
            ))
            title.append(NSAttributedString(
                string: "  ·  ",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12.0, weight: .medium),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.60)
                ]
            ))
            title.append(NSAttributedString(
                string: sessionText,
                attributes: [.font: baseFont, .foregroundColor: NSColor.labelColor]
            ))
            button.attributedTitle = title
        } else {
            button.attributedTitle = NSAttributedString(string: "")
        }

        let weeklyHelp = weeklyPercent.map(QuotaFormatters.percent) ?? "暂不可读"
        let sessionHelp = sessionPercent.map(QuotaFormatters.percent) ?? "暂不可读"
        let detailedHelp = "本周剩余 \(weeklyHelp)｜近 5 小时剩余 \(sessionHelp)"

        statusItem.length = NSStatusItem.variableLength
        button.toolTip = nil
        button.setAccessibilityLabel("GPT流量监控，\(detailedHelp)")
        button.needsLayout = true
        button.needsDisplay = true
    }

    private func updateStatusButtonVisual() {}

    private func updatePanelSize() {
        let view = hostingController.view
        view.layoutSubtreeIfNeeded()
        let fitting = view.fittingSize
        guard fitting.width > 0, fitting.height > 0 else { return }

        let size = NSSize(
            width: max(DesignTokens.panelWidth, fitting.width),
            height: fitting.height
        )
        if panel.contentViewController?.preferredContentSize != size {
            panel.contentViewController?.preferredContentSize = size
            panel.setContentSize(size)
        }
    }

    func showFromApplicationReopen() {
        cancelScheduledClose()
        showPanel()
    }

    private func statusHoverChanged(_ inside: Bool) {
        pointerOverStatus = inside
        if inside {
            cancelScheduledClose()
            showPanel()
        } else {
            scheduleClose()
        }
    }

    private func panelHoverChanged(_ inside: Bool) {
        pointerOverPanel = inside
        if inside {
            cancelScheduledClose()
        } else {
            scheduleClose()
        }
    }

    private func showPanel() {
        guard let button = statusItem.button else { return }

        cancelScheduledClose()
        fadeOutTask?.cancel()
        fadeOutTask = nil
        isFadingOut = false
        updatePanelSize()
        positionPanel(relativeTo: button)

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        Task { await store.refreshIfStale() }
    }

    private func closePanel(animated: Bool) {
        cancelScheduledClose()
        guard panel.isVisible, !isFadingOut else { return }

        isFadingOut = true
        fadeOutTask?.cancel()
        fadeOutTask = nil

        guard animated else {
            panel.orderOut(nil)
            panel.alphaValue = 0
            isFadingOut = false
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }

        fadeOutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled, let self else { return }
            guard !self.pointerOverStatus, !self.pointerOverPanel else {
                self.panel.alphaValue = 1
                self.isFadingOut = false
                return
            }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 0
            self.isFadingOut = false
            self.fadeOutTask = nil
            self.updateStatusButtonVisual()
        }
    }

    private func scheduleClose() {
        cancelScheduledClose()
        closeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.closeGraceNanoseconds)
            guard !Task.isCancelled, let self else { return }
            guard !self.pointerOverStatus, !self.pointerOverPanel else { return }
            self.closePanel(animated: true)
        }
    }

    private func cancelScheduledClose() {
        closeTask?.cancel()
        closeTask = nil
    }

    private func positionPanel(relativeTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let statusRect = buttonWindow.convertToScreen(buttonRectInWindow)
        let panelSize = panel.frame.size

        let screen = buttonWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(
            x: statusRect.minX - panelSize.width,
            y: statusRect.minY - panelSize.height,
            width: panelSize.width * 2,
            height: panelSize.height * 2
        )

        var x = statusRect.maxX - panelSize.width
        x = min(max(x, visible.minX + 6), visible.maxX - panelSize.width - 6)

        var y = statusRect.minY - panelSize.height - Self.panelGap
        if y < visible.minY + 6 {
            y = statusRect.maxY + Self.panelGap
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func repositionPanelIfVisible() {
        guard panel.isVisible, let button = statusItem.button else { return }
        positionPanel(relativeTo: button)
    }

    private func openSettings(_ tab: SettingsTab) {
        closePanel(animated: false)
        onOpenSettings(tab)
    }
}

@MainActor
private final class QuotaHoverPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class StatusItemHoverView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private extension View {
    func eraseToAnyView() -> AnyView { AnyView(self) }
}
