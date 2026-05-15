import SwiftUI

// iPhone-specific spacing tokens. Additions to the shared `Theme` and
// `Typography` — these never mutate the iPad tokens, they just give the
// compact iPhone surfaces a single place to tune density.
//
// Typography uses the existing `Typography` helper (Dynamic Type-aware);
// iPhone screens just call it with smaller point sizes (~75% of iPad).

enum PhoneTheme {
    /// Horizontal padding from screen edge to card content. iPad uses 32pt;
    /// iPhone needs to claw back margin so cards still feel composed at
    /// 390pt-wide canvases.
    static let screenHPad: CGFloat = 16
    static let screenVPad: CGFloat = 16

    /// Inside cards.
    static let cardPad: CGFloat   = 16
    static let cardSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 20

    static let cardRadius: CGFloat = 14

    /// Now-baking mini-bar height — used by iPhoneShell's safeAreaInset and
    /// for the ActiveBake tab to know how much bottom padding to leave so
    /// its own primary action button doesn't hide under the mini-bar (it
    /// shouldn't show on the Bake tab anyway, but defensive).
    static let miniBarHeight: CGFloat = 60
}
