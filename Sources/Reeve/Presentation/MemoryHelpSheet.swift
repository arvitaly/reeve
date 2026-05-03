import SwiftUI

/// Surface D — modal sheet from popover. Four short cards explaining the
/// memory model in plain English. Designed for someone who has never opened
/// Activity Monitor.
///
/// Activated only by the "How memory accounting works" link in the detail
/// panel. No first-launch onboarding (per design — Reeve is opinionated).
struct MemoryHelpSheet: View {
    @State private var index: Int = 0
    let onClose: () -> Void

    private static let cards: [HelpCard] = [
        HelpCard(
            title: "Used vs Cached vs Free",
            body: """
            macOS aggressively keeps RAM full. Empty RAM is wasted RAM. Most of \
            what looks "used" is actually cached files the system can drop in \
            milliseconds.

            The number that matters for slowdown is **available** (cached + free), \
            not **free**. Reeve shows both.
            """,
            bullets: [
                ("Used",   "what's actually in flight"),
                ("Cached", "files in case you need them"),
                ("Free",   "hasn't been touched yet")
            ]
        ),
        HelpCard(
            title: "What apps actually consume",
            body: """
            Each app's number is its **physical footprint**: real RAM (resident) \
            plus what the system compressed from it plus what it mapped through \
            the GPU. This is what Apple's own Activity Monitor uses.

            If two apps share a library, the library's bytes count toward whichever \
            app touched it first. We don't double-count.
            """,
            bullets: []
        ),
        HelpCard(
            title: "What's hard to measure",
            body: """
            Some memory the kernel uses isn't owned by any single app — XPC buffers \
            between processes, kernel zones, GPU mappings without an owning task. \
            Reading these requires running as root.

            Reeve marks this honestly as **Other (unmeasured)** with a striped \
            pattern. We tell you what's likely in there — we won't pretend we \
            measured it. An opt-in helper (coming in v0.3.0) will split it open.
            """,
            bullets: []
        ),
        HelpCard(
            title: "Why some memory looks gray",
            body: """
            Wherever you see the striped pattern, it means: *we know this category \
            exists, but we can't put a number on it without privileges Reeve doesn't \
            have.*

            Solid colored bars are measured. Striped bars are inferred from totals. \
            The same convention runs through the bar at the top, the detail panel, \
            and any chart in Reeve.
            """,
            bullets: []
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            cardArea
            pager
        }
        .frame(width: 460, height: 520)
        .background(Color.rvBg)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("How memory works")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.rvText)
            Spacer()
            Button(action: onClose) {
                HStack(spacing: 3) {
                    Text("Close")
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(Color.rvTextFaint)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: - Card area

    private var cardArea: some View {
        let card = Self.cards[index]
        return VStack(alignment: .leading, spacing: 12) {
            Text("Card \(index + 1) of \(Self.cards.count)")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Color.rvTextFaint)

            VStack(alignment: .leading, spacing: 14) {
                Text(card.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.rvText)

                Text(formattedBody(card.body))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.rvTextDim)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if !card.bullets.isEmpty {
                    miniGlossary(card.bullets)
                }

                if index == Self.cards.count - 1 {
                    stripeSwatchExample
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.rvBgElev)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.rvHairline, lineWidth: 0.5)
                    )
            )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .id(index)
        .transition(.opacity.combined(with: .move(edge: .trailing)))
        .animation(.easeInOut(duration: 0.2), value: index)
    }

    private func miniGlossary(_ items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    Circle().fill(Color.rvAccent).frame(width: 5, height: 5)
                    Text(item.0)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.rvText)
                        .frame(width: 70, alignment: .leading)
                    Text(item.1)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.rvTextDim)
                }
            }
        }
    }

    private var stripeSwatchExample: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.rvInputBg)
                UnmeasurableStripes(spacing: 2, lineWidth: 0.8, opacity: 0.5, cornerRadius: 3)
            }
            .frame(width: 60, height: 16)
            Text("This pattern means: not measured.")
                .font(.system(size: 11))
                .foregroundStyle(Color.rvTextDim)
        }
        .padding(.top, 4)
    }

    // MARK: - Pager

    private var pager: some View {
        HStack(spacing: 18) {
            arrowButton(systemName: "chevron.left", enabled: index > 0) {
                if index > 0 { index -= 1 }
            }
            HStack(spacing: 8) {
                ForEach(0..<Self.cards.count, id: \.self) { i in
                    Circle()
                        .fill(i == index ? Color.rvText : Color.rvHairline)
                        .frame(width: 6, height: 6)
                        .onTapGesture { index = i }
                }
            }
            arrowButton(systemName: "chevron.right", enabled: index < Self.cards.count - 1) {
                if index < Self.cards.count - 1 { index += 1 }
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }

    private func arrowButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(enabled ? Color.rvText : Color.rvHairline)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Markdown-ish bold

    private func formattedBody(_ text: String) -> AttributedString {
        // Convert **bold** → bold runs.
        var current = AttributedString(text)
        while let range = current.range(of: "**") {
            let after = current[range.upperBound...]
            if let close = after.range(of: "**") {
                var boldRun = current[range.upperBound..<close.lowerBound]
                boldRun.font = .system(size: 12, weight: .semibold).leading(.standard)
                boldRun.foregroundColor = .rvText
                var rebuilt = AttributedString(current[..<range.lowerBound])
                rebuilt.append(boldRun)
                rebuilt.append(AttributedString(current[close.upperBound...]))
                current = rebuilt
            } else {
                break
            }
        }
        return current
    }
}

private struct HelpCard {
    let title: String
    let body: String
    let bullets: [(String, String)]
}
