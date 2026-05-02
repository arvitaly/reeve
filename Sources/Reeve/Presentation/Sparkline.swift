import SwiftUI

struct Sparkline: View {
    let data: [Double]
    var width: CGFloat? = nil
    let height: CGFloat
    let color: Color
    var fill: Bool = true
    var capLine: Double? = nil
    var capMax: Double? = nil
    var lineWidth: CGFloat = 1.2

    var body: some View {
        Canvas { ctx, size in
            guard data.count >= 2 else { return }
            let effectiveMax = capMax ?? (data.max().map { $0 * 1.1 } ?? 1)
            let clampedMax = max(effectiveMax, 0.001)
            let step = size.width / CGFloat(data.count - 1)

            var line = Path()
            for (i, value) in data.enumerated() {
                let x = CGFloat(i) * step
                let y = size.height - CGFloat(min(value / clampedMax, 1)) * size.height
                if i == 0 { line.move(to: CGPoint(x: x, y: y)) }
                else { line.addLine(to: CGPoint(x: x, y: y)) }
            }

            if fill {
                var area = line
                area.addLine(to: CGPoint(x: CGFloat(data.count - 1) * step, y: size.height))
                area.addLine(to: CGPoint(x: 0, y: size.height))
                area.closeSubpath()
                let gradient = Gradient(stops: [
                    .init(color: color.opacity(0.35), location: 0),
                    .init(color: color.opacity(0), location: 1),
                ])
                ctx.fill(area, with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            }

            ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

            if let cap = capLine, let cMax = capMax, cMax > 0 {
                let capY = size.height - CGFloat(min(cap / cMax, 1)) * size.height
                var dash = Path()
                dash.move(to: CGPoint(x: 0, y: capY))
                dash.addLine(to: CGPoint(x: size.width, y: capY))
                ctx.stroke(dash, with: .color(.rvOver), style: StrokeStyle(lineWidth: 0.8, dash: [2, 2]))
            }
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil)
    }
}
