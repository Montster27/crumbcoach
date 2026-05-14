import Foundation
import UIKit

// Single seam every Cloud AI feature goes through. Owns the Anthropic key
// (Keychain), the HTTP request shape (Messages API), and the response
// parsing (decode JSON the model emits into a typed `Output`). Every
// Tier 1 + Tier 2 feature builds on top — no other file in the app talks
// to the Anthropic SDK / HTTP directly.
//
// Privacy / safety contract (per haiku.md "Cross-cutting decisions"):
// - The key only exists on this device, in Keychain, after the user types
//   it into Settings. We never log it, never write it to JSON, never send
//   it to a remote we don't control.
// - Every call site builds its own system prompt + structured-output
//   schema description. This file is dumb plumbing.
// - We pin the model version at the call site, not here, so each surface
//   can upgrade independently with its own eval pass.

enum RemoteAIClient {

    // MARK: - Keychain plumbing

    /// Account label the Keychain wrapper uses. App-scoped so other
    /// services on the device can't read it.
    static let keychainAccount = "com.monty.crumbcoach.app.anthropic.apiKey"

    /// True when the user has saved an API key. Settings reads this to
    /// decide whether the Cloud AI toggle is interactable.
    static var isConfigured: Bool {
        guard let key = Keychain.readString(account: keychainAccount) else {
            return false
        }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Persist the user's API key. Whitespace-trimmed; passing an empty
    /// string deletes the entry. Returns false when the Keychain write
    /// itself fails — the UI surfaces a one-shot error in that case.
    @discardableResult
    static func setAPIKey(_ key: String) -> Bool {
        Keychain.writeString(key, account: keychainAccount)
    }

    /// Wipe the stored key. Settings "Remove key" calls this.
    static func clearAPIKey() {
        Keychain.delete(account: keychainAccount)
    }

    // MARK: - Errors

    enum Error: LocalizedError {
        case notConfigured
        case disabledByUser
        case requestFailed(String)
        case httpStatus(Int, body: String?)
        case decodingFailed(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Add your Anthropic API key in Settings → Cloud AI first."
            case .disabledByUser:
                return "Cloud AI features are turned off in Settings."
            case .requestFailed(let msg):
                return "Couldn't reach Claude: \(msg)"
            case .httpStatus(let code, let body):
                if let body, !body.isEmpty { return "Claude returned HTTP \(code): \(body)" }
                return "Claude returned HTTP \(code)."
            case .decodingFailed(let msg):
                return "Claude returned an unexpected response shape: \(msg)"
            }
        }
    }

    // MARK: - Image payload

    /// One image-attachment for a request. JPEG bytes get base64'd into
    /// the Anthropic image content block. We resize down to ≤ 1568 px on
    /// the long edge before encoding — that's the upper bound the
    /// vision-capable Claude models actually look at, so sending a 12 MP
    /// camera grab just inflates the request.
    struct ImagePayload {
        let jpegData: Data

        init(uiImage: UIImage, maxDimension: CGFloat = 1568, jpegQuality: CGFloat = 0.85) {
            let resized = Self.resize(uiImage, longEdge: maxDimension)
            self.jpegData = resized.jpegData(compressionQuality: jpegQuality) ?? Data()
        }

        private static func resize(_ image: UIImage, longEdge: CGFloat) -> UIImage {
            let size = image.size
            let longest = max(size.width, size.height)
            guard longest > longEdge else { return image }
            let scale = longEdge / longest
            let target = CGSize(width: size.width * scale, height: size.height * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: target, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: target))
            }
        }
    }

    // MARK: - Public call

    /// Send a single user message (text + optional images) to the
    /// Anthropic Messages API and decode the response body as
    /// `Output`. The model is asked to emit ONLY a JSON object; we strip
    /// markdown fences before decoding so a fence-wrapped reply still
    /// works.
    ///
    /// - Parameters:
    ///   - model: The Anthropic model id (pin per surface, not globally).
    ///   - systemPrompt: System-role instructions. Each call site
    ///     embeds its own structured-output schema description here.
    ///   - userText: User-role text block.
    ///   - images: Zero or more image payloads sent before the text.
    ///   - outputType: The `Decodable` shape the model is expected to
    ///     emit.
    ///   - maxTokens: Per-call output cap. Defaults to 1024 — small
    ///     diagnoses fit comfortably; recipe-import calls can raise.
    static func generate<Output: Decodable>(
        model: String,
        systemPrompt: String,
        userText: String,
        images: [ImagePayload] = [],
        outputType: Output.Type,
        maxTokens: Int = 1024
    ) async throws -> Output {
        guard let key = Keychain.readString(account: keychainAccount),
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Error.notConfigured
        }

        var content: [[String: Any]] = []
        for image in images {
            let base64 = image.jpegData.base64EncodedString()
            content.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": base64,
                ],
            ])
        }
        content.append(["type": "text", "text": userText])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": [["role": "user", "content": content]],
        ]

        guard let url = URL(string: "https://api.anthropic.com/v1/messages"),
              let payload = try? JSONSerialization.data(withJSONObject: body) else {
            throw Error.requestFailed("Couldn't build request.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = payload
        request.timeoutInterval = 30

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Error.requestFailed(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let snippet = String(data: data, encoding: .utf8)?
                .prefix(280).description
            throw Error.httpStatus(http.statusCode, body: snippet)
        }

        guard let envelope = try? JSONDecoder().decode(MessagesResponse.self, from: data) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(160).description ?? "<binary>"
            throw Error.decodingFailed("envelope not parseable: \(snippet)")
        }
        let combined = envelope.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: "\n")
        let stripped = stripJSONFences(combined)
        guard let jsonData = stripped.data(using: .utf8) else {
            throw Error.decodingFailed("empty content")
        }
        do {
            return try JSONDecoder().decode(Output.self, from: jsonData)
        } catch {
            let snippet = stripped.prefix(160).description
            throw Error.decodingFailed("\(error.localizedDescription) — body: \(snippet)")
        }
    }

    // MARK: - Helpers

    /// Trim ```json … ``` fences off model output so JSONDecoder doesn't
    /// see the markdown wrapper. Idempotent on un-fenced input.
    private static func stripJSONFences(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            }
            if let fenceRange = text.range(of: "```", options: .backwards) {
                text = String(text[..<fenceRange.lowerBound])
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Envelope

    /// Subset of the Messages-API response envelope we actually look at.
    /// Other fields (`id`, `model`, `stop_reason`, `usage`, …) are
    /// ignored on decode.
    private struct MessagesResponse: Decodable {
        let content: [ContentBlock]
    }

    private struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
}
