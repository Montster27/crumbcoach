import Foundation
import MetricKit
import os.log

// Local-only crash + diagnostic collection via MetricKit. Subscribing to
// `MXMetricManager` lets us receive the same daily payloads Apple's diagnostic
// pipeline produces (crashes, hangs, disk-write outliers). We keep them on
// disk in `<App Support>/Crumbcoach/telemetry/` so the user can share them
// via the Settings "Send diagnostic report" path if asked.
//
// Privacy posture:
//   - Nothing is uploaded automatically. Without a backend in v1, every
//     payload sits on the user's iPad until they explicitly share it.
//   - Apple's "Share with App Developers" toggle (iOS Settings → Privacy →
//     Analytics & Improvements) is the parallel automatic path; App Store
//     Connect surfaces aggregated crash counts from it without any code
//     from us. The Settings copy makes this distinction explicit.
//   - When the user toggles telemetry off, we unsubscribe + delete every
//     stored payload. There's no lingering local data we can't justify.
//
// MetricKit delivers at most once per 24 hours, so payloads are sparse;
// they're a debugging aid, not a real-time monitor.

final class TelemetryManager: NSObject {

    static let shared = TelemetryManager()

    private let log = Logger(subsystem: "com.crumbcoach.app", category: "telemetry")
    private let metricManager = MXMetricManager.shared
    private let storageDirectory: URL
    private var isSubscribed = false

    private override init() {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory,
                                 in: .userDomainMask,
                                 appropriateFor: nil,
                                 create: true)) ?? fm.temporaryDirectory
        let dir = base
            .appendingPathComponent("Crumbcoach", isDirectory: true)
            .appendingPathComponent("telemetry", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        self.storageDirectory = dir
        super.init()
    }

    // MARK: Subscription lifecycle

    /// Mirror the user's Settings toggle. Idempotent — calling with the same
    /// value twice does nothing surprising. When disabling, we also delete
    /// the payload archive so toggling off is a real reset, not just a pause.
    func setEnabled(_ enabled: Bool) {
        if enabled, !isSubscribed {
            metricManager.add(self)
            isSubscribed = true
            log.info("Telemetry subscribed (MetricKit)")
        } else if !enabled, isSubscribed {
            metricManager.remove(self)
            isSubscribed = false
            log.info("Telemetry unsubscribed (MetricKit)")
            deleteAllStoredPayloads()
        }
    }

    // MARK: Stored payloads

    /// Filenames of every JSON payload currently on disk, newest first.
    func storedPayloadFiles() -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: storageDirectory,
                                                         includingPropertiesForKeys: [.contentModificationDateKey],
                                                         options: [.skipsHiddenFiles]) else {
            return []
        }
        return entries
            .filter { $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                let lDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lDate > rDate
            }
    }

    /// One concatenated text blob suitable for sharing via the iOS share
    /// sheet. Nil if the user has opted out or no payloads have arrived yet.
    func diagnosticReportText() -> String? {
        let files = storedPayloadFiles()
        guard !files.isEmpty else { return nil }
        let header = "CrumbCoach diagnostic report\nGenerated \(ISO8601DateFormatter().string(from: Date()))\nPayloads: \(files.count)\n\n"
        let body = files.compactMap { url -> String? in
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else { return nil }
            return "--- \(url.lastPathComponent) ---\n\(text)\n"
        }.joined(separator: "\n")
        return header + body
    }

    private func deleteAllStoredPayloads() {
        let fm = FileManager.default
        for file in storedPayloadFiles() {
            try? fm.removeItem(at: file)
        }
    }

    private func write(_ data: Data, kind: String) {
        let timestamp = Int(Date().timeIntervalSince1970)
        let url = storageDirectory.appendingPathComponent("\(kind)-\(timestamp)-\(UUID().uuidString.prefix(8)).json")
        try? data.write(to: url, options: [.atomic])
    }
}

extension TelemetryManager: MXMetricManagerSubscriber {

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            write(payload.jsonRepresentation(), kind: "metric")
            log.info("Received MXMetricPayload (\(payload.jsonRepresentation().count, privacy: .public) bytes)")
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            write(payload.jsonRepresentation(), kind: "diagnostic")
            // Crash + hang diagnostics are the high-value signal. Log a
            // count rather than the body so the system log stays readable.
            let crashCount = payload.crashDiagnostics?.count ?? 0
            let hangCount = payload.hangDiagnostics?.count ?? 0
            log.info("Received MXDiagnosticPayload (crashes: \(crashCount, privacy: .public), hangs: \(hangCount, privacy: .public))")
        }
    }
}
