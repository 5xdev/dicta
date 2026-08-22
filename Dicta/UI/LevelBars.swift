import SwiftUI

/// Animated bars: mic-driven while recording, gentle idle wave while transcribing, orange flash on error.
struct LevelBars: View {
    enum Mode { case flat, live, busy, error }

    let level: Float
    let mode: Mode
    private let count = 7
    private let minHeight: CGFloat = 4
    private let maxHeight: CGFloat = 22

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: mode != .busy)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule()
                        .fill(color(for: i))
                        .frame(width: 4, height: height(for: i, time: t))
                }
            }
            .shadow(color: glow, radius: 3)   // soft luminous halo; bars are plain shapes so this stays capsule-shaped
        }
        .animation(.easeOut(duration: 0.08), value: level)
        .animation(.easeInOut(duration: 0.2), value: mode == .error)
    }

    /// Bars sweep from the app accent (lifted toward white) on the left to a cool aqua on the right,
    /// so they stay bright on the dark pill and read as a "live" waveform rather than a flat glyph.
    private var gradientStart: Color { Color.accentColor.mix(with: .white, by: 0.2) }
    private let gradientEnd = Color(red: 0.45, green: 0.92, blue: 0.95)

    private func color(for index: Int) -> Color {
        let base = gradientStart.mix(with: gradientEnd, by: Double(index) / Double(count - 1))
        switch mode {
        case .live: return base
        case .busy: return base.opacity(0.7)
        case .error: return .orange
        case .flat: return base.opacity(0.35)
        }
    }

    private var glow: Color {
        switch mode {
        case .live: return gradientStart.opacity(0.5)
        case .busy: return gradientStart.opacity(0.25)
        case .error: return Color.orange.opacity(0.5)
        case .flat: return .clear
        }
    }

    private func height(for index: Int, time: TimeInterval) -> CGFloat {
        let center = Double(count - 1) / 2
        let distance = abs(Double(index) - center) / center      // 0 at middle, 1 at edges
        let weight = 1 - 0.6 * distance                          // middle bars respond most
        let amplitude: Double
        switch mode {
        case .live:
            amplitude = Double(level) * weight
        case .busy:
            // travelling sine so the bars ripple left→right while we wait for the server
            amplitude = (0.5 + 0.5 * sin(time * 6 - Double(index) * 0.9)) * 0.55 * weight
        case .error:
            amplitude = 0.35 * weight
        case .flat:
            amplitude = 0
        }
        return max(minHeight, min(maxHeight, minHeight + CGFloat(amplitude) * (maxHeight - minHeight)))
    }
}
