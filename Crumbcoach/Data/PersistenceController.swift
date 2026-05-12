import Foundation

// Local persistence via Codable JSON in Application Support.
//
// The Code Spec (§4.1 iOS / §5.1 Android) calls for SwiftData + CloudKit /
// Room + Drive AppData. JSON-on-disk is a pragmatic stand-in: zero schema
// migrations, no `@Model` ceremony for deeply nested value types, and a
// trivial path forward — when we move to SwiftData, the same `PersistedState`
// shape becomes the import dump.
//
// File location: <Application Support>/Crumbcoach/state.json
// Atomic writes via `.atomic`; debounced via AppState.saveSoon().

final class PersistenceController {
    static let shared = PersistenceController()

    private let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(filename: String = "state.json",
         directoryName: String = "Crumbcoach",
         baseDirectory: FileManager.SearchPathDirectory = .applicationSupportDirectory) {
        let fm = FileManager.default
        let base = (try? fm.url(for: baseDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent(directoryName, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        self.url = dir.appendingPathComponent(filename)

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    /// Decode the persisted state. Returns nil on first launch or on read /
    /// schema-mismatch errors (in which case we fall back to seed data).
    func load<T: Decodable>(_ type: T.Type = T.self) -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(T.self, from: data)
        } catch {
            // Schema drift: rename the bad file and fall back to seeds.
            let backup = url.deletingPathExtension().appendingPathExtension("bad.\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            return nil
        }
    }

    func save<T: Encodable>(_ value: T) {
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Persistence failures are non-fatal — log and continue.
            // In production wire this to crash reporting (Sentry / OSLog).
        }
    }

    /// Wipe state.  Useful for the “reset to sample data” affordance.
    func reset() {
        try? FileManager.default.removeItem(at: url)
    }

    var fileURL: URL { url }
}
