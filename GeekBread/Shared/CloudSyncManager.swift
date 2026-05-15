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
    private let log = Logger(subsystem: "com.geekbread.app", category: "cloudsync")
    private var enabled = false

    // MARK: Recipes-only sync constants
    //
    // Per the May 2026 "recipes sync only" decision, the recipe library is
    // synced as its own JSON file separate from the local state.json. Other
    // state (starters, journal, active bake, settings) stays device-local —
    // the legacy full-state sync API below is preserved for compatibility
    // but no longer called from AppState.
    static let recipesFilename = "recipes.json"
    private static let recipesLastSyncedKey = "geekbread.cloudsync.recipesLastSyncedMtime"

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// In-app serialization for push and pull. Each new call chains after
    /// the previous in-flight task so two near-simultaneous saves can't
    /// race on the cloud file's removeItem + copyItem. `NSFileCoordinator`
    /// (below) handles the cross-process race with the iCloud daemon; this
    /// chain handles the in-app one.
    private var pushTask: Task<Void, Never>?
    private var pullTask: Task<Bool, Never>?
    private var recipesPushTask: Task<Void, Never>?
    private var recipesPullTask: Task<[Recipe]?, Never>?

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

    /// Bring the published status into line with the system iCloud state
    /// for the always-on recipe sync flow. AppState calls this on launch
    /// and on scene-active so the Settings status line reflects whether
    /// iCloud is reachable, without round-tripping through a user toggle.
    func refreshAvailability() {
        if isAvailable {
            // Don't clobber a fresh `.syncedAt` / `.syncing` value — the
            // user wants to see the last sync time, not a generic "ready".
            switch status {
            case .ready, .disabled, .unavailable:
                status = .ready
            default:
                break
            }
        } else {
            status = .unavailable
        }
    }

    // MARK: Push

    /// Copy the local state file up to the iCloud Drive Documents
    /// container. Off-main; no-op if disabled or unavailable.
    ///
    /// Two safety layers stack here:
    ///   1. **In-app chain** via `pushTask`: each new push awaits the
    ///      prior in-flight one before running, so two saves spawned 0.5s
    ///      apart can't race their own `removeItem` + `copyItem` against
    ///      each other.
    ///   2. **`NSFileCoordinator`** wrapping the actual file work: Apple
    ///      requires coordinated access to ubiquity URLs so the iCloud
    ///      daemon doesn't return stale bytes mid-sync, and so simultaneous
    ///      writes from other processes serialize cleanly.
    func push(localStateURL: URL) async {
        guard enabled, isAvailable, let cloudDir = ubiquityDocumentsDirectory() else {
            return
        }
        status = .syncing
        let cloudURL = cloudDir.appendingPathComponent(localStateURL.lastPathComponent)
        let prior = pushTask
        let next = Task { [weak self] in
            // Wait for the predecessor so pushes serialize in arrival order.
            // Cancellation propagates harmlessly — `value` returns the
            // cancelled task's Void regardless.
            await prior?.value
            guard let self else { return }
            let result = await Self.performPush(
                localStateURL: localStateURL,
                cloudURL: cloudURL,
                log: self.log
            )
            await MainActor.run { self.status = result }
        }
        pushTask = next
        await next.value
    }

    private static func performPush(localStateURL: URL,
                                     cloudURL: URL,
                                     log: Logger) async -> SyncStatus {
        await Task.detached(priority: .utility) { () -> SyncStatus in
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordinationError: NSError?
            var outcome: SyncStatus = .failed("coordination did not run")
            coordinator.coordinate(writingItemAt: cloudURL,
                                    options: .forReplacing,
                                    error: &coordinationError) { writeURL in
                do {
                    let fm = FileManager.default
                    if fm.fileExists(atPath: writeURL.path) {
                        try fm.removeItem(at: writeURL)
                    }
                    try fm.copyItem(at: localStateURL, to: writeURL)
                    log.info("CloudSync push ok")
                    outcome = .syncedAt(Date())
                } catch {
                    log.error("CloudSync push failed: \(error.localizedDescription, privacy: .public)")
                    outcome = .failed(error.localizedDescription)
                }
            }
            if let coordinationError {
                log.error("CloudSync push coordination failed: \(coordinationError.localizedDescription, privacy: .public)")
                return .failed(coordinationError.localizedDescription)
            }
            return outcome
        }.value
    }

    // MARK: Pull

    /// Return value: `true` if a newer cloud copy was pulled and replaced
    /// the local file (caller should reload from disk). Like push, this is
    /// chained against any in-flight pull and wrapped in `NSFileCoordinator`
    /// for cross-process safety.
    @discardableResult
    func pullIfNewer(into localStateURL: URL) async -> Bool {
        guard enabled, isAvailable, let cloudDir = ubiquityDocumentsDirectory() else {
            return false
        }
        let cloudURL = cloudDir.appendingPathComponent(localStateURL.lastPathComponent)
        guard FileManager.default.fileExists(atPath: cloudURL.path) else { return false }

        let prior = pullTask
        let next = Task { [weak self] in
            _ = await prior?.value
            guard let self else { return false }
            let pulledMtime = await Self.performPull(
                localStateURL: localStateURL,
                cloudURL: cloudURL,
                log: self.log
            )
            if let mtime = pulledMtime {
                // Report the cloud file's authoring time, NOT now(). The
                // user's two iPads should see the same "last synced"
                // timestamp; otherwise they can't tell whether their
                // data is drifting.
                await MainActor.run { self.status = .syncedAt(mtime) }
                return true
            }
            return false
        }
        pullTask = next
        return await next.value
    }

    // MARK: Recipes-only push / pull
    //
    // Recipe sync runs unconditionally whenever iCloud is signed in — no
    // user opt-in toggle. The cloud carries the recipe array on its own
    // (`recipes.json`); local state.json continues to be the source of
    // truth on each device for everything else.
    //
    // Mtime-based last-write-wins: each device caches the cloud file's
    // mtime at the last successful sync in UserDefaults. Pull replaces
    // local recipes only when the cloud file is meaningfully newer than
    // the cached mtime, which prevents an idle device from re-importing
    // its own recently-pushed copy.

    /// Encode `recipes` and copy the resulting JSON up to iCloud Drive.
    /// No-op when iCloud is unavailable. Pushes are serialized through
    /// `recipesPushTask` so a flurry of edits doesn't race the file
    /// coordinator against itself.
    func pushRecipes(_ recipes: [Recipe]) async {
        guard isAvailable, let cloudDir = ubiquityDocumentsDirectory() else { return }
        let cloudURL = cloudDir.appendingPathComponent(Self.recipesFilename)

        let payload: Data
        do {
            payload = try encoder.encode(recipes)
        } catch {
            log.error("CloudSync recipe encode failed: \(error.localizedDescription, privacy: .public)")
            status = .failed(error.localizedDescription)
            return
        }

        status = .syncing
        let prior = recipesPushTask
        let next = Task { [weak self] in
            await prior?.value
            guard let self else { return }
            let result = await Self.performRecipesPush(
                payload: payload,
                cloudURL: cloudURL,
                log: self.log
            )
            await MainActor.run {
                if case .syncedAt(let mtime) = result {
                    UserDefaults.standard.set(mtime, forKey: Self.recipesLastSyncedKey)
                }
                self.status = result
            }
        }
        recipesPushTask = next
        await next.value
    }

    private static func performRecipesPush(payload: Data,
                                            cloudURL: URL,
                                            log: Logger) async -> SyncStatus {
        await Task.detached(priority: .utility) { () -> SyncStatus in
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordinationError: NSError?
            var outcome: SyncStatus = .failed("coordination did not run")
            coordinator.coordinate(writingItemAt: cloudURL,
                                    options: .forReplacing,
                                    error: &coordinationError) { writeURL in
                do {
                    try payload.write(to: writeURL, options: [.atomic])
                    let mtime = (try? writeURL.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate) ?? Date()
                    log.info("CloudSync recipes push ok")
                    outcome = .syncedAt(mtime)
                } catch {
                    log.error("CloudSync recipes push failed: \(error.localizedDescription, privacy: .public)")
                    outcome = .failed(error.localizedDescription)
                }
            }
            if let coordinationError {
                log.error("CloudSync recipes push coordination failed: \(coordinationError.localizedDescription, privacy: .public)")
                return .failed(coordinationError.localizedDescription)
            }
            return outcome
        }.value
    }

    /// Pull the cloud recipes file when it's newer than the device's
    /// cached mtime. Returns the decoded array on success, nil otherwise.
    /// Caller is responsible for merging into AppState — this method
    /// doesn't touch any other state.
    func pullRecipesIfNewer() async -> [Recipe]? {
        guard isAvailable, let cloudDir = ubiquityDocumentsDirectory() else { return nil }
        let cloudURL = cloudDir.appendingPathComponent(Self.recipesFilename)
        guard FileManager.default.fileExists(atPath: cloudURL.path) else { return nil }

        let cachedMtime = UserDefaults.standard.object(forKey: Self.recipesLastSyncedKey) as? Date
        let prior = recipesPullTask
        let next = Task { [weak self] in
            _ = await prior?.value
            guard let self else { return [Recipe]?.none }
            let (recipes, mtime) = await Self.performRecipesPull(
                cloudURL: cloudURL,
                cachedMtime: cachedMtime,
                decoder: self.decoder,
                log: self.log
            )
            if let mtime {
                await MainActor.run {
                    UserDefaults.standard.set(mtime, forKey: Self.recipesLastSyncedKey)
                    self.status = .syncedAt(mtime)
                }
            }
            return recipes
        }
        recipesPullTask = next
        return await next.value
    }

    private static func performRecipesPull(cloudURL: URL,
                                            cachedMtime: Date?,
                                            decoder: JSONDecoder,
                                            log: Logger) async -> ([Recipe]?, Date?) {
        await Task.detached(priority: .utility) { () -> ([Recipe]?, Date?) in
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordinationError: NSError?
            var decoded: [Recipe]?
            var pulledMtime: Date?
            coordinator.coordinate(readingItemAt: cloudURL,
                                    options: [],
                                    error: &coordinationError) { readURL in
                let cloudMtime = (try? readURL.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                // 0.5s slop guards against sub-second mtime jitter when our
                // own push timestamp round-trips back through the file system.
                let threshold = (cachedMtime ?? .distantPast).addingTimeInterval(0.5)
                guard cloudMtime > threshold else { return }
                do {
                    let data = try Data(contentsOf: readURL)
                    decoded = try decoder.decode([Recipe].self, from: data)
                    pulledMtime = cloudMtime
                } catch {
                    log.error("CloudSync recipes pull failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            if let coordinationError {
                log.error("CloudSync recipes pull coordination failed: \(coordinationError.localizedDescription, privacy: .public)")
            }
            return (decoded, pulledMtime)
        }.value
    }

    /// Returns the cloud file's mtime when a copy actually happened. Nil
    /// when the local file was already current or the coordinator hit an
    /// error.
    private static func performPull(localStateURL: URL,
                                     cloudURL: URL,
                                     log: Logger) async -> Date? {
        await Task.detached(priority: .utility) { () -> Date? in
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordinationError: NSError?
            var pulledMtime: Date?
            coordinator.coordinate(readingItemAt: cloudURL,
                                    options: [],
                                    error: &coordinationError) { readURL in
                let fm = FileManager.default
                let cloudDate = (try? readURL.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                let localDate = (try? localStateURL.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                // 0.5s slop because mtimes round-trip through the file
                // system with sub-second precision; we don't want clock
                // jitter to falsely flag the cloud as newer.
                guard cloudDate > localDate.addingTimeInterval(0.5) else { return }
                do {
                    if fm.fileExists(atPath: localStateURL.path) {
                        try fm.removeItem(at: localStateURL)
                    }
                    try fm.copyItem(at: readURL, to: localStateURL)
                    pulledMtime = cloudDate
                } catch {
                    log.error("CloudSync pull failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            if let coordinationError {
                log.error("CloudSync pull coordination failed: \(coordinationError.localizedDescription, privacy: .public)")
            }
            return pulledMtime
        }.value
    }
}
