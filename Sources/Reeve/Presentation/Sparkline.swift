import SwiftUI

struct Sparkline: View {
    let data: [Double]
    let width: CGFloat
    let height: CGFloat
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            guard data.count >= 2 else { return }
            let minVal = data.min() ?? 0
            let maxVal = data.max() ?? 1
            let range = max(maxVal - minVal, 0.001)
            let step = size.width / CGFloat(data.count - 1)

            var path = Path()
            for (i, value) in data.enumerated() {
                let x = CGFloat(i) * step
                let y = size.height - CGFloat((value - minVal) / range) * size.height
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(path, with: .color(color), lineWidth: 1)
        }
        .frame(width: width, height: height)
    }
}
