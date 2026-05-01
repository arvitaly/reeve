import SwiftUI
import ReeveKit


// Template NSImage rendered via CoreGraphics — isTemplate=true lets macOS
// composite it correctly for any menu bar appearance (light/dark/tinted).
private func makeReeveTemplateImage(size: CGFloat = 16) -> NSImage {
    let sz = NSSize(width: size, height: size)
    let image = NSImage(size: sz, flipped: false) { bounds in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
        let w = bounds.width, h = bounds.height
        let sw = max(1.5, w * 0.09)

        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineWidth(sw)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        // Left bracket
        ctx.beginPath()
        ctx.move(to:    CGPoint(x: w * 0.273, y: h * 0.273))
        ctx.addLine(to: CGPoint(x: w * 0.195, y: h * 0.273))
        ctx.addLine(to: CGPoint(x: w * 0.195, y: h * 0.727))
        ctx.addLine(to: CGPoint(x: w * 0.273, y: h * 0.727))
        ctx.strokePath()

        // Right bracket
        ctx.beginPath()
        ctx.move(to:    CGPoint(x: w * 0.727, y: h * 0.273))
        ctx.addLine(to: CGPoint(x: w * 0.805, y: h * 0.273))
        ctx.addLine(to: CGPoint(x: w * 0.805, y: h * 0.727))
        ctx.addLine(to: CGPoint(x: w * 0.727, y: h * 0.727))
        ctx.strokePath()

        // Center rect
        ctx.setFillColor(NSColor.black.cgColor)
        let rx = w * 0.375, ry = h * 0.406, rw = w * 0.250, rh = h * 0.188
        let cr = min(rw, rh) * 0.125
        let path = CGPath(roundedRect: CGRect(x: rx, y: ry, width: rw, height: rh),
                          cornerWidth: cr, cornerHeight: cr, transform: nil)
        ctx.addPath(path)
        ctx.fillPath()

        return true
    }
    image.isTemplate = true
    return image
}

private let reeveTemplateImage = makeReeveTemplateImage()

struct MenuBarLabel: View {
    @ObservedObject var engine: MonitoringEngine
    @EnvironmentObject var appState: AppState
    @AppStorage("menuBarShowCPU")    private var showCPU:    Bool = true
    @AppStorage("menuBarShowMemory") private var showMemory: Bool = false
    @AppStorage("menuBarShowDisk")   private var showDisk:   Bool = false

    private enum LabelState {
        case flash
        case normal
        case warn
        case over(ApplicationGroup)
    }

    private var labelState: LabelState {
        if let exp = appState.killFlashExpiry, exp > .now { return .flash }
        let (apps, _) = buildApplicationGroups(snapshot: engine.snapshot)
        var hasWarn = false
        for app in apps {
            let cap = memCap(for: app, in: appState.groupRuleSpecs)
            switch app.overallSeverity(cap: cap) {
            case .over: return .over(app)
            case .warn: hasWarn = true
            case .normal: break
            }
        }
        if hasWarn || engine.snapshot.totalCPU > 50 { return .warn }
        return .normal
    }

    var body: some View {
        switch labelState {
        case .flash:       flashLabel
        case .normal:      normalLabel
        case .warn:        warnLabel
        case .over(let g): overLabel(g)
        }
    }

    @ViewBuilder private var metricText: some View {
        let parts = metricParts
        if !parts.isEmpty {
            Text(parts.joined(separator: " "))
                .font(.caption.monospacedDigit())
        }
    }

    private var metricParts: [String] {
        var parts: [String] = []
        let cpu = engine.snapshot.totalCPU
        if showCPU && cpu >= 1 { parts.append(String(format: "%.0f%%", cpu)) }
        if showMemory, let m = engine.snapshot.usedMemory { parts.append(shortMem(m)) }
        let diskWrite = engine.snapshot.processes.reduce(0) { $0 + $1.diskWriteRate }
        if showDisk && diskWrite >= 1_048_576 { parts.append("↑" + shortMem(diskWrite) + "/s") }
        return parts
    }

    private var flashLabel: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.green).frame(width: 7, height: 7)
                .shadow(color: .green.opacity(0.6), radius: 3)
            Text("—").font(.caption.monospacedDigit()).foregroundStyle(Color.green)
        }
    }

    private var normalLabel: some View {
        HStack(spacing: 4) {
            Image(nsImage: reeveTemplateImage)
            metricText
        }
    }

    private var warnLabel: some View {
        HStack(spacing: 4) {
            Image(nsImage: reeveTemplateImage).colorMultiply(Color.rvAccent)
            metricText
        }
    }

    @ViewBuilder
    private func overLabel(_ group: ApplicationGroup) -> some View {
        HStack(spacing: 3) {
            if let icon = group.icon {
                Image(nsImage: icon)
                    .resizable().interpolation(.high)
                    .frame(width: 14, height: 14)
            }
            Circle().fill(Color.rvDanger).frame(width: 6, height: 6)
            Text(shortMem(group.totalMemory))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.rvDanger)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.rvDanger.opacity(0.12))
        .clipShape(Capsule())
    }

    private func shortMem(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 1.0 { return String(format: "%.1fG", gb) }
        return String(format: "%.0fM", Double(bytes) / (1024 * 1024))
    }
}
