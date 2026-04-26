import SwiftUI

/// Compact Canvas-drawn fill bar for per-group memory usage in list rows.
struct MiniBar: View {
    let value: Double    // current bytes
    let cap: Double?     // rule cap bytes, nil = no rule
    let width: CGFloat
    var height: CGFloat = 4
    let severity: Severity

    private static let absoluteMax: Double = 6 * 1_073_741_824  // 6 GB fallback scale

    private var rawFill: Double {
        let scale = cap ?? Self.absoluteMax
        guard scale > 0 else { return 0 }
        return value / scale
    }

    private var fillRatio: Double { min(rawFill, 1.0) }
    private var isOver: Bool { rawFill > 1.0 }

    var body: some View {
        Canvas { ctx, size in
            // Track
            ctx.fill(
                Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2),
                with: .color(.rvBarTrack)
            )
            // Fill
            let fillW = size.width * fillRatio
            if fillW > 0 {
                ctx.fill(
                    Path(roundedRect: CGRect(x: 0, y: 0, width: fillW, height: size.height),
                         cornerRadius: size.height / 2),
                    with: .color(severity.barColor)
                )
            }
            // Over-cap stub: 2 px white tick at right edge
            if isOver {
                ctx.fill(
                    Path(roundedRect: CGRect(x: size.width - 2, y: 0, width: 2, height: size.height),
                         cornerRadius: 1),
                    with: .color(.white.opacity(0.7))
                )
            }
        }
        .frame(width: width, height: height)
    }
}

/// 6 px severity indicator dot.
struct SeverityDot: View {
    let severity: Severity

    var body: some View {
        Circle()
            .fill(severity.dotColor)
            .frame(width: 6, height: 6)
    }
}
