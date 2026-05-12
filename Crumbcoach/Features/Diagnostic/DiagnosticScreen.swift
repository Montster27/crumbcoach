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

                // Privacy reassurance — Vision feature-print computation
                // is fully on-device. We surface this honestly instead of
                // the prior fake "model version" badge.
                if diagState == .result {
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: 0x86EFAC)).frame(width: 6, height: 6)
                        Text("On-device · photo never left this iPad")
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
                Text("On-device vision model · No upload")
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
        if let match {
            matchResultCard(match)
            honestyCard
        } else {
            emptyJournalCard
        }
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

    /// The honest disclosure card. The whole point of Stage 24a is that
    /// we're NOT claiming AI diagnosis — we're comparing image features.
    /// Surfacing this once on the result page is the difference between
    /// "useful tool" and "lies to the user."
    private var honestyCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                Kicker("How this works", color: Theme.slate500)
                Text("Apple Vision computes a feature print for your crumb shot and compares it to your journal photos. Higher percentages mean visually closer — they don't predict how this bake will rate. Your judgement still calls it.")
                    .font(Typography.ui(12.5))
                    .foregroundStyle(Theme.slate600)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
        currentPhoto = nil
    }

    /// Real on-device comparison using `VisionFeaturePrint`. Computes the
    /// current photo's embedding, computes embeddings for every journal
    /// entry's photo, finds the nearest neighbour by feature distance,
    /// and surfaces the closest match. No model bundled; everything runs
    /// through Apple's `VNGenerateImageFeaturePrintRequest`.
    private func startAnalysis() {
        diagState = .analyzing
        match = nil
        let photoName = currentPhoto
        let journal = state.journal
        let persistence = state.persistence
        Task.detached(priority: .userInitiated) {
            guard let filename = photoName,
                  let currentImage = persistence.loadPhoto(named: filename),
                  let currentPrint = await VisionFeaturePrint.compute(for: currentImage) else {
                await MainActor.run { self.diagState = .idle }
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
            await MainActor.run {
                self.match = result
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
