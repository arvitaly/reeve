import SwiftUI

struct Sparkline: View {
    let data: [Double]
    let width: CGFloat?    // nil = fill available width
    let height: CGFloat
    let color: Color

    init(data: [Double], width: CGFloat? = nil, height: CGFloat, color: Color) {
        self.data = data
        self.width = width
        self.height = height
        self.color = color
    }

    var body: some View {
        Canvas { ctx, size in
            guard data.count >= 2 else { return }
            let minVal = data.min() ?? 0
            let maxVal = data.max() ?? 1
            let range = max(maxVal - minVal, 0.001)
            let step = size.width / CGFloat(data.count - 1)

            var line = Path()
            for (i, value) in data.enumerated() {
                let x = CGFloat(i) * step
                let y = size.height - CGFloat((value - minVal) / range) * size.height
                if i == 0 { line.move(to: CGPoint(x: x, y: y)) }
                else { line.addLine(to: CGPoint(x: x, y: y)) }
            }

            var fill = line
            let lastX = CGFloat(data.count - 1) * step
            fill.addLine(to: CGPoint(x: lastX, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .color(color.opacity(0.15)))
            ctx.stroke(line, with: .color(color), lineWidth: 1)
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil)
    }
}
