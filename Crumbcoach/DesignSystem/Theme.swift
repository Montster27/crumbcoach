import SwiftUI

// CrumbCoach design tokens — ported from tokens.css + app.css
// Warm-neutral palette with terracotta primary, generous whitespace.

enum Theme {
    // MARK: Surfaces / backgrounds
    static let surface1   = Color(hex: 0xFCFAF8) // app background
    static let surface2   = Color(hex: 0xF6F1EB) // warmer panel
    static let cardBg     = Color.white

    // MARK: Primary (terracotta)
    static let primary      = Color(hex: 0xB86A3A)
    static let primaryDeep  = Color(hex: 0x8A4C25)
    static let primaryTint  = Color(hex: 0xF7ECE2)
    static let primaryTint2 = Color(hex: 0xEFD9C4)
    static let primaryRing  = Color(hex: 0xB86A3A, alpha: 0.18)

    // MARK: Accent (olive)
    static let accent      = Color(hex: 0x5B6B3E)
    static let accentTint  = Color(hex: 0xEDF1E2)

    // MARK: Warm (amber)
    static let warm        = Color(hex: 0xD97706)
    static let warm50      = Color(hex: 0xFFF7ED)
    static let warm700     = Color(hex: 0xB45309)

    // MARK: Slate (neutrals)
    static let slate50  = Color(hex: 0xF8FAFC)
    static let slate100 = Color(hex: 0xF1F5F9)
    static let slate200 = Color(hex: 0xE2E8F0)
    static let slate300 = Color(hex: 0xCBD5E1)
    static let slate400 = Color(hex: 0x94A3B8)
    static let slate500 = Color(hex: 0x64748B)
    static let slate600 = Color(hex: 0x475569)
    static let slate700 = Color(hex: 0x334155)
    static let slate800 = Color(hex: 0x1E293B)
    static let slate900 = Color(hex: 0x0F172A)
    static let slate950 = Color(hex: 0x020617)

    // MARK: Borders
    static let border1   = slate200
    static let borderSft = Color(hex: 0xDBE4EE)

    // MARK: Status pills (bg, fg)
    static let pillGoodBg  = Color(hex: 0xECFDF5)
    static let pillGoodFg  = Color(hex: 0x047857)
    static let pillWarnBg  = Color(hex: 0xFEF3C7)
    static let pillWarnFg  = Color(hex: 0x92400E)
    static let pillInfoBg  = Color(hex: 0xEFF6FF)
    static let pillInfoFg  = Color(hex: 0x1E40AF)
    static let pillBadBg   = Color(hex: 0xFEF2F2)
    static let pillBadFg   = Color(hex: 0xB91C1C)
    static let pillNeutBg  = Color(hex: 0xF1F5F9)
    static let pillNeutFg  = Color(hex: 0x475569)

    // MARK: Sky (info)
    static let sky400 = Color(hex: 0x38BDF8)
    static let sky500 = Color(hex: 0x0EA5E9)
    static let sky600 = Color(hex: 0x0284C7)

    // MARK: Semantic helpers
    static let success50  = Color(hex: 0xECFDF5)
    static let success600 = Color(hex: 0x059669)
    static let success700 = Color(hex: 0x047857)

    // MARK: Shadows
    static let shadowCard  = Color.black.opacity(0.04)
    static let shadowPanel = Color.black.opacity(0.07)
}

// MARK: - Color hex helper

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8)  & 0xFF) / 255.0
        let b = Double( hex        & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// MARK: - Typography
//
// Custom fonts are available if bundled (Instrument Serif for display, Geist
// for UI, Geist Mono for numerics). Otherwise we fall back to the system
// equivalents. The availability check runs once per family — `UIFont(name:)`
// allocates each call, and we'd otherwise hit it on every label render.

enum Typography {
    static let displayName = "Instrument Serif"
    static let uiName      = "Geist"
    static let monoName    = "Geist Mono"

    private static let displayAvailable: Bool = UIFont(name: displayName, size: 16) != nil
    private static let uiAvailable: Bool      = UIFont(name: uiName, size: 16) != nil
    private static let monoAvailable: Bool    = UIFont(name: monoName, size: 16) != nil

    static func display(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        displayAvailable
            ? Font.custom(displayName, size: size).weight(weight)
            : Font.system(size: size, weight: weight, design: .serif)
    }

    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        uiAvailable
            ? Font.custom(uiName, size: size).weight(weight)
            : Font.system(size: size, weight: weight, design: .default)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        monoAvailable
            ? Font.custom(monoName, size: size).weight(weight)
            : Font.system(size: size, weight: weight, design: .monospaced)
    }
}
