import SwiftUI

// MARK: - Severity dot with pulse

struct SeverityDot: View {
    let severity: Severity
    var size: CGFloat = 6
    var pulse: Bool = false

    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(severity.dotColor)
            .frame(width: size, height: size)
            .scaleEffect(isPulsing && severity == .over && pulse ? 1.6 : 1.0)
            .opacity(isPulsing && severity == .over && pulse ? 0.3 : 1.0)
            .animation(
                severity == .over && pulse
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}

// MARK: - Category chip

struct CategoryChip: View {
    let category: AppCategory

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(category.color)
                .frame(width: 4, height: 4)
            Text(category.label)
        }
        .font(.system(size: 10, weight: .medium))
        .tracking(0.2)
        .foregroundStyle(category.color)
        .padding(.horizontal, 7)
        .frame(height: 18)
        .background(category.color.opacity(0.14), in: Capsule())
    }
}

// MARK: - Metric pill

struct MetricPill: View {
    let text: String
    var color: Color? = nil
    var mono: Bool = true

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: mono ? .monospaced : .default))
            .tracking(-0.1)
            .foregroundStyle(color ?? .rvText)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background((color?.opacity(0.16) ?? Color.rvPill), in: RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - Stack bar (memory composition by category)

struct StackBar: View {
    let segments: [(label: String, value: Double, color: Color)]
    let total: Double
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    let pct = total > 0 ? seg.value / total : 0
                    Rectangle()
                        .fill(seg.color)
                        .frame(width: geo.size.width * pct)
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .background(Color.rvInputBg, in: Capsule())
    }
}

// MARK: - Action chip

struct ActionChip: View {
    let label: String
    var icon: String? = nil
    var kind: ActionChipKind = .default
    let action: () -> Void

    @State private var isHovered = false

    enum ActionChipKind {
        case `default`, warn, over, accent

        var foreground: Color {
            switch self {
            case .default: return .rvText
            case .warn:    return .rvWarn
            case .over:    return .rvOver
            case .accent:  return .rvAccent
            }
        }
        var background: Color {
            switch self {
            case .default: return .rvPill
            case .warn:    return .rvWarnGlow
            case .over:    return .rvOverGlow
            case .accent:  return .rvAccentGlow
            }
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Text(icon)
                        .font(.system(size: 11))
                        .opacity(0.85)
                }
                Text(label)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(kind.foreground)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? kind.background.opacity(1.3) : kind.background)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var count: Int? = nil
    var sticky: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            if let count {
                Text("\(count)")
                    .fontWeight(.medium)
                    .opacity(0.7)
            }
            Spacer()
        }
        .font(.system(size: 10, weight: .semibold))
        .tracking(0.6)
        .textCase(.uppercase)
        .foregroundStyle(Color.rvTextFaint)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}

// MARK: - Timeline scrubber

struct TimelineScrubber: View {
    let length: Int
    @Binding var value: Int

    private var normalized: Double {
        length > 1 ? Double(value) / Double(length - 1) : 0
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("\u{2212}60s")
                Spacer()
                Text(value == length - 1 ? "Live" : "\u{2212}\(length - 1 - value)s ago")
                    .foregroundStyle(Color.rvTextDim)
                Spacer()
                Text("now")
            }
            .font(.system(size: 10, weight: .medium))
            .tracking(0.4)
            .textCase(.uppercase)
            .foregroundStyle(Color.rvTextFaint)

            GeometryReader { geo in
                let trackW = geo.size.width
                let handleX = 4 + (trackW - 8) * normalized

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.rvInputBg)
                        .frame(height: 2)

                    Capsule()
                        .fill(Color.rvAccent)
                        .frame(width: max(0, handleX), height: 2)

                    ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { p in
                        Rectangle()
                            .fill(Color.rvTextFaint)
                            .opacity(0.4)
                            .frame(width: 1, height: 6)
                            .offset(x: 4 + (trackW - 8) * p - 0.5)
                    }

                    Circle()
                        .fill(Color.rvText)
                        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                        .frame(width: 12, height: 12)
                        .offset(x: handleX - 6)
                }
                .frame(height: 22)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let pct = max(0, min(1, (drag.location.x - 4) / (trackW - 8)))
                            value = Int(round(pct * Double(length - 1)))
                        }
                )
            }
            .frame(height: 22)
        }
    }
}
