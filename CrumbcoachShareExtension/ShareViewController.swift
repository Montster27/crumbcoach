import UIKit
import Social
import UniformTypeIdentifiers

// Safari → Share → CrumbCoach. The extension reads the shared URL from the
// extension context's input items, encodes it as a `crumbcoach://import`
// deep link, asks iOS to open the main app, and completes the request.
//
// We intentionally don't show a confirmation UI — the user has already
// tapped Share → CrumbCoach and any extra screen is friction. A subclass
// of `SLComposeServiceViewController` returns nil from `presentationStyle`
// shorthand via the Info.plist `NSExtensionAttributes` block.

class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        handleShare()
    }

    private func handleShare() {
        Task { [weak self] in
            guard let self else { return }
            if let url = await self.extractURL() {
                self.openMainApp(with: url)
            }
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    /// Walk the input items + attachments looking for the first URL-typed
    /// payload. Most Safari shares hand us a single URL item; some hand a
    /// plain-text URL string, so we accept both. Only http/https schemes
    /// are forwarded — anything else (mailto:, ftp:, javascript:, custom
    /// app schemes) would just fail in the importer and confuse the user,
    /// so we drop it here and let the extension complete silently.
    private func extractURL() async -> URL? {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            return nil
        }
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = try? await provider.loadItem(
                        forTypeIdentifier: UTType.url.identifier
                    ) as? URL,
                       isWebURL(url) {
                        return url
                    }
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let raw = try? await provider.loadItem(
                        forTypeIdentifier: UTType.plainText.identifier
                    ) as? String,
                       let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
                       isWebURL(url) {
                        return url
                    }
                }
            }
        }
        return nil
    }

    private func isWebURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }

    /// Hand the shared URL to the main app via the `crumbcoach://import`
    /// deep link. Walks up the responder chain looking for an object that
    /// responds to `openURL:` — the documented contract for extensions
    /// opening their containing app.
    private func openMainApp(with sharedURL: URL) {
        var components = URLComponents()
        components.scheme = "crumbcoach"
        components.host = "import"
        components.queryItems = [URLQueryItem(name: "url", value: sharedURL.absoluteString)]
        guard let deepLink = components.url else { return }

        var responder: UIResponder? = self
        let selector = sel_registerName("openURL:")
        while let current = responder {
            if current.responds(to: selector) {
                _ = current.perform(selector, with: deepLink)
                return
            }
            responder = current.next
        }
    }
}
