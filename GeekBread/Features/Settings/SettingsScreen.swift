import SwiftUI
import UIKit

// Settings — name, notifications status, demo / start-over actions, about.
// Intentionally light: this is not where we hide deep configuration. Keep it
// scannable so a baker can find their own name and the reset button without
// hunting.

struct SettingsScreen: View {
    var state: AppState
    @ObservedObject private var cloudSync = CloudSyncManager.shared
    @ObservedObject private var sidekick = SidekickManager.shared
    @State private var nameDraft: String = ""
    @State private var showLoadDemoConfirm: Bool = false
    @State private var showStartOverConfirm: Bool = false
    @State private var diagnosticShareItems: [Any]? = nil
    /// Mirrors `RemoteAIClient.isConfigured` so the toggle row updates
    /// the instant the user saves or removes a key.
    @State private var cloudAIKeyConfigured: Bool = RemoteAIClient.isConfigured
    /// Pending text in the secure entry field. Cleared after Save.
    @State private var cloudAIKeyDraft: String = ""
    @State private var cloudAIKeySaveError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            profileCard
            kitchenCard
            recipeImportCard
            cloudAICard
            sidekickCard
            notificationsCard
            cloudSyncCard
            telemetryCard
            dataCard
            aboutCard
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 720, alignment: .leading)
        .onAppear { nameDraft = state.userName }
        .alert("Replace your data with the demo state?",
                isPresented: $showLoadDemoConfirm) {
            Button("Load demo", role: .destructive) { state.loadDemoData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This swaps your journal, active bake, and starters for the Marisol-kitchen demo so you can explore the full app. Your name stays.")
        }
        .alert("Start over?", isPresented: $showStartOverConfirm) {
            Button("Start over", role: .destructive) { state.startOver() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Clears your journal and any active bake, and sends you back through onboarding. The recipe library is preserved.")
        }
    }

    // MARK: Profile

    private var profileCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                Kicker("Profile")
                Text("Your name")
                    .font(Typography.ui(13, weight: .medium))
                    .foregroundStyle(Theme.slate700)
                HStack(spacing: 10) {
                    TextField("Baker", text: $nameDraft)
                        .font(Typography.display(18, weight: .medium))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(Color.white,
                                     in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Theme.border1, lineWidth: 1)
                        )
                    Button("Save") {
                        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        state.setUserName(trimmed.isEmpty ? "Baker" : trimmed)
                    }
                    .ccPrimary(compact: true)
                    .disabled(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines) == state.userName)
                }
                Text("Used to greet you on the home screen.")
                    .font(Typography.ui(11.5))
                    .foregroundStyle(Theme.slate500)
            }
        }
    }

    // MARK: Kitchen

    private var kitchenCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                Kicker("Kitchen")
                unitsRow
                SoftDivider()
                tempSourceRow
            }
        }
    }

    private var unitsRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Weight units")
                    .font(Typography.ui(14, weight: .semibold))
                    .foregroundStyle(Theme.slate900)
                Text("Recipes are stored in grams; oz converts on display + edit.")
                    .font(Typography.ui(12))
                    .foregroundStyle(Theme.slate600)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Picker("Weight units",
                   selection: Binding(
                        get: { state.units },
                        set: { state.setUnits($0) }
                   )) {
                Text("Grams").tag(Units.grams)
                Text("Ounces").tag(Units.ounces)
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .labelsHidden()
        }
    }

    private var tempSourceRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Kitchen temperature source")
                    .font(Typography.ui(14, weight: .semibold))
                    .foregroundStyle(Theme.slate900)
                Text(state.kitchenTempSource == .homeKit
                     ? "HomeKit pairing arrives in a future update — the Scheduler still uses the slider for now."
                     : "Slide the Scheduler's kitchen temperature manually each bake.")
                    .font(Typography.ui(12))
                    .foregroundStyle(Theme.slate600)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Picker("Kitchen temperature source",
                   selection: Binding(
                        get: { state.kitchenTempSource },
                        set: { state.setKitchenTempSource($0) }
                   )) {
                Text("Manual").tag(KitchenTempSource.manual)
                Text("HomeKit").tag(KitchenTempSource.homeKit)
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .labelsHidden()
        }
    }

    // MARK: Recipe import (Stage 17.5b)

    /// AI assist toggle for the recipe importer. Hidden when the device
    /// can't run Apple Foundation Models — older iPads, non-Apple-Silicon
    /// iPads, anything pre-iOS 26 — so the toggle never claims a feature
    /// that won't fire. Off by default; opt-in only.
    @ViewBuilder
    private var recipeImportCard: some View {
        if AIRecipeAssist.isAvailable {
            SurfaceCard {
                VStack(alignment: .leading, spacing: 12) {
                    Kicker("Recipe import")
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Use Apple Intelligence to fill recipe gaps")
                                .font(Typography.ui(14, weight: .semibold))
                                .foregroundStyle(Theme.slate900)
                            Text("When the importer can't read a weight or a duration from a recipe URL, on-device Apple Intelligence estimates one. Estimates are flagged so you can double-check before baking.")
                                .font(Typography.ui(12))
                                .foregroundStyle(Theme.slate600)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Toggle("",
                                isOn: Binding(
                                    get: { state.aiAssistEnabled },
                                    set: { state.setAIAssistEnabled($0) }
                                ))
                            .labelsHidden()
                            .tint(Theme.primary)
                    }
                }
            }
        }
    }

    // MARK: Cloud AI (Stage 24 / haiku.md)

    /// Single toggle that gates every Cloud AI surface (crumb diagnosis,
    /// starter health, recipe-import structural pass). The user supplies
    /// their own Anthropic API key — BYOK is the v1 strategy from
    /// haiku.md "Cross-cutting decisions". Key lives in Keychain; this
    /// card never displays it back.
    private var cloudAICard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Kicker("Cloud AI")
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Use Claude for crumb diagnosis & recipe cleanup")
                            .font(Typography.ui(14, weight: .semibold))
                            .foregroundStyle(Theme.slate900)
                        Text("Sends a crumb / starter photo + bake context, or a recipe page's structure, to Anthropic Claude (Haiku). Your API key, your bill. Photos and text leave this iPad only when you act on a Cloud AI feature.")
                            .font(Typography.ui(12))
                            .foregroundStyle(Theme.slate600)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("",
                            isOn: Binding(
                                get: { state.cloudAIEnabled },
                                set: { state.setCloudAIEnabled($0) }
                            ))
                        .labelsHidden()
                        .tint(Theme.primary)
                        .disabled(!cloudAIKeyConfigured)
                }
                SoftDivider()
                cloudAIKeyRow
            }
        }
    }

    @ViewBuilder
    private var cloudAIKeyRow: some View {
        if cloudAIKeyConfigured {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Anthropic API key saved")
                        .font(Typography.ui(13.5, weight: .medium))
                        .foregroundStyle(Theme.slate900)
                    Text("Stored on this iPad's Keychain only. Remove it to disable Cloud AI on this device.")
                        .font(Typography.ui(11.5))
                        .foregroundStyle(Theme.slate500)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(role: .destructive) {
                    RemoteAIClient.clearAPIKey()
                    cloudAIKeyConfigured = false
                    state.setCloudAIEnabled(false)
                } label: {
                    Label("Remove key", systemImage: "trash")
                }
                .ccSecondary(compact: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Paste your Anthropic API key")
                    .font(Typography.ui(13, weight: .medium))
                    .foregroundStyle(Theme.slate700)
                HStack(spacing: 10) {
                    SecureField("sk-ant-…", text: $cloudAIKeyDraft)
                        .font(Typography.mono(13))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(Color.white,
                                     in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Theme.border1, lineWidth: 1)
                        )
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Save") {
                        let trimmed = cloudAIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if RemoteAIClient.setAPIKey(trimmed) {
                            cloudAIKeyConfigured = !trimmed.isEmpty
                            cloudAIKeyDraft = ""
                            cloudAIKeySaveError = nil
                        } else {
                            cloudAIKeySaveError = "Couldn't write to Keychain. Try again."
                        }
                    }
                    .ccPrimary(compact: true)
                    .disabled(cloudAIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let err = cloudAIKeySaveError {
                    Text(err)
                        .font(Typography.ui(11.5))
                        .foregroundStyle(Theme.warm700)
                }
                Text("Get a key at console.anthropic.com → Settings → API keys. We never see or store it ourselves.")
                    .font(Typography.ui(11.5))
                    .foregroundStyle(Theme.slate500)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Sidekick (Stage 25)

    /// Sourdough Sidekick pairing card. Discovery scans the BLE airspace
    /// for an advertiser matching the Sidekick name; live readings need
    /// the FirstBuild protocol that hasn't been published yet, so the
    /// card is explicit that "Paired" means "we can see your jar" rather
    /// than "we're reading from it".
    private var sidekickCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Kicker("Sourdough Sidekick")
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sidekickHeadline)
                            .font(Typography.ui(14, weight: .semibold))
                            .foregroundStyle(Theme.slate900)
                        Text(sidekickDetail)
                            .font(Typography.ui(12))
                            .foregroundStyle(Theme.slate600)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    sidekickPrimaryButton
                }
                if case .discovered(let name, _) = sidekick.phase {
                    SoftDivider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                                .font(Typography.ui(13.5, weight: .medium))
                                .foregroundStyle(Theme.slate900)
                            Text("Tap “Use this jar” to remember it. Live readings light up once FirstBuild publishes the Sidekick protocol.")
                                .font(Typography.ui(11.5))
                                .foregroundStyle(Theme.slate500)
                        }
                        Spacer()
                        Button("Use this jar") {
                            sidekick.acknowledgePairing(state: state)
                        }
                        .ccPrimary(compact: true)
                    }
                }
                if state.sidekickPaired {
                    SoftDivider()
                    HStack {
                        Text("Once FirstBuild publishes the Sidekick BLE protocol, live temperature + rise readings will flow into the Starter and Active Bake screens automatically.")
                            .font(Typography.ui(11.5))
                            .foregroundStyle(Theme.slate500)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Forget") {
                            sidekick.forget(state: state)
                        }
                        .ccSecondary(compact: true)
                    }
                }
            }
        }
    }

    private var sidekickHeadline: String {
        if state.sidekickPaired {
            return "Sidekick paired"
        }
        switch sidekick.phase {
        case .warmingUp, .scanning:
            return "Looking for your Sidekick"
        case .discovered:
            return "Found a Sidekick nearby"
        case .notFound:
            return "No Sidekick found"
        case .unavailable:
            return "Bluetooth unavailable"
        case .paired:
            return "Sidekick paired"
        case .idle:
            return "Pair your Sourdough Sidekick"
        }
    }

    private var sidekickDetail: String {
        if state.sidekickPaired, case .paired(let name, _) = sidekick.phase {
            return "Pairing remembered for \(name). Live readings light up in a future update."
        }
        if state.sidekickPaired {
            return "Pairing remembered. Tap “Rediscover” to confirm the jar is in range again, or “Forget” to clear."
        }
        switch sidekick.phase {
        case .warmingUp:    return "Asking iPadOS for Bluetooth permission…"
        case .scanning:     return "Scanning the room for ~8 seconds. Make sure the jar is on and within a few feet."
        case .discovered:   return "Confirm this is your jar so we can light it up once the BLE protocol ships."
        case .notFound:     return "Couldn't see a jar advertising. Check that the Sidekick is on and re-try the scan."
        case .unavailable(let reason): return reason
        case .paired:       return "Pairing remembered."
        case .idle:
            return "Discovery only — live starter temperature + rise readings arrive once FirstBuild publishes the Sidekick BLE protocol."
        }
    }

    @ViewBuilder
    private var sidekickPrimaryButton: some View {
        if state.sidekickPaired {
            switch sidekick.phase {
            case .warmingUp, .scanning:
                Button("Cancel") { sidekick.cancel() }
                    .ccSecondary(compact: true)
            default:
                Button("Rediscover") { sidekick.beginPairing() }
                    .ccSecondary(compact: true)
            }
        } else {
            switch sidekick.phase {
            case .warmingUp, .scanning:
                Button("Cancel") { sidekick.cancel() }
                    .ccSecondary(compact: true)
            case .unavailable:
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Open Settings", systemImage: "arrow.up.right.square")
                }
                .ccSecondary(compact: true)
            case .discovered:
                Button("Restart scan") { sidekick.beginPairing() }
                    .ccSecondary(compact: true)
            default:
                Button("Pair") { sidekick.beginPairing() }
                    .ccPrimary(compact: true)
                    .disabled(!sidekick.isBluetoothLikelyAvailable)
            }
        }
    }

    // MARK: Notifications

    private var notificationsCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Kicker("Notifications")
                HStack(spacing: 10) {
                    StatusPill(kind: pillKind, text: pillText, dot: true)
                    Spacer()
                    if state.notificationAuthStatus == .denied {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Open Settings", systemImage: "arrow.up.right.square")
                        }
                        .ccSecondary(compact: true)
                    }
                }
                Text("Bake reminders fire at action points — folds, shape, retard end, bake start, bake out. Set per-bake on the Scheduler.")
                    .font(Typography.ui(12))
                    .foregroundStyle(Theme.slate600)
            }
        }
    }

    private var pillKind: PillKind {
        switch state.notificationAuthStatus {
        case .authorized, .provisional, .ephemeral: return .good
        case .denied: return .bad
        case .notDetermined: return .neutral
        @unknown default: return .neutral
        }
    }

    private var pillText: String {
        switch state.notificationAuthStatus {
        case .authorized: return "On"
        case .provisional: return "Quiet"
        case .ephemeral: return "App Clip"
        case .denied: return "Off"
        case .notDetermined: return "Not asked yet"
        @unknown default: return "Unknown"
        }
    }

    // MARK: Telemetry

    private var telemetryCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Kicker("Diagnostics")
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Collect crash diagnostics on this iPad")
                            .font(Typography.ui(14, weight: .semibold))
                            .foregroundStyle(Theme.slate900)
                        Text("Uses Apple's MetricKit to record crashes and hangs locally. Nothing is uploaded automatically — you choose when (or whether) to share a report.")
                            .font(Typography.ui(12))
                            .foregroundStyle(Theme.slate600)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("",
                            isOn: Binding(
                                get: { state.telemetryEnabled },
                                set: { state.setTelemetryEnabled($0) }
                            ))
                        .labelsHidden()
                        .tint(Theme.primary)
                }

                if state.telemetryEnabled {
                    SoftDivider()
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Send a diagnostic report")
                                .font(Typography.ui(13.5, weight: .medium))
                                .foregroundStyle(Theme.slate900)
                            Text(diagnosticDetail)
                                .font(Typography.ui(11.5))
                                .foregroundStyle(Theme.slate500)
                        }
                        Spacer()
                        Button {
                            if let body = TelemetryManager.shared.diagnosticReportText() {
                                diagnosticShareItems = [body]
                            }
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .ccSecondary(compact: true)
                        .disabled(TelemetryManager.shared.storedPayloadFiles().isEmpty)
                    }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { diagnosticShareItems != nil },
            set: { if !$0 { diagnosticShareItems = nil } }
        )) {
            if let items = diagnosticShareItems {
                ShareActivitySheet(items: items)
            }
        }
    }

    private var diagnosticDetail: String {
        let count = TelemetryManager.shared.storedPayloadFiles().count
        switch count {
        case 0:  return "No reports yet. MetricKit posts new payloads at most once a day."
        case 1:  return "1 report ready to share."
        default: return "\(count) reports ready to share."
        }
    }

    // MARK: Cloud sync
    //
    // Recipes-only iCloud sync (May 2026): the recipe library syncs
    // automatically across the user's iPhone, iPad, and Mac whenever
    // iCloud is signed in. The card is informational — no toggle —
    // with a "Sync now" button for manual reconciliation. Other state
    // (starters, journal, active bake, settings) intentionally stays
    // device-local.

    @ViewBuilder
    private var cloudSyncCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                Kicker("iCloud sync")
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Recipes sync across your devices")
                            .font(Typography.ui(14, weight: .semibold))
                            .foregroundStyle(Theme.slate900)
                        Text(cloudSyncDescription)
                            .font(Typography.ui(12))
                            .foregroundStyle(Theme.slate600)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                if cloudSync.isAvailable {
                    SoftDivider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sync now")
                                .font(Typography.ui(13.5, weight: .medium))
                                .foregroundStyle(Theme.slate900)
                            Text(cloudSyncStatusLine)
                                .font(Typography.ui(11.5))
                                .foregroundStyle(Theme.slate500)
                        }
                        Spacer()
                        Button {
                            Task { await state.syncRecipesWithCloud() }
                        } label: {
                            Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .ccSecondary(compact: true)
                        .disabled(cloudSync.status == .syncing)
                    }
                }
            }
        }
    }

    private var cloudSyncDescription: String {
        if !cloudSync.isAvailable {
            return "Sign in to iCloud (Settings → Apple ID → iCloud) to enable recipe sync. Other data — bakes, journal, starters — stays on this device."
        }
        return "Your recipe library is mirrored to iCloud and pulled in on every other device signed in to the same Apple ID. Other data — bakes, journal, starters — stays on this device. Photos stay on each device too."
    }

    private var cloudSyncStatusLine: String {
        switch cloudSync.status {
        case .disabled:               return "Ready to sync"
        case .unavailable:            return "iCloud not available"
        case .ready:                  return "Ready to sync"
        case .syncing:                return "Syncing…"
        case .syncedAt(let date):
            let f = DateFormatter()
            f.dateFormat = "MMM d, h:mm a"
            return "Last synced \(f.string(from: date))"
        case .failed(let msg):        return "Last sync failed: \(msg)"
        }
    }

    // MARK: Data

    private var dataCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                Kicker("Data")
                dataRow(
                    title: "Load demo data",
                    detail: "See the app with Marisol's full kitchen — a mid-bulk bake, journal entries, two starters.",
                    icon: .sparkle,
                    action: { showLoadDemoConfirm = true }
                )
                SoftDivider()
                dataRow(
                    title: "Start over",
                    detail: "Clear your journal and active bake; keep the recipe library; re-run onboarding.",
                    icon: .trash,
                    destructive: true,
                    action: { showStartOverConfirm = true }
                )
            }
        }
    }

    private func dataRow(title: String, detail: String, icon: CCIcon,
                         destructive: Bool = false,
                         action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(destructive ? Theme.warm50 : Theme.primaryTint)
                    .frame(width: 38, height: 38)
                CCIconView(icon: icon, size: 16,
                            color: destructive ? Theme.warm700 : Theme.primary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typography.ui(14, weight: .semibold))
                    .foregroundStyle(Theme.slate900)
                Text(detail)
                    .font(Typography.ui(12))
                    .foregroundStyle(Theme.slate600)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(destructive ? "Reset" : "Run", action: action)
                .buttonStyle(CCButtonStyle(variant: destructive ? .secondary : .primary,
                                            compact: true))
        }
    }

    // MARK: About

    private var aboutCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                Kicker("About")
                aboutRow("Version", versionString)
                aboutRow("Build", buildString)
                aboutRow("Recipes", "\(state.recipes.count)")
                aboutRow("Journal entries", "\(state.journal.count)")
                aboutRow("Starters", "\(state.starters.count)")
            }
        }
    }

    private func aboutRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(Typography.ui(13))
                .foregroundStyle(Theme.slate700)
            Spacer()
            Text(value)
                .font(Typography.mono(13, weight: .semibold))
                .foregroundStyle(Theme.slate900)
        }
    }

    private var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
    private var buildString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}

#Preview("Settings") {
    SettingsScreen(state: AppState(persistence: PersistenceController(filename: "preview-settings.json")))
        .padding()
        .background(Theme.surface1)
}
