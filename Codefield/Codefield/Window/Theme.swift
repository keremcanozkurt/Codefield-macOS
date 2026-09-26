import AppKit
import SwiftUI

// The palette of the workspace page (upstream globals.css), so the native
// chrome and the page read as one surface.
enum Theme {
    static let background = Color(hex: 0x08090C)
    static let surface = Color(hex: 0x0D0F13)
    static let foreground = Color(hex: 0xE8E6E0)
    static let muted = Color(hex: 0x8B8F99)
    static let subtle = Color(hex: 0x5C606A)
    static let line = Color(hex: 0x1D2027)
    static let lineStrong = Color(hex: 0x33373F)
    static let warning = Color(hex: 0xC99A5B)
    static let danger = Color(hex: 0xD9796B)

    static let backgroundColor = NSColor(red: 8 / 255, green: 9 / 255, blue: 12 / 255, alpha: 1)
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
