import SwiftUI

/// Diagonal-stripe pattern used wherever Reeve cannot measure a value.
/// Same swatch appears in the bar, the detail panel, and the educational sheet —
/// so users learn it once.
///
/// "Honest absence beats plausible approximation" (CLAUDE.md): we mark what we
/// could not measure, we do not interpolate it.
struct UnmeasurableStripes: View {
    var spacing: CGFloat = 3
    var lineWidth: CGFloat = 1
    var color: Color = .rvDotNormal
    var opacity: Double = 0.45
    var cornerRadius: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let path = Path { p in
                    let step = spacing + lineWidth
                    let extent = size.width + size.height
                    var x: CGFloat = -size.height
                    while x < extent {
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x + size.height, y: size.height))
                        x += step
                    }
                }
                ctx.stroke(path, with: .color(color.opacity(opacity)), lineWidth: lineWidth)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

/// Tiny inline marker that replaces a colored dot when something is unmeasurable.
/// Used in MemorySummaryLine and MemoryDetailPanel rows.
struct UnmeasurableDot: View {
    var size: CGFloat = 8

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.rvInputBg)
            UnmeasurableStripes(spacing: 1.5, lineWidth: 0.8, opacity: 0.55, cornerRadius: 2)
        }
        .frame(width: size, height: size)
    }
}
