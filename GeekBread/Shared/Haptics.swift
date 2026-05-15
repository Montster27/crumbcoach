import UIKit

// Centralized haptic feedback. Every UI surface that wants tactile feedback
// reaches through here so we have one place to tune intensities, swap to
// `UICanvasFeedbackGenerator` later, or disable the whole layer behind a
// Settings toggle.
//
// `UIImpactFeedbackGenerator` etc. are cheap to allocate on demand — the
// real cost is the call to `prepare()`, which warms the Taptic engine. We
// don't prepare here because the events we trigger from are user-initiated
// (button taps), and warming would mean keeping a reference around. The
// system already handles a tiny latency budget well enough for one-shot
// taps.

enum Haptics {

    /// Light bump — used for the small, repeated "tick" actions: marking a
    /// fold, ticking a chip on/off, scrubbing a slider into a discrete spot.
    static func tick() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Medium bump — used for the more meaningful state transitions:
    /// advancing or skipping a stage. Distinct enough from `.tick` that a
    /// user can feel which one fired.
    static func advance() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Notification success — used once at `completeBake`. The intent is
    /// "we finished something significant", not "we performed an action."
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Selection — the soft "click" the user expects when toggling a
    /// segmented control or chip.
    static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
