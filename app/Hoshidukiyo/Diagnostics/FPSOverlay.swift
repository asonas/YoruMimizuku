import SwiftUI
import QuartzCore

/// Tracks frame intervals reported by a display link and derives a rolling FPS
/// plus the worst frame time in each window (a proxy for hitches/jank).
@MainActor
final class FrameRateMonitor: ObservableObject {
    @Published private(set) var fps: Double = 0
    @Published private(set) var worstFrameMs: Double = 0

    private var lastTimestamp: CFTimeInterval = 0
    private var frames = 0
    private var elapsed: CFTimeInterval = 0
    private var worst: CFTimeInterval = 0

    func record(timestamp: CFTimeInterval) {
        defer { lastTimestamp = timestamp }
        guard lastTimestamp > 0 else { return }
        let delta = timestamp - lastTimestamp
        guard delta > 0 else { return }

        frames += 1
        elapsed += delta
        worst = max(worst, delta)

        if elapsed >= 0.5 {
            fps = Double(frames) / elapsed
            worstFrameMs = worst * 1000
            frames = 0
            elapsed = 0
            worst = 0
        }
    }
}

/// Hosts a `CADisplayLink` (macOS 14+) bound to the window's display and reports
/// each frame's timestamp. Zero-size; meant to be attached via `.background`.
private final class DisplayLinkView: NSView {
    var onFrame: ((CFTimeInterval) -> Void)?
    private var link: CADisplayLink?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        link?.invalidate()
        link = nil
        guard window != nil else { return }
        let link = displayLink(target: self, selector: #selector(handleFrame(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func handleFrame(_ sender: CADisplayLink) {
        onFrame?(sender.timestamp)
    }
}

private struct DisplayLinkProbe: NSViewRepresentable {
    let onFrame: (CFTimeInterval) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = DisplayLinkView()
        view.onFrame = onFrame
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? DisplayLinkView)?.onFrame = onFrame
    }
}

/// A small always-on-top readout of live FPS and the worst recent frame time.
/// Color-codes the worst frame against the 60 Hz (16.7 ms) and 30 Hz (33.3 ms)
/// budgets so dropped frames are obvious at a glance.
struct FPSOverlayView: View {
    @StateObject private var monitor = FrameRateMonitor()

    var body: some View {
        HStack(spacing: 8) {
            Text(String(format: "%.0f fps", monitor.fps))
            Text(String(format: "worst %.1f ms", monitor.worstFrameMs))
                .foregroundStyle(color(forFrameMs: monitor.worstFrameMs))
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.black.opacity(0.55), in: Capsule())
        .background(DisplayLinkProbe { monitor.record(timestamp: $0) })
        .allowsHitTesting(false)
    }

    private func color(forFrameMs ms: Double) -> Color {
        switch ms {
        case ..<16.7: return .green
        case ..<33.4: return .yellow
        default: return .red
        }
    }
}

/// Overlays the FPS readout in DEBUG builds and is a no-op in Release.
struct DebugPerfOverlay: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG
        content.overlay(alignment: .bottomTrailing) {
            FPSOverlayView().padding(8)
        }
        #else
        content
        #endif
    }
}
