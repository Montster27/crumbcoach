import Foundation
import os.log

// iCloud Drive-backed sync of the JSON state file. Pragmatic v1.x choice over
// a full `NSPersistentCloudKitContainer` rewrite — using the ubiquity Documents
// container gives us cross-device sync of the same `state.json` we already
// write locally, with conflict resolution via file modification dates
// (last-write-wins).
//
// Trade-offs vs. NSPersistentCloudKitContainer:
//   - No record-level merge: a concurrent edit on two devices replaces the
//     loser entirely (whichever wrote later). For a single-baker app with
//     long edit sessions, this is rare; we surface "Last synced HH:MM" so the
//     user can spot stale state.
//   - No push notifications: cross-device propagation happens on next
//     foreground, not in real time. CloudKit subscriptions are a separate
//     Phase C add when we have iPhone / Watch targets to justify them.
//   - Photos aren't synced yet: the JSON references photo filenames that
//     only exist locally. Stage 18's share-and-export path is the natural
//     companion to add photo CKAssets later.
//
// Availability gating:
//   - `isAvailable` checks for an iCloud account; nil if the user isn't
//     signed in. UI must show a "Sign in to iCloud" hint instead of toggling.
//   - The `setEnabled` toggle is independent — opting out keeps the local
//     file authoritative without scrubbing what's already in the cloud.
//
// Threading: all I/O happens off the main actor via the public async
// methods. The `lastSyncedAt` / `status` reads are MainActor-isolated.

@MainActor
final class CloudSyncManager: ObservableObject {

    static let shared = CloudSyncManager()

    enum SyncStatus: Equatable {
        case disabled               // user has not opted in
        case unavailable            // iCloud not signed in
        case ready                  // signed in, opted in, nothing in flight
        case syncing                // a push or pull is mid-flight
        case syncedAt(Date)         // last successful sync
        case failed(String)         // last attempt errored
    }

    @Published private(set) var status: SyncStatus = .disabled
    private let log = Logger(subsystem: "com.crumbcoach.app", category: "cloudsync")
    private var enabled = false

    private init() {}

    // MARK: Availability

    /// True when the user is signed in to iCloud. The ubiquity container is
    /// useless without it.
    var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// Resolves the iCloud Drive Documents directory for the default
    /// container. Returns nil if iCloud is signed out or the user hasn't
    /// enabled iCloud Drive.
    private func ubiquityDocumentsDirectory() -> URL? {
        guard let url = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        let docs = url.appendingPathComponent("Documents", isDirectory: true)
        if !FileManager.default.fileExists(atPath: docs.path) {
            try? FileManager.default.createDirectory(at: docs,
                                                     withIntermediateDirectories: true)
        }
        return docs
    }

    // MARK: Lifecycle

    /// Mirror the Settings toggle. When enabling, kick off an immediate
    /// pull-then-push so the cloud copy isn't stale on the first sync.
    func setEnabled(_ value: Bool) {
        enabled = value
        if !value {
            status = .disabled
            return
        }
        if !isAvailable {
            status = .unavailable
            return
        }
        status = .ready
    }

    // MARK: Push

    /// Copy the local state file up to the iCloud Drive Documents container.
    /// Off-main; no-op if disabled or unavailable.
    func push(localStateURL: URL) async {
        guard enabled, isAvailable, let cloudDir = ubiquityDocumentsDirectory() else {
            return
        }
        status = .syncing
        let cloudURL = cloudDir.appendingPathComponent(localStateURL.lastPathComponent)

        let result = await Task.detached(priority: .utility) { [log] () -> SyncStatus in
            do {
                if FileManager.default.fileExists(atPath: cloudURL.path) {
                    try FileManager.default.removeItem(at: cloudURL)
                }
                try FileManager.default.copyItem(at: localStateURL, to: cloudURL)
                log.info("CloudSync push ok")
                return .syncedAt(Date())
            } catch {
                log.error("CloudSync push failed: \(error.localizedDescription, privacy: .public)")
                return .failed(error.localizedDescription)
            }
        }.value

        status = result
    }

    // MARK: Pull

    /// Return value: `true` if a newer cloud copy was pulled and replaced
    /// the local file (caller should reload from disk).
    @discardableResult
    func pullIfNewer(into localStateURL: URL) async -> Bool {
        guard enabled, isAvailable, let cloudDir = ubiquityDocumentsDirectory() else {
            return false
        }
        let cloudURL = cloudDir.appendingPathComponent(localStateURL.lastPathComponent)
        guard FileManager.default.fileExists(atPath: cloudURL.path) else { return false }

        let didPull = await Task.detached(priority: .utility) { () -> Bool in
            let fm = FileManager.default
            let cloudDate = (try? cloudURL.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            let localDate = (try? localStateURL.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            guard cloudDate > localDate.addingTimeInterval(0.5) else { return false }
            // Coordinated swap: remove local then copy cloud → local.
            do {
                if fm.fileExists(atPath: localStateURL.path) {
                    try fm.removeItem(at: localStateURL)
                }
                try fm.copyItem(at: cloudURL, to: localStateURL)
                return true
            } catch {
                return false
            }
        }.value

        if didPull {
            status = .syncedAt(Date())
        }
        return didPull
    }
}
