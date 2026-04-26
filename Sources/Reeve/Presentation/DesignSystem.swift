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
    /// steel-cyan accent — primary interactive color, severity warn
    static var rvAccent: Color {
        rvAdaptive(
            l: oklchToSRGB(0.55, 0.13, hDeg: 235),
            d: oklchToSRGB(0.74, 0.12, hDeg: 230)
        )
    }

    /// warm-red danger — severity over
    static var rvDanger: Color {
        rvAdaptive(
            l: oklchToSRGB(0.55, 0.22, hDeg: 25),
            d: oklchToSRGB(0.68, 0.20, hDeg: 25)
        )
    }

    /// secondary text — labels, values
    static var rvTextDim: Color {
        rvAdaptive(
            l: oklchToSRGB(0.42, 0.008, hDeg: 250),
            d: oklchToSRGB(0.72, 0.008, hDeg: 250)
        )
    }

    /// tertiary text — hints, counts
    static var rvTextFaint: Color {
        rvAdaptive(
            l: oklchToSRGB(0.62, 0.008, hDeg: 250),
            d: oklchToSRGB(0.52, 0.008, hDeg: 250)
        )
    }

    /// row selection background
    static var rvRowSelected: Color {
        rvAdaptive(
            NSColor.black.withAlphaComponent(0.040),
            NSColor.white.withAlphaComponent(0.045)
        )
    }

    /// row expanded background
    static var rvRowExpanded: Color {
        rvAdaptive(
            NSColor.black.withAlphaComponent(0.020),
            NSColor.white.withAlphaComponent(0.025)
        )
    }

    /// mini-bar and pressure-bar track (empty portion)
    static var rvBarTrack: Color {
        rvAdaptive(
            NSColor.black.withAlphaComponent(0.070),
            NSColor.white.withAlphaComponent(0.080)
        )
    }

    /// mini-bar fill at normal severity — same value in both appearances
    static var rvBarNormal: Color {
        let rgb = oklchToSRGB(0.55, 0.01, hDeg: 250)
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    /// severity dot at normal severity
    static var rvDotNormal: Color {
        rvAdaptive(
            l: oklchToSRGB(0.65, 0.008, hDeg: 250),
            d: oklchToSRGB(0.50, 0.008, hDeg: 250)
        )
    }
}

// MARK: - Severity

enum Severity: Comparable, Hashable {
    case normal, warn, over
}

extension Severity {
    var textColor: Color {
        switch self {
        case .normal: .rvTextDim
        case .warn:   .rvAccent
        case .over:   .rvDanger
        }
    }

    var barColor: Color {
        switch self {
        case .normal: .rvBarNormal
        case .warn:   .rvAccent
        case .over:   .rvDanger
        }
    }

    var dotColor: Color {
        switch self {
        case .normal: .rvDotNormal
        case .warn:   .rvAccent
        case .over:   .rvDanger
        }
    }

    /// left-edge stripe for selected rows; clear when normal
    var stripeColor: Color {
        switch self {
        case .normal: .clear
        case .warn:   .rvAccent.opacity(0.45)
        case .over:   .rvDanger.opacity(0.45)
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
