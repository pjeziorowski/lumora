// App/Sources/Accessibility/Palette.swift
//
// Text colours that keep at least 4.5:1 contrast (WCAG AA for body text) on the plain and
// grouped backgrounds in light and dark mode, and go further with Increase Contrast. The
// system `.secondary` style measures about 3.3:1 on a grouped list background in light
// mode, and plain system green, orange and red fall below 4:1 on white, which the
// accessibility audit reports. Ratios in the comments are against #F2F2F7 (light grouped
// background) and #1C1C1E (dark grouped row).

import SwiftUI
import UIKit

extension Color {
    /// Secondary text: 6.0:1 light, 7.7:1 dark.
    static let subdued = dynamic(light: 0x5C5C61, dark: 0xAEAEB2, lightHigh: 0x3A3A3E, darkHigh: 0xD1D1D6)
    /// "Visible", "ready" and other good news: 4.8:1 light, 8.4:1 dark.
    static let positive = dynamic(light: 0x1E7B34, dark: 0x30D158, lightHigh: 0x145A25, darkHigh: 0x5AE07C)
    /// Warnings: 5.0:1 light, 8.3:1 dark.
    static let caution = dynamic(light: 0xA35200, dark: 0xFF9F0A, lightHigh: 0x7A3D00, darkHigh: 0xFFB340)
    /// Errors: 5.1:1 light, 6.0:1 dark.
    static let critical = dynamic(light: 0xC4281C, dark: 0xFF6961, lightHigh: 0x9A1C12, darkHigh: 0xFF8A84)

    private static func dynamic(light: UInt32, dark: UInt32, lightHigh: UInt32, darkHigh: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let high = traits.accessibilityContrast == .high
            switch traits.userInterfaceStyle {
            case .dark: return UIColor(rgb: high ? darkHigh : dark)
            default: return UIColor(rgb: high ? lightHigh : light)
            }
        })
    }
}

extension ShapeStyle where Self == Color {
    static var subdued: Color { Color.subdued }
    static var positive: Color { Color.positive }
    static var caution: Color { Color.caution }
    static var critical: Color { Color.critical }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
