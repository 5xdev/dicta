import AppKit
import Combine
import SwiftUI

/// A floating, click-through pill at the bottom of the active screen that shows recording state.
@MainActor
final class OverlayPanelController {
    private let panel: NSPanel
    private var cancellables = Set<AnyCancellable>()
    // Pill is 80×28; the extra room lets the drop shadow render instead of being clipped by the window.
    private let size = NSSize(width: 112, height: 60)

    init(controller: DictationController) {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.alphaValue = 0
        // Always render as a dark HUD, regardless of system light/dark mode, so the pill reads on any backdrop.
        panel.appearance = NSAppearance(named: .darkAqua)

        let host = NSHostingView(rootView: OverlayView().environmentObject(controller))
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        controller.$state
            .removeDuplicates()
            .sink { [weak self] state in   // already on the main actor; no RunLoop.main hop (it stalls during menu tracking)
                if state == .idle { self?.hide() } else { self?.show() }
            }
            .store(in: &cancellables)
    }

    private func show() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 16))
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    private func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [panel] in
            if panel.alphaValue == 0 { panel.orderOut(nil) }
        })
    }
}

/// Minimal pill: nothing but the level bars.
///
/// Styled as a fixed dark HUD (like the system volume bezel) so it looks the same over light and dark
/// content: a dark tinted glass fill, a faint light hairline inside the edge to separate it from dark
/// backdrops, and a soft drop shadow to separate it from light ones.
struct OverlayView: View {
    @EnvironmentObject private var controller: DictationController

    var body: some View {
        ZStack {
            // The shadows live on a plain capsule, NOT on the material view: on macOS SwiftUI renders the
            // shadow of a material-backed view from its rectangular bounds, which shows up as a faint box.
            Capsule()
                .fill(Color.black.opacity(0.55))                         // keeps the pill deep even over pure white
                .shadow(color: .black.opacity(0.30), radius: 12, y: 4)   // soft halo: separates from light backdrops
                .shadow(color: .black.opacity(0.20), radius: 1.5, y: 0.5) // tight contact shadow: crisp edge
            Capsule()
                .fill(.ultraThinMaterial)                                // dark because the panel appearance is darkAqua
            Capsule()
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)        // hairline: separates from dark backdrops
            LevelBars(level: controller.level, mode: mode)
                .frame(width: 64, height: 22)
        }
        .frame(width: 80, height: 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mode: LevelBars.Mode {
        switch controller.state {
        case .recording: return .live
        case .transcribing: return .busy
        case .error: return .error
        case .idle: return .flat
        }
    }
}
