import AppKit
import SwiftUI

// MARK: - oklch → sRGB

// Pipeline: oklch → oklab → linear LMS → linear sRGB → gamma sRGB
// Matrices from https://bottosson.github.io/posts/oklab/
private func oklchToSRGB(_ l: Double, _ c: Double, hDeg: Double) -> (r: Double, g: Double, b: Double) {
    let hRad = hDeg * .pi / 180
    let a    = c * cos(hRad)
    let bOK  = c * sin(hRad)

    let l_ = l + 0.3963377774 * a + 0.2158037573 * bOK
    let m_ = l - 0.1055613458 * a - 0.0638541728 * bOK
    let s_ = l - 0.0894841775 * a - 1.2914855480 * bOK

    let lc = l_ * l_ * l_
    let mc = m_ * m_ * m_
    let sc = s_ * s_ * s_

    let lr =  4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc
    let lg = -1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc
    let lb = -0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc

    func toGamma(_ u: Double) -> Double {
        guard u > 0 else { return 0 }
        return u <= 0.0031308 ? 12.92 * u : 1.055 * pow(u, 1 / 2.4) - 0.055
    }
    return (r: toGamma(lr), g: toGamma(lg), b: toGamma(lb))
}

// MARK: - Adaptive Color helpers

private typealias RGB = (r: Double, g: Double, b: Double)

private func rvAdaptive(_ light: NSColor, _ dark: NSColor) -> Color {
    Color(NSColor(name: nil, dynamicProvider: {
        $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
    }))
}

private func rvAdaptive(l: RGB, d: RGB) -> Color {
    rvAdaptive(
        NSColor(srgbRed: l.r, green: l.g, blue: l.b, alpha: 1),
        NSColor(srgbRed: d.r, green: d.g, blue: d.b, alpha: 1)
    )
}

// MARK: - Color tokens

extension Color {
    /// Brand accent — interactive elements, segmented controls, selected states
    static var rvAccent: Color {
        rvAdaptive(
            l: oklchToSRGB(0.55, 0.14, hDeg: 235),
            d: oklchToSRGB(0.74, 0.13, hDeg: 230)
        )
    }

    // MARK: Semantic severity ramp

    static var rvOk: Color {
        rvAdaptive(
            l: oklchToSRGB(0.55, 0.16, hDeg: 162),
            d: oklchToSRGB(0.66, 0.13, hDeg: 162)
        )
    }

    static var rvWarn: Color {
        rvAdaptive(
            l: oklchToSRGB(0.68, 0.17, hDeg: 75),
            d: oklchToSRGB(0.78, 0.15, hDeg: 75)
        )
    }

    static var rvOver: Color {
        rvAdaptive(
            l: oklchToSRGB(0.55, 0.22, hDeg: 25),
            d: oklchToSRGB(0.66, 0.21, hDeg: 25)
        )
    }

    static var rvOkGlow: Color {
        rvAdaptive(
            NSColor(srgbRed: oklchToSRGB(0.55, 0.16, hDeg: 162).r, green: oklchToSRGB(0.55, 0.16, hDeg: 162).g, blue: oklchToSRGB(0.55, 0.16, hDeg: 162).b, alpha: 0.18),
            NSColor(srgbRed: oklchToSRGB(0.66, 0.13, hDeg: 162).r, green: oklchToSRGB(0.66, 0.13, hDeg: 162).g, blue: oklchToSRGB(0.66, 0.13, hDeg: 162).b, alpha: 0.22)
        )
    }

    static var rvWarnGlow: Color {
        rvAdaptive(
            NSColor(srgbRed: oklchToSRGB(0.68, 0.17, hDeg: 75).r, green: oklchToSRGB(0.68, 0.17, hDeg: 75).g, blue: oklchToSRGB(0.68, 0.17, hDeg: 75).b, alpha: 0.18),
            NSColor(srgbRed: oklchToSRGB(0.78, 0.15, hDeg: 75).r, green: oklchToSRGB(0.78, 0.15, hDeg: 75).g, blue: oklchToSRGB(0.78, 0.15, hDeg: 75).b, alpha: 0.20)
        )
    }

    static var rvOverGlow: Color {
        rvAdaptive(
            NSColor(srgbRed: oklchToSRGB(0.55, 0.22, hDeg: 25).r, green: oklchToSRGB(0.55, 0.22, hDeg: 25).g, blue: oklchToSRGB(0.55, 0.22, hDeg: 25).b, alpha: 0.22),
            NSColor(srgbRed: oklchToSRGB(0.66, 0.21, hDeg: 25).r, green: oklchToSRGB(0.66, 0.21, hDeg: 25).g, blue: oklchToSRGB(0.66, 0.21, hDeg: 25).b, alpha: 0.28)
        )
    }

    static var rvAccentGlow: Color {
        rvAdaptive(
            NSColor(srgbRed: oklchToSRGB(0.55, 0.14, hDeg: 235).r, green: oklchToSRGB(0.55, 0.14, hDeg: 235).g, blue: oklchToSRGB(0.55, 0.14, hDeg: 235).b, alpha: 0.16),
            NSColor(srgbRed: oklchToSRGB(0.74, 0.13, hDeg: 230).r, green: oklchToSRGB(0.74, 0.13, hDeg: 230).g, blue: oklchToSRGB(0.74, 0.13, hDeg: 230).b, alpha: 0.22)
        )
    }

    // MARK: Surfaces

    static var rvBg: Color {
        rvAdaptive(
            l: oklchToSRGB(0.985, 0.003, hDeg: 250),
            d: oklchToSRGB(0.205, 0.008, hDeg: 255)
        )
    }

    static var rvBgElev: Color {
        rvAdaptive(
            l: oklchToSRGB(1, 0, hDeg: 0),
            d: oklchToSRGB(0.245, 0.009, hDeg: 255)
        )
    }

    // MARK: Text

    static var rvText: Color {
        rvAdaptive(
            l: oklchToSRGB(0.18, 0.005, hDeg: 250),
            d: oklchToSRGB(0.96, 0.005, hDeg: 250)
        )
    }

    static var rvTextDim: Color {
        rvAdaptive(
            l: oklchToSRGB(0.42, 0.008, hDeg: 250),
            d: oklchToSRGB(0.74, 0.008, hDeg: 250)
        )
    }

    static var rvTextFaint: Color {
        rvAdaptive(
            l: oklchToSRGB(0.62, 0.008, hDeg: 250),
            d: oklchToSRGB(0.54, 0.008, hDeg: 250)
        )
    }

    // MARK: Interactive surfaces

    static var rvRowHover: Color {
        rvAdaptive(
            NSColor.black.withAlphaComponent(0.04),
            NSColor.white.withAlphaComponent(0.04)
        )
    }

    static var rvRowSelected: Color {
        rvAdaptive(
            NSColor.black.withAlphaComponent(0.06),
            NSColor.white.withAlphaComponent(0.07)
        )
    }

    static var rvRowExpanded: Color {
        rvAdaptive(
            NSColor.black.withAlphaComponent(0.02),
            NSColor.white.withAlphaComponent(0.025)
        )
    }

    static var rvInputBg: Color {
        rvAdaptive(
            NSColor.black.withAlphaComponent(0.035),
            NSColor.white.withAlphaComponent(0.05)
        )
    }

    static var rvPill: Color {
        rvAdaptive(
            NSColor.black.withAlphaComponent(0.05),
            NSColor.white.withAlphaComponent(0.08)
        )
    }

    static var rvPillHover: Color {
        rvAdaptive(
            NSColor.black.withAlphaComponent(0.10),
            NSColor.white.withAlphaComponent(0.13)
        )
    }

    // MARK: Hairlines

    static var rvHairline: Color {
        rvAdaptive(
            NSColor.black.withAlphaComponent(0.06),
            NSColor.white.withAlphaComponent(0.07)
        )
    }

    static var rvHairlineStrong: Color {
        rvAdaptive(
            NSColor.black.withAlphaComponent(0.12),
            NSColor.white.withAlphaComponent(0.13)
        )
    }

    static var rvWindowEdge: Color {
        rvAdaptive(
            NSColor.black.withAlphaComponent(0.10),
            NSColor.white.withAlphaComponent(0.10)
        )
    }

    // MARK: Legacy aliases

    /// @deprecated Use rvOver
    static var rvDanger: Color { .rvOver }

    static var rvBarTrack: Color { .rvInputBg }

    static var rvBarNormal: Color {
        let rgb = oklchToSRGB(0.55, 0.01, hDeg: 250)
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    static var rvDotNormal: Color {
        rvAdaptive(
            l: oklchToSRGB(0.65, 0.008, hDeg: 250),
            d: oklchToSRGB(0.50, 0.008, hDeg: 250)
        )
    }

    // MARK: Memory breakdown colors

    static var rvMemWired: Color {
        let rgb = oklchToSRGB(0.55, 0.12, hDeg: 30)
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    static var rvMemActive: Color {
        let rgb = oklchToSRGB(0.60, 0.14, hDeg: 145)
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    static var rvMemCompressed: Color {
        let rgb = oklchToSRGB(0.62, 0.15, hDeg: 270)
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    static var rvMemInactive: Color {
        let rgb = oklchToSRGB(0.55, 0.04, hDeg: 250)
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}

// MARK: - App category

enum AppCategory: String, CaseIterable, Codable {
    case browser, dev, comm, media, creative, system, utility

    var label: String {
        switch self {
        case .browser:  return "Browser"
        case .dev:      return "Dev"
        case .comm:     return "Comms"
        case .media:    return "Media"
        case .creative: return "Creative"
        case .system:   return "System"
        case .utility:  return "Utility"
        }
    }

    var color: Color {
        switch self {
        case .browser:  return .rvCatBrowser
        case .dev:      return .rvCatDev
        case .comm:     return .rvCatComm
        case .media:    return .rvCatMedia
        case .creative: return .rvCatCreative
        case .system:   return .rvCatSystem
        case .utility:  return .rvCatUtility
        }
    }
}

extension Color {
    static var rvCatBrowser: Color {
        rvAdaptive(l: oklchToSRGB(0.55, 0.14, hDeg: 230), d: oklchToSRGB(0.74, 0.13, hDeg: 230))
    }
    static var rvCatDev: Color {
        rvAdaptive(l: oklchToSRGB(0.52, 0.16, hDeg: 290), d: oklchToSRGB(0.74, 0.14, hDeg: 290))
    }
    static var rvCatComm: Color {
        rvAdaptive(l: oklchToSRGB(0.58, 0.16, hDeg: 340), d: oklchToSRGB(0.78, 0.14, hDeg: 340))
    }
    static var rvCatMedia: Color {
        rvAdaptive(l: oklchToSRGB(0.55, 0.16, hDeg: 145), d: oklchToSRGB(0.78, 0.16, hDeg: 145))
    }
    static var rvCatCreative: Color {
        rvAdaptive(l: oklchToSRGB(0.60, 0.16, hDeg: 50), d: oklchToSRGB(0.78, 0.14, hDeg: 50))
    }
    static var rvCatSystem: Color {
        rvAdaptive(l: oklchToSRGB(0.55, 0.02, hDeg: 250), d: oklchToSRGB(0.66, 0.02, hDeg: 250))
    }
    static var rvCatUtility: Color {
        rvAdaptive(l: oklchToSRGB(0.62, 0.15, hDeg: 75), d: oklchToSRGB(0.78, 0.14, hDeg: 75))
    }
}

// MARK: - Severity

enum Severity: Comparable, Hashable {
    case normal, warn, over
}

extension Severity {
    var color: Color {
        switch self {
        case .normal: .rvOk
        case .warn:   .rvWarn
        case .over:   .rvOver
        }
    }

    var glowColor: Color {
        switch self {
        case .normal: .rvOkGlow
        case .warn:   .rvWarnGlow
        case .over:   .rvOverGlow
        }
    }

    var textColor: Color {
        switch self {
        case .normal: .rvTextDim
        case .warn:   .rvWarn
        case .over:   .rvOver
        }
    }

    var barColor: Color {
        switch self {
        case .normal: .rvBarNormal
        case .warn:   .rvWarn
        case .over:   .rvOver
        }
    }

    var dotColor: Color {
        switch self {
        case .normal: .rvDotNormal
        case .warn:   .rvWarn
        case .over:   .rvOver
        }
    }

    var stripeColor: Color {
        switch self {
        case .normal: .clear
        case .warn:   .rvWarn.opacity(0.45)
        case .over:   .rvOver.opacity(0.45)
        }
    }
}

// MARK: - Typography

enum RVFont {
    static func ui(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Formatting

func formatMem(_ bytes: Double) -> String {
    if bytes >= 1_073_741_824 {
        let gb = bytes / 1_073_741_824
        let formatted = String(format: "%.2f", gb)
            .replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
        return formatted + " GB"
    }
    return "\(Int(bytes / (1024 * 1024))) MB"
}

func formatMemShort(_ bytes: Double) -> String {
    if bytes >= 1_073_741_824 {
        return String(format: "%.1fG", bytes / 1_073_741_824)
    }
    return "\(Int(bytes / (1024 * 1024)))M"
}
