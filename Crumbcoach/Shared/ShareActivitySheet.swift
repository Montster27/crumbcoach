import SwiftUI
import UIKit

// Thin `UIActivityViewController` wrapper used by screens that want to hand
// items to the iOS share sheet. Mostly used for Markdown / URL share
// payloads from RecipeDetail, Journal, and the Settings diagnostic share.

struct ShareActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController,
                                 context: Context) {}
}
