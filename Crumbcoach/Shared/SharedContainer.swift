import Foundation

// Helper for App Group access shared between the main app (which writes the
// widget snapshot) and the widget extension (which reads it). The group id
// must match the entitlements file in BOTH targets, hence the constant.
//
// Gracefully degrades when the entitlement isn't provisioned: reads return
// nil and writes are silently skipped. Build still runs; widgets just don't
// update.

enum SharedContainer {

    /// Same App Group identifier in `Crumbcoach.entitlements` and
    /// `CrumbcoachWidgets.entitlements`. Forks to another team change all
    /// three references (plus the team id) in lockstep.
    static let groupIdentifier = "group.com.monty.crumbcoach.shared"

    /// URL of the App Group container directory, or nil when the
    /// entitlement isn't reachable (running without provisioning, simulator
    /// with a free team, etc.).
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
    }

    /// Path the main app writes the active-bake snapshot to, and the
    /// widget extension reads from.
    static var widgetSnapshotURL: URL? {
        url?.appendingPathComponent("widget-snapshot.json", isDirectory: false)
    }

    /// Encode + atomically write the snapshot. Silent no-op when the App
    /// Group is unavailable — widgets just won't update; main app continues.
    static func writeWidgetSnapshot(_ snapshot: WidgetSnapshot) {
        guard let url = widgetSnapshotURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    /// Decode the snapshot if present. Used by the widget TimelineProvider.
    static func readWidgetSnapshot() -> WidgetSnapshot? {
        guard let url = widgetSnapshotURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}
