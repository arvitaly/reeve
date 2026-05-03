import SwiftUI

/// Single non-wrapping line below the bar. Replaces the old wrapping legend.
/// Shows the top three "loud" used categories with plain-English labels +
/// a trailing chevron that opens the memory detail panel.
struct MemorySummaryLine: View {
    let model: MemoryModel
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(model.summaryHighlights) { seg in
                summaryItem(seg)
            }
            if model.hasUnmeasurable
                && !model.summaryHighlights.contains(where: { $0.isUnmeasurable }) {
                unmeasuredBadge
            }
            Spacer(minLength: 4)
            chevron
        }
        .frame(height: 16)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
    }

    private func summaryItem(_ seg: MemorySegment) -> some View {
        HStack(spacing: 4) {
            if seg.isUnmeasurable {
                UnmeasurableDot(size: 7)
            } else {
                Circle()
                    .fill(seg.color)
                    .frame(width: 6, height: 6)
            }
            Text(seg.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(seg.isUnmeasurable ? Color.rvTextFaint : Color.rvTextDim)
                .tracking(-0.1)
            Text(shortBytes(seg.bytes))
                .font(RVFont.mono(size: 10))
                .foregroundStyle(seg.isUnmeasurable ? Color.rvTextFaint : Color.rvText)
        }
    }

    private var unmeasuredBadge: some View {
        HStack(spacing: 3) {
            UnmeasurableDot(size: 7)
            Text("?")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.rvTextFaint)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color.rvInputBg, in: RoundedRectangle(cornerRadius: 3))
    }

    private var chevron: some View {
        HStack(spacing: 2) {
            Text(isExpanded ? "Hide" : "Detail")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.rvAccent)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.rvAccent)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .help(isExpanded ? "Collapse memory detail" : "Open memory detail")
    }

    private func shortBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 10 { return String(format: "%.0fG", gb) }
        if gb >= 1.0 { return String(format: "%.1fG", gb) }
        return String(format: "%.0fM", Double(bytes) / 1_048_576)
    }
}
