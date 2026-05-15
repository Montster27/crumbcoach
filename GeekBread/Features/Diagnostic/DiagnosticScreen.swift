import SwiftUI

// Crumb comparison screen (Stage 24a). Real, on-device Vision feature-print
// match against the user's journal photos. Three states:
//   - idle:      no photo yet, show photo-guide tips
//   - analyzing: Vision computing prints for the current photo + journal
//   - result:    closest journal match + similarity %
//
// We deliberately *do not* claim to diagnose underproofing, predict bake
// outcomes, or train a model from feedback. We compare image features the
// user has already rated; everything else is the user's judgement.
// Stage 24 (the full vision-language model) is the long-term answer.

struct DiagnosticScreen: View {
    var state: AppState

    enum DiagState { case idle, analyzing, result }

    @State private var diagState: DiagState = .idle
    @State private var currentPhoto: String? = nil       // disk filename or bundled asset
    @State private var photoPickerOpen = false
    /// The closest journal entry by Vision feature-print distance, and the
    /// 0–100 similarity score derived from that distance. Nil when the
    /// journal has no comparable photos yet.
    @State private var match: MatchResult? = nil
    /// Stage 24 (haiku.md Tier 1.1) — Cloud AI diagnosis for the current
    /// photo, when the user has opted in and the model returned with
    /// confidence ≥ 0.7. Nil otherwise; the 24a similarity card remains
    /// the surfaced answer in that case.
    @State private var diagnosis: Diagnosis? = nil

    struct MatchResult {
        let entry: JournalEntry
        let similarity: Int
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            // LEFT: photo
            VStack(spacing: 20) {
                photoPanel
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            // RIGHT: panels
            VStack(spacing: 16) {
                switch diagState {
                case .idle:      idleSide
                case .analyzing: analyzingSide
                case .result:    resultSide
                }
            }
            .frame(width: 420)
        }
        .photoPicker(isPresented: $photoPickerOpen) { image in
            // Defer the analysis start until we have a real on-disk filename
            // — if persistence fails the global photo-error alert covers it.
            if let filename = state.persistence.savePhoto(image) {
                currentPhoto = filename
                startAnalysis()
            } else {
                state.photoErrorMessage = "Couldn't save that photo. Try again — your iPad may be low on storage."
            }
        }
        .onAppear {
            // Consume a photo handed off from another screen (Home's "Take
            // photo" button). One-shot — clear after consuming.
            if let pending = state.pendingDiagnosticPhoto {
                currentPhoto = pending
                state.pendingDiagnosticPhoto = nil
                startAnalysis()
            }
        }
    }

    // MARK: Photo panel

    private var photoPanel: some View {
        ZStack {
            BreadPhoto(assetName: currentPhoto, kind: .crumb, height: 480)

            VStack {
                HStack {
                    topLabel
                    Spacer()
                    if diagState == .result {
                        Button(action: { photoPickerOpen = true }) {
                            Label("New photo", systemImage: "camera")
                        }
                        .buttonStyle(BlurChip())
                    }
                }
                .padding(12)
                Spacer()

                // Privacy reassurance. Honest about whether the photo
                // stayed on-device (Vision similarity only) or was
                // sent to Anthropic Claude (Stage 24 diagnose pass).
                // We key off `diagnosis != nil` — only set when the
                // cloud call returned a usable result — so the badge
                // can't claim cloud ran when it didn't.
                if diagState == .result {
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: 0x86EFAC)).frame(width: 6, height: 6)
                        Text(diagnosis == nil
                             ? "On-device · photo never left this iPad"
                             : "Photo sent to Anthropic Claude · Settings → Cloud AI")
                            .font(Typography.ui(11)).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.7), in: Capsule())
                    .padding(12)
                }
            }

            if diagState == .idle { idleOverlay }
            if diagState == .analyzing { analyzingOverlay }
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .background(Theme.slate900, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.border1, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var topLabel: some View {
        let timestamp = CCFormat.clockTime.string(from: Date())
        return Text("Crumb shot · \(timestamp)")
            .font(Typography.ui(12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().fill(Color.black.opacity(0.45)).blendMode(.multiply))
    }

    private var idleOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
            VStack(spacing: 16) {
                Button(action: { photoPickerOpen = true }) {
                    Circle().fill(.white).frame(width: 88, height: 88)
                        .overlay(CCIconView(icon: .camera, size: 36, color: Theme.primary))
                        .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Take crumb photo")
                .accessibilityHint("Opens the camera or photo library to start a diagnostic")
                Text("Tap to analyze · or drop a photo")
                    .font(Typography.ui(14))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private var analyzingOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 16) {
                RingProgress(value: 0.65, size: 72, stroke: 5,
                              color: .white, trackColor: .white.opacity(0.2)) {
                    CCIconView(icon: .sparkle, size: 26, color: .white)
                }
                Text("Analyzing crumb structure…")
                    .font(Typography.ui(15, weight: .medium)).foregroundStyle(.white)
                Text(state.cloudAIEnabled
                     ? "Apple Vision + Anthropic Claude"
                     : "On-device vision model · No upload")
                    .font(Typography.ui(12)).foregroundStyle(.white.opacity(0.75))
                HStack(spacing: 6) {
                    ForEach(["Detecting cell distribution", "Comparing to bake #23", "Cross-referencing schedule"], id: \.self) { t in
                        Text(t)
                            .font(Typography.ui(10))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.12), in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
                    }
                }
            }
        }
    }

    // MARK: Side panels

    private var idleSide: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                Kicker("Photo guide")
                Text("Sliced loaf, flat on the cutting board.")
                    .font(Typography.display(22, weight: .medium))
                    .foregroundStyle(Theme.slate900)
                Text("Overhead light, neutral background. We'll compare your shot against your journal's photos and surface the closest match.")
                    .font(Typography.ui(13)).foregroundStyle(Theme.slate600)
                SoftDivider()
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(["Slice through the widest point",
                             "Avoid shadows from your phone",
                             "Include 1–2 cm of crust on top"], id: \.self) { t in
                        HStack(spacing: 10) {
                            CCIconView(icon: .check, size: 16, color: Theme.success600)
                            Text(t).font(Typography.ui(13)).foregroundStyle(Theme.slate700)
                        }
                    }
                }
            }
        }
    }

    private var analyzingSide: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 18) {
                Kicker("Comparing")
                Text("Finding the closest journal match…")
                    .font(Typography.display(22, weight: .medium))
                    .foregroundStyle(Theme.slate900)
                let steps = [
                    "Computing this photo's feature print",
                    "Loading your journal's photos",
                    "Comparing against past bakes",
                ]
                ForEach(steps, id: \.self) { step in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Theme.slate100).frame(width: 22, height: 22)
                            Circle().fill(Theme.slate400).frame(width: 6, height: 6)
                        }
                        Text(step).font(Typography.ui(13))
                            .foregroundStyle(Theme.slate700)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var resultSide: some View {
        // Stage 24 (haiku.md Tier 1.1) — when Cloud AI returned a
        // confident diagnosis, surface it ABOVE the 24a similarity
        // card. The similarity card stays as a verifier ("does this
        // crumb look like any of your past bakes?") rather than the
        // primary answer.
        if let diagnosis, diagnosis.isConfident {
            diagnosisCard(diagnosis)
        }
        if let match {
            matchResultCard(match)
            honestyCard
        } else {
            emptyJournalCard
        }
    }

    /// Stage 24 diagnosis card. Shown above the similarity match when
    /// Claude returned a high-confidence verdict. Layout mirrors
    /// `matchResultCard` so the two read as a coherent pair.
    private func diagnosisCard(_ d: Diagnosis) -> some View {
        SurfaceCard(padding: EdgeInsets()) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Kicker("Diagnosis · Claude Haiku", color: Theme.primary)
                        Spacer()
                        StatusPill(kind: pillKind(for: d.primaryLabel),
                                    text: "\(Int((d.confidence * 100).rounded()))% confidence")
                    }
                    Text(d.primaryLabel.displayLabel)
                        .font(Typography.display(24, weight: .medium))
                        .foregroundStyle(Theme.slate900)
                    Text(d.explanation)
                        .font(Typography.ui(13))
                        .foregroundStyle(Theme.slate700)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
                .background(
                    LinearGradient(colors: [Theme.primaryTint, .white],
                                    startPoint: .top, endPoint: .bottom)
                )
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.border1).frame(height: 1) }

                if !d.suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Kicker("Next bake")
                        ForEach(Array(d.suggestions.enumerated()), id: \.offset) { _, suggestion in
                            HStack(alignment: .top, spacing: 10) {
                                CCIconView(icon: .check, size: 14, color: Theme.primary)
                                Text(suggestion)
                                    .font(Typography.ui(12.5))
                                    .foregroundStyle(Theme.slate700)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                }
            }
        }
    }

    /// Pick a status pill kind from the diagnosis label. Negative
    /// labels (under/over) read as warning; openCrumb/even read as
    /// positive; the others stay informational.
    private func pillKind(for label: DiagnosisLabel) -> PillKind {
        switch label {
        case .even, .openCrumb:                                 return .good
        case .underproofed, .overproofed, .underbaked, .overferment: return .warn
        case .tightCrumb:                                       return .info
        case .unknown:                                          return .neutral
        }
    }

    /// Pull whatever bake context the diagnose call should see. Today
    /// that's the active bake when there is one — its recipe carries
    /// the hydration / bulk / retard / oven temp we want to ground
    /// the diagnosis in. Standalone diagnose calls (no active bake)
    /// pass an empty context; the model's prompt knows to do its best.
    private func makeBakeContext() -> BakeContext {
        guard let bake = state.activeBake,
              let recipe = state.recipe(bake.recipeId) else {
            return BakeContext()
        }
        let bakeStage = recipe.stages.first { $0.kind == .bake }
        let retardStage = recipe.stages.first { $0.kind == .coldRetard }
        let bulkStage = recipe.stages.first { $0.kind == .bulk || $0.kind == .bulkFold }
        return BakeContext(
            recipeTitle: recipe.title,
            breadType: recipe.breadType.rawValue,
            hydrationPct: recipe.hydrationPct,
            bulkMinutes: bulkStage?.durationMin,
            ambientTempC: bake.kitchenTempC,
            retardMinutes: retardStage?.durationMin,
            bakeTempC: bakeStage?.temperatureC,
            bakeMinutes: bakeStage?.durationMin
        )
    }

    /// Closest journal entry by Vision feature-print distance + a
    /// similarity percentage + a tap-into-the-journal CTA. The recipe
    /// title comes from the user's library when the entry's recipeId is
    /// still present; otherwise we fall back to the id itself.
    private func matchResultCard(_ match: MatchResult) -> some View {
        let entry = match.entry
        let recipe = state.recipe(entry.recipeId)
        let title = recipe?.title ?? entry.recipeId
        return SurfaceCard(padding: EdgeInsets()) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Kicker("Closest match", color: Theme.primary)
                        Spacer()
                        StatusPill(kind: similarityPillKind(match.similarity),
                                    text: "\(match.similarity)% similar")
                    }
                    Text(title)
                        .font(Typography.display(24, weight: .medium))
                        .foregroundStyle(Theme.slate900)
                    HStack(spacing: 8) {
                        StarRating(rating: entry.rating, size: 14)
                        Text("·").foregroundStyle(Theme.slate400)
                        Text(entry.dateDisplay)
                            .font(Typography.ui(12)).foregroundStyle(Theme.slate600)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
                .background(
                    LinearGradient(colors: [Theme.primaryTint, .white],
                                    startPoint: .top, endPoint: .bottom)
                )
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.border1).frame(height: 1) }

                HStack(alignment: .top, spacing: 12) {
                    if let asset = entry.photoAsset {
                        BreadPhoto(assetName: asset, kind: .crumb, height: 80)
                            .frame(width: 110, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        if !entry.note.isEmpty {
                            Text(entry.note)
                                .font(Typography.ui(12.5))
                                .foregroundStyle(Theme.slate700)
                                .lineLimit(4)
                        } else {
                            Text("No notes from this bake.")
                                .font(Typography.ui(12.5))
                                .foregroundStyle(Theme.slate500)
                        }
                        Button {
                            state.goTo(.journal)
                        } label: {
                            Label("View in journal", systemImage: "graph")
                        }
                        .ccGhost(compact: true)
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
            }
        }
    }

    /// The honest disclosure card. Wording shifts depending on
    /// whether Cloud AI ran — when it did, we name what was sent
    /// where; when it didn't, we keep the original Stage-24a copy.
    private var honestyCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                Kicker("How this works", color: Theme.slate500)
                Text(honestyBody)
                    .font(Typography.ui(12.5))
                    .foregroundStyle(Theme.slate600)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var honestyBody: String {
        if diagnosis != nil {
            return "GeekBread sent your crumb photo and bake context (hydration, bulk time, kitchen temp, retard) to Anthropic Claude (Haiku) for the diagnosis above, then ran Apple Vision on-device to find the closest match in your journal. The diagnosis is the model's best read of the photo — your judgement still calls it."
        }
        if state.cloudAIEnabled {
            return "Apple Vision computed a feature print on-device and compared it to your journal photos. The Cloud AI diagnosis didn't return a high-confidence answer this time, so we're showing the similarity match only — your judgement still calls it."
        }
        return "Apple Vision computes a feature print for your crumb shot and compares it to your journal photos. Higher percentages mean visually closer — they don't predict how this bake will rate. Your judgement still calls it."
    }

    private var emptyJournalCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Kicker("No comparisons yet")
                Text("Log a few bakes with photos first.")
                    .font(Typography.display(20, weight: .medium))
                    .foregroundStyle(Theme.slate900)
                Text("The diagnostic compares your crumb shots against your past bakes' photos. With nothing in your journal yet, there's nothing to compare to — finish a bake (Active bake → Complete bake) and the matcher comes alive.")
                    .font(Typography.ui(13))
                    .foregroundStyle(Theme.slate600)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    state.goTo(.journal)
                } label: {
                    Label("Open Journal", systemImage: "graph")
                }
                .ccSecondary(compact: true)
            }
        }
    }

    private func similarityPillKind(_ pct: Int) -> PillKind {
        switch pct {
        case 70...: return .good
        case 40...: return .info
        default:    return .neutral
        }
    }

    private func reset() {
        diagState = .idle
        match = nil
        diagnosis = nil
        currentPhoto = nil
    }

    /// Run the Stage-24 cloud diagnose call (if opted in) in parallel
    /// with the Stage-24a on-device similarity match. Both finish
    /// before we flip to `.result`. On any cloud failure or low
    /// confidence, `diagnosis` stays nil and the similarity card
    /// becomes the surfaced answer — same UX as before Cloud AI.
    private func startAnalysis() {
        diagState = .analyzing
        match = nil
        diagnosis = nil
        let photoName = currentPhoto
        let journal = state.journal
        let persistence = state.persistence
        let cloudEnabled = state.cloudAIEnabled
        let bakeContext = makeBakeContext()
        Task.detached(priority: .userInitiated) {
            guard let filename = photoName,
                  let currentImage = persistence.loadPhoto(named: filename) else {
                await MainActor.run { self.diagState = .idle }
                return
            }

            // Kick off the remote call concurrently with Vision so the
            // two latencies overlap instead of stacking.
            async let cloudDiagnosisTask: Diagnosis? = cloudEnabled
                ? CrumbDiagnosis.diagnose(image: currentImage, context: bakeContext)
                : nil
            async let currentPrintTask = VisionFeaturePrint.compute(for: currentImage)

            let currentPrint = await currentPrintTask
            guard let currentPrint else {
                let remote = await cloudDiagnosisTask
                await MainActor.run {
                    // Even when the current image can't be embedded
                    // for similarity, a cloud diagnosis can still
                    // succeed — surface it.
                    self.diagnosis = remote?.isConfident == true ? remote : nil
                    self.match = nil
                    self.diagState = .result
                }
                return
            }

            var best: (JournalEntry, Float)?
            for entry in journal {
                guard let asset = entry.photoAsset,
                      let img = persistence.loadPhoto(named: asset),
                      let print = await VisionFeaturePrint.compute(for: img) else {
                    continue
                }
                let d = VisionFeaturePrint.distance(currentPrint, print)
                if best == nil || d < best!.1 { best = (entry, d) }
            }
            let result: MatchResult? = best.map { entry, distance in
                MatchResult(
                    entry: entry,
                    similarity: VisionFeaturePrint.similarityPercent(distance: distance)
                )
            }
            let remoteDiagnosis = await cloudDiagnosisTask
            await MainActor.run {
                self.match = result
                self.diagnosis = remoteDiagnosis?.isConfident == true ? remoteDiagnosis : nil
                self.diagState = .result
            }
        }
    }
}

// MARK: - Helpers

private struct BlurChip: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.ui(12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().fill(Color.black.opacity(0.4)).blendMode(.multiply))
    }
}

#Preview("Diagnostic") {
    DiagnosticScreen(state: AppState(persistence: PersistenceController(filename: "preview-diag.json")))
        .padding()
        .background(Theme.surface1)
        .frame(width: 1100, height: 800)
}
