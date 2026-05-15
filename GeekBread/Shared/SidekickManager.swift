import Foundation
import CoreBluetooth
import os.log

// Stage 25 — Sourdough Sidekick BLE integration scaffolding.
//
// The Sourdough Sidekick is a smart starter jar built by FirstBuild that
// reports starter temperature and rise height over Bluetooth LE. The full
// integration is blocked on FirstBuild publishing their GATT protocol
// (service + characteristic UUIDs, byte layout for readings); this manager
// is the scaffolding we can ship today so that:
//
//   1. The CoreBluetooth permission gets requested and stored at app
//      install rather than the first time a baker tries to pair, which
//      would surprise them mid-cook.
//   2. The Settings → Pair flow can scan for nearby advertisers by name
//      and confirm that the user's device + jar can see each other.
//   3. When the protocol drops, the only wiring that needs updating is
//      the connect / subscribe / decode block — discovery and state plumbing
//      are already in place.
//
// Once the protocol is published, replace `nameFilter` with a service UUID
// in `central.scanForPeripherals(withServices:)` for an order-of-magnitude
// power win, then implement CBPeripheralDelegate connect/read/notify.

@MainActor
final class SidekickManager: NSObject, ObservableObject {

    static let shared = SidekickManager()

    enum Phase: Equatable {
        /// No scan in flight; idle.
        case idle
        /// Awaiting `CBCentralManager.state` transition before we can
        /// start scanning. The first instantiation always lands here.
        case warmingUp
        /// `CBCentralManager` is powered on and the scan is running.
        case scanning
        /// Scan stopped after the window expired without finding any
        /// advertiser matching the Sidekick name.
        case notFound
        /// Discovered a peripheral whose advertised name matches.
        /// `name` and `identifier` come straight from CoreBluetooth.
        case discovered(name: String, identifier: UUID)
        /// User has acknowledged the discovered jar — we record `paired`
        /// in AppState. We don't yet hold an open GATT connection; that
        /// arrives with the protocol.
        case paired(name: String, identifier: UUID)
        /// CoreBluetooth reported a permission or power problem we
        /// can't recover from without user action (Settings → Bluetooth).
        case unavailable(reason: String)
    }

    @Published private(set) var phase: Phase = .idle

    /// How long the scan runs before declaring `.notFound`. Long enough
    /// to catch a jar whose advertisement interval is the typical 1s,
    /// short enough that we don't burn the radio when nothing is around.
    private let scanWindow: TimeInterval = 8

    /// The advertised name FirstBuild ships on the Sidekick. We match by
    /// prefix so firmware revisions that append a serial ("Sourdough
    /// Sidekick 0421") still resolve. Verified against the public
    /// FirstBuild product photos and the Indiegogo-era app screenshots;
    /// if the production firmware ships a different prefix we'll need a
    /// `Settings → Advanced → Device name` override.
    private let namePrefix = "Sourdough Sidekick"

    private var central: CBCentralManager?
    private var scanTimeoutTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.geekbread.app",
                              category: "sidekick")

    private override init() { super.init() }

    // MARK: - Public API

    /// Coarse availability check the Settings card uses for layout. True
    /// only when CoreBluetooth thinks BLE is usable on this device (i.e.
    /// not airplane mode, hardware present). We intentionally do NOT
    /// instantiate the central here — that would prompt the user for
    /// Bluetooth permission on the Settings *open*, not on the Pair tap.
    var isBluetoothLikelyAvailable: Bool {
        // CBManager.authorization is a static class property — readable
        // before any central instantiation. `.notDetermined` is fine
        // (user hasn't been asked yet); `.allowedAlways` is fine.
        // `.denied` and `.restricted` are dead-ends for our flow.
        let auth = CBManager.authorization
        return auth == .notDetermined || auth == .allowedAlways
    }

    /// Start the discovery flow. Idempotent — calling while a scan is
    /// already running is a no-op. The first call instantiates the
    /// `CBCentralManager`, which is what triggers the OS permission
    /// prompt; we delay creation until this method runs so the prompt
    /// only appears on an explicit user gesture.
    func beginPairing() {
        switch phase {
        case .scanning, .warmingUp: return
        default: break
        }
        if central == nil {
            // `delegate` fires `centralManagerDidUpdateState` once
            // CoreBluetooth resolves power + authorization, which is
            // where the actual `scanForPeripherals` call lives.
            central = CBCentralManager(delegate: self, queue: .main, options: nil)
        }
        phase = .warmingUp

        // If the central is already powered on (re-pairing after the
        // first time), `centralManagerDidUpdateState` won't fire again,
        // so kick the scan directly.
        if let central, central.state == .poweredOn {
            startScan()
        }
    }

    /// Tell the manager the user confirmed the discovered jar. Real
    /// pairing (GATT connect, peripheral retention) lands with the
    /// protocol; for now we flip the AppState flag and surface the
    /// `.paired` phase so the Settings UI updates.
    func acknowledgePairing(state: AppState) {
        guard case .discovered(let name, let id) = phase else { return }
        state.setSidekickPaired(true)
        phase = .paired(name: name, identifier: id)
        central?.stopScan()
        scanTimeoutTask?.cancel()
    }

    /// Cancel any in-flight scan and reset to `.idle`. Safe to call from
    /// any phase.
    func cancel() {
        scanTimeoutTask?.cancel()
        central?.stopScan()
        phase = .idle
    }

    /// Forget the paired jar — flips AppState.sidekickPaired to false and
    /// returns the manager to `.idle`. We don't yet have an active GATT
    /// connection to tear down, so this is just bookkeeping.
    func forget(state: AppState) {
        state.setSidekickPaired(false)
        phase = .idle
    }

    // MARK: - Scan

    private func startScan() {
        guard let central, central.state == .poweredOn else { return }
        phase = .scanning
        // `withServices: nil` is the broad scan — costlier on power, but
        // we don't know the FirstBuild service UUID yet. The published
        // protocol will let us swap to `withServices: [knownUUID]` for
        // a major battery improvement.
        central.scanForPeripherals(withServices: nil, options: nil)
        scanTimeoutTask?.cancel()
        scanTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(8 * 1_000_000_000))
            guard let self else { return }
            if case .scanning = self.phase {
                self.central?.stopScan()
                self.phase = .notFound
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension SidekickManager: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // Hop to the main actor to mutate `phase` / talk to AppState.
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                self.log.info("CoreBluetooth powered on")
                if case .warmingUp = self.phase {
                    self.startScan()
                }
            case .poweredOff:
                self.phase = .unavailable(reason: "Bluetooth is off. Turn it on in Control Center to pair.")
            case .unauthorized:
                self.phase = .unavailable(reason: "Bluetooth permission was denied. Enable it in Settings → GeekBread.")
            case .unsupported:
                self.phase = .unavailable(reason: "This iPad doesn't support Bluetooth LE.")
            case .resetting:
                self.phase = .unavailable(reason: "Bluetooth is resetting — try again in a moment.")
            case .unknown:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                     didDiscover peripheral: CBPeripheral,
                                     advertisementData: [String: Any],
                                     rssi RSSI: NSNumber) {
        // Advertisements are firehose — match by name early to keep
        // this delegate cheap. Both the GAP local name and the
        // advertisement's `kCBAdvDataLocalName` are checked because some
        // peripherals only populate the latter.
        let advertisedName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        let prefix = namePrefix
        guard advertisedName.hasPrefix(prefix) else { return }
        Task { @MainActor in
            // Only the first discovery within a scan window flips state
            // — once `.discovered`, we stop the scan to save power and
            // wait for the user to acknowledge.
            if case .scanning = self.phase {
                self.central?.stopScan()
                self.scanTimeoutTask?.cancel()
                self.phase = .discovered(name: advertisedName,
                                          identifier: peripheral.identifier)
            }
        }
    }
}
