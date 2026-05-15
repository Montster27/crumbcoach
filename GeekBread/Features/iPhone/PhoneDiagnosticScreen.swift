import SwiftUI

// iPhone Diagnostic — photo on top, state-dependent content below.
// Camera-first entry since the phone *is* the camera.
//
// The Vision + Cloud diagnosis pipeline is copied verbatim from the iPad
// DiagnosticScreen; only the layout adapts. We can't share the iPad's
// internal `startAnalysis()` because it's a private instance method on
// `DiagnosticScreen`, but the algorithm (parallel Vision + Cloud) is
// straightforward to duplicate.

struct PhoneDiagnosticScreen: View {
    var state: AppState

    enum DiagState { case idle, analyzing, result }

    @State private var diagState: DiagState = .idle
    @State private var currentPhoto: String? = nil
    @State private var photoPickerOpen = false
    @State private var match: MatchResult? = nil
    @State private var diagnosis: Diagnosis? = nil

    struct MatchResult {
        let entry: JournalEntry
        let similarity: Int
    }

    var body: some View {
        ScrollView {
            VStack(spacing: PhoneTheme.cardSpacing) {
                photoPanel
                stateContent
            }
            .padding(.horizontal, PhoneTheme.screenHPad)
            .padding(.top, PhoneTheme.screenVPad)
            .padding(.bottom, PhoneTheme.sectionSpacing)
        }
        .background(Theme.surface1)
        .photoPicker(isPresented: $photoPickerOpen) { image in
            if let filename = state.persistence.savePhoto(image) {
                currentPhoto = filename
                startAnalysis()
            } else {
                state.photoErrorMessage = "Couldn't save that photo. Try again — your iPhone may be low on storage."
            }
        }
        .onAppear {
            if let pending = state.pendingDiagnosticPhoto {
                currentPhoto = pending
                state.pendingDiagnosticPhoto = nil
                startAnalysis()
            }
        }
        .toolbar {
            if diagState == .result {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { photoPickerOpen = true } label: {
                        Image(systemName: "camera.fill")
                    }
                    .accessibilityLabel("New photo")
                }
            }
        }
    }

    // MARK: Photo panel

    private var photoPanel: some View {
        ZStack {
            BreadPhoto(assetName: currentPhoto, kind: .crumb, height: 320)
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .clipped()

            VStack {
                HStack {
                    topLabel
                    Spacer()
                }
                .padding(10)
                Spacer()
                if diagState == .result {
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: 0x86EFAC)).frame(width: 5, height: 5)
                        Text(diagnosis == nil
                             ? "On-device · never left this iPhone"
                             : "Sent to Anthropic Claude · Settings → Cloud AI")
                            .font(Typography.ui(10.5))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.7), in: Capsule())
                    .padding(10)
                }
            }

            if diagState == .idle { idleOverlay }
            if diagState == .analyzing { analyzingOverlay }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
        .background(Theme.slate900,
                    in: RoundedRectangle(cornerRadius: PhoneTheme.cardRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: PhoneTheme.cardRadius, style: .continuous))
    }

    private var topLabel: some View {
        let timestamp = CCFormat.clockTime.string(from: Date())
        return Text("Crumb shot · \(timestamp)")
            .font(Typography.ui(11, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().fill(Color.black.opacity(0.45)).blendMode(.multiply))
    }

    private var idleOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
            VStack(spacing: 14) {
                Button { photoPickerOpen = true } label: {
                    Circle().fill(.white).frame(width: 72, height: 72)
                        .overlay(CCIconView(icon: .camera, size: 30, color: Theme.primary))
                        .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Take crumb photo")
                .accessibilityHint("Opens the camera or photo library to start a diagnostic")
                Text("Tap to analyze")
                    .font(Typography.ui(13))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private var analyzingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
            VStack(spacing: 12) {
                RingProgress(value: 0.65, size: 56, stroke: 4,
                              color: .white, trackColor: .white.opacity(0.2)) {
                    CCIconView(icon: .sparkle, size: 20, color: .white)
                }
                Text("Analyzing crumb structure…")
                    .font(Typography.ui(13, weight: .medium))
                    .foregroundStyle(.white)
                Text(state.cloudAIEnabled
                     ? "Apple Vision + Anthropic Claude"
                     : "On-device · No upload")
                    .font(Typography.ui(11))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: State-dependent content below the photo

    @ViewBuilder
    private var stateContent: some View {
        switch diagState {
        case .idle:      idleSide
        case .analyzing: analyzingSide
        case .result:    resultSide
        }
    }

    private var idleSide: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Kicker("Photo guide")
                Text("Sliced loaf, flat on the cutting board.")
                    .font(Typography.display(18, weight: .medium))
                    .foregroundStyle(Theme.slate900)
                Text("Overhead light, neutral background. We'll compare your shot against your journal's photos and surface the closest match.")
                    .font(Typography.ui(12.5))
                    .foregroundStyle(Theme.slate600)
                SoftDivider()
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(["Slice through the widest point",
                             "Avoid shadows from your phone",
                             "Include 1–2 cm of crust on top"], id: \.self) { t in
                        HStack(spacing: 10) {
                            CCIconView(icon: .check, size: 14, color: Theme.success600)
                            Text(t).font(Typography.ui(12.5)).foregroundStyle(Theme.slate700)
                        }
                    }
                }
            }
        }
    }

    private var analyzingSide: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                Kicker("Comparing")
                Text("Finding the closest journal match…")
                    .font(Typography.display(18, weight: .medium))
                    .foregroundStyle(Theme.slate900)
                let steps = [
                    "Computing this photo's feature print",
                    "Loading your journal's photos",
                    "Comparing against past bakes",
                ]
                ForEach(steps, id: \.self) { step in
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(Theme.slate100).frame(width: 20, height: 20)
                            Circle().fill(Theme.slate400).frame(width: 5, height: 5)
                        }
                        Text(step)
                            .font(Typography.ui(12.5))
                            .foregroundStyle(Theme.slate700)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var resultSide: some View {
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

    private func diagnosisCard(_ d: Diagnosis) -> some View {
        SurfaceCard(padding: EdgeInsets()) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Kicker("Diagnosis · Claude Haiku", color: Theme.primary)
                        Spacer()
                        StatusPill(kind: pillKind(for: d.primaryLabel),
                                    text: "\(Int((d.confidence * 100).rounded()))%")
                    }
                    Text(d.primaryLabel.displayLabel)
                        .font(Typography.display(20, weight: .medium))
                        .foregroundStyle(Theme.slate900)
                    Text(d.explanation)
                        .font(Typography.ui(12.5))
                        .foregroundStyle(Theme.slate700)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, PhoneTheme.cardPad)
                .padding(.vertical, 14)
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
                                CCIconView(icon: .check, size: 13, color: Theme.primary)
                                Text(suggestion)
                                    .font(Typography.ui(12))
                                    .foregroundStyle(Theme.slate700)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.horizontal, PhoneTheme.cardPad)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private func pillKind(for label: DiagnosisLabel) -> PillKind {
        switch label {
        case .even, .openCrumb:                                       return .good
        case .underproofed, .overproofed, .underbaked, .overferment:  return .warn
        case .tightCrumb:                                             return .info
        case .unknown:                                                return .neutral
        }
    }

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
                        .font(Typography.display(20, weight: .medium))
                        .foregroundStyle(Theme.slate900)
                    HStack(spacing: 8) {
                        StarRating(rating: entry.rating, size: 12)
                        Text("·").foregroundStyle(Theme.slate400)
                        Text(entry.dateDisplay)
                            .font(Typography.ui(11.5))
                            .foregroundStyle(Theme.slate600)
                    }
                }
                .padding(.horizontal, PhoneTheme.cardPad)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [Theme.primaryTint, .white],
                                    startPoint: .top, endPoint: .bottom)
                )
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.border1).frame(height: 1) }

                HStack(alignment: .top, spacing: 10) {
                    if let asset = entry.photoAsset {
                        BreadPhoto(assetName: asset, kind: .crumb, height: 72)
                            .frame(width: 96, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        if !entry.note.isEmpty {
                            Text(entry.note)
                                .font(Typography.ui(12))
                                .foregroundStyle(Theme.slate700)
                                .lineLimit(4)
                        } else {
                            Text("No notes from this bake.")
                                .font(Typography.ui(12))
                                .foregroundStyle(Theme.slate500)
                        }
                        Button {
                            state.goTo(.journal)
                        } label: {
                            Label("View in journal", systemImage: "chart.bar")
                        }
                        .ccGhost(compact: true)
                        .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, PhoneTheme.cardPad)
                .padding(.vertical, 12)
            }
        }
    }

    private var honestyCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 6) {
                Kicker("How this works", color: Theme.slate500)
                Text(honestyBody)
                    .font(Typography.ui(12))
                    .foregroundStyle(Theme.slate600)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var honestyBody: String {
        if diagnosis != nil {
            return "Your crumb photo and bake context (hydration, bulk, kitchen temp, retard) were sent to Anthropic Claude for the diagnosis above, then Apple Vision compared the photo on-device to your journal to find the closest match. Your judgement still calls it."
        }
        if state.cloudAIEnabled {
            return "Apple Vision compared this crumb to your journal photos on-device. The Cloud AI diagnosis didn't return a confident answer this time — showing similarity match only."
        }
        return "Apple Vision compares your crumb shot to your journal photos on-device. Similarity percentages don't predict how this bake will rate — your judgement still calls it."
    }

    private var emptyJournalCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Kicker("No comparisons yet")
                Text("Log a few bakes with photos first.")
                    .font(Typography.display(18, weight: .medium))
                    .foregroundStyle(Theme.slate900)
                Text("The diagnostic compares your crumb shots against past bakes' photos. With nothing in your journal yet, there's nothing to compare to.")
                    .font(Typography.ui(12.5))
                    .foregroundStyle(Theme.slate600)
                    .fixedSize(horizontal: false, vertical: true)
                Button { state.goTo(.journal) } label: {
                    Label("Open Journal", systemImage: "chart.bar")
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

    // MARK: Analysis (copied behavior from DiagnosticScreen.startAnalysis)

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

            async let cloudDiagnosisTask: Diagnosis? = cloudEnabled
                ? CrumbDiagnosis.diagnose(image: currentImage, context: bakeContext)
                : nil
            async let currentPrintTask = VisionFeaturePrint.compute(for: currentImage)

            let currentPrint = await currentPrintTask
            guard let currentPrint else {
                let remote = await cloudDiagnosisTask
                await MainActor.run {
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

#Preview("Phone Diagnostic") {
    NavigationStack {
        PhoneDiagnosticScreen(state: AppState(persistence: PersistenceController(filename: "preview-phone-diag.json")))
            .navigationTitle("Diagnose")
            .navigationBarTitleDisplayMode(.inline)
    }
}
