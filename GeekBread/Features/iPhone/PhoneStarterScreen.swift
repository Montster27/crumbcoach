import SwiftUI

// iPhone Starter — vertical stack: switcher chips (horizontal scroll) →
// rise chart → AI starter check → feeding log. Same state mutations as
// the iPad screen; only the layout is portrait-friendly.

struct PhoneStarterScreen: View {
    var state: AppState
    @State private var selectedId: String
    @State private var photoPickerOpen = false
    @State private var addStarterOpen = false

    init(state: AppState) {
        self.state = state
        _selectedId = State(initialValue: state.starters.first?.id ?? "")
    }

    private var selected: Starter? { state.starter(selectedId) }

    var body: some View {
        Group {
            if state.starters.isEmpty {
                PhoneEmptyStarterView { addStarterOpen = true }
            } else {
                ScrollView {
                    VStack(spacing: PhoneTheme.cardSpacing) {
                        switcher
                        if let s = selected {
                            riseCard(starter: s)
                            aiCheckCard(starter: s)
                            feedingLogCard(starter: s)
                        }
                    }
                    .padding(.horizontal, PhoneTheme.screenHPad)
                    .padding(.top, PhoneTheme.screenVPad)
                    .padding(.bottom, PhoneTheme.sectionSpacing)
                }
            }
        }
        .background(Theme.surface1)
        .photoPicker(isPresented: $photoPickerOpen) { image in
            state.setStarterPhoto(image, starterId: selectedId)
            if state.cloudAIEnabled {
                let starterId = selectedId
                let context = makeStarterContext(state.starter(starterId))
                Task {
                    let assessment = await StarterHealthCheck.assess(image: image, context: context)
                    await MainActor.run {
                        state.setStarterAssessment(starterId: starterId, assessment: assessment)
                    }
                }
            }
        }
        .sheet(isPresented: $addStarterOpen) {
            PhoneAddStarterSheet { name, flourType in
                let id = state.addStarter(name: name, flourType: flourType)
                selectedId = id
            }
            .presentationDetents([.medium, .large])
        }
        .toolbar {
            if !state.starters.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { addStarterOpen = true } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Add starter")
                }
            }
        }
    }

    // MARK: Switcher

    private var switcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(state.starters) { st in
                    PhoneStarterChip(starter: st, active: st.id == selectedId) {
                        selectedId = st.id
                    }
                }
            }
            .padding(.horizontal, PhoneTheme.screenHPad)
            .padding(.vertical, 2)
        }
        .padding(.horizontal, -PhoneTheme.screenHPad)
    }

    // MARK: Rise card

    private func riseCard(starter: Starter) -> some View {
        SurfaceCard(padding: EdgeInsets()) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Kicker("Rise · last 12 hours")
                    Text("\(starter.name) peaked 2h ago")
                        .font(Typography.display(18, weight: .medium))
                        .foregroundStyle(Theme.slate900)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, PhoneTheme.cardPad)
                .padding(.vertical, 12)

                PhoneRiseChart(values: starter.riseHistory, peakHeight: starter.peakHeightPct)
                    .frame(height: 160)
                    .padding(.horizontal, PhoneTheme.cardPad)
                    .padding(.bottom, 12)

                Rectangle().fill(Theme.border1).frame(height: 1)
                LazyVGrid(columns: [GridItem(.flexible()),
                                    GridItem(.flexible())], spacing: 0) {
                    starterMeta("Last fed",    starter.lastFeed)
                    starterMeta("Peak height", "\(starter.peakHeightPct)%")
                    starterMeta("Peak at",     starter.peakAt)
                    starterMeta("Next feed",   starter.nextFeed)
                }
            }
        }
    }

    private func starterMeta(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Kicker(label, size: 9.5)
            Text(value)
                .font(Typography.mono(14, weight: .semibold))
                .foregroundStyle(Theme.slate900)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PhoneTheme.cardPad)
        .padding(.vertical, 10)
    }

    // MARK: AI check

    private func aiCheckCard(starter: Starter) -> some View {
        SurfaceCard(padding: EdgeInsets()) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    BreadPhoto(assetName: starter.lastPhoto ?? "starter",
                               kind: .starter, height: 140)
                    LinearGradient(colors: [.clear, .black.opacity(0.7)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 140)
                    VStack(alignment: .leading, spacing: 2) {
                        if let time = starter.lastPhotoTime {
                            Text("Photo · \(time)")
                                .font(Typography.ui(10.5))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        Text(starter.state)
                            .font(Typography.display(16, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    VStack {
                        HStack {
                            Spacer()
                            Button { photoPickerOpen = true } label: {
                                Label("Add photo", systemImage: "camera")
                            }
                            .buttonStyle(PhoneBlurChip())
                        }
                        Spacer()
                    }
                    .padding(8)
                }
                .frame(height: 140)
                .clipped()

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Kicker("Starter health AI")
                        Spacer()
                        if let a = starter.assessment, a.isConfident {
                            StatusPill(kind: assessmentPillKind(a.state),
                                        text: "\(a.state.displayLabel) · \(Int((a.confidence * 100).rounded()))%")
                        }
                    }
                    aiCheckBody(starter: starter)
                    actionButtonRow(starter: starter)
                }
                .padding(PhoneTheme.cardPad)
            }
        }
    }

    @ViewBuilder
    private func aiCheckBody(starter: Starter) -> some View {
        if let a = starter.assessment, a.isConfident {
            Text(a.explanation)
                .font(Typography.ui(12.5))
                .foregroundStyle(Theme.slate700)
                .fixedSize(horizontal: false, vertical: true)
            if a.suggestedAction == .wait, let hours = a.waitHours {
                Text("Suggested: wait \(hours, format: .number.precision(.fractionLength(0...1)))h, then re-check.")
                    .font(Typography.ui(11.5, weight: .medium))
                    .foregroundStyle(Theme.slate900)
            }
        } else if starter.assessment != nil {
            Text("AI couldn't read this photo confidently. Try a clearer shot.")
                .font(Typography.ui(12.5))
                .foregroundStyle(Theme.slate600)
        } else if state.cloudAIEnabled, starter.lastPhoto == nil {
            Text("Add a photo to get an AI read on this starter's state.")
                .font(Typography.ui(12.5))
                .foregroundStyle(Theme.slate600)
        } else if state.cloudAIEnabled {
            Text("Tap “Add photo” to refresh the AI read for this starter.")
                .font(Typography.ui(12.5))
                .foregroundStyle(Theme.slate600)
        } else {
            Text("Photograph your starter and enable Cloud AI in Settings to get a state read.")
                .font(Typography.ui(12.5))
                .foregroundStyle(Theme.slate600)
        }
    }

    @ViewBuilder
    private func actionButtonRow(starter: Starter) -> some View {
        let suggested = (starter.assessment?.isConfident == true)
            ? starter.assessment?.suggestedAction
            : nil
        let storageActionIsFridge = starter.storage != .fridge
        let storageActionMatches: StarterAction =
            starter.storage == .fridge ? .bringToCounter : .refrigerate
        let feedIsPrimary = suggested == .feedNow
        let storageIsPrimary = suggested == storageActionMatches
        HStack(spacing: 6) {
            Button("Feed now") {
                state.logStarterFeeding(starterId: starter.id)
            }
            .buttonStyle(CCButtonStyle(
                variant: feedIsPrimary ? .primary : .secondary,
                compact: true))
            .frame(maxWidth: .infinity)

            Button(storageActionIsFridge ? "Refrigerate" : "Bring to counter") {
                state.setStarterStorage(starterId: starter.id,
                                        storage: starter.storage == .fridge ? .counter : .fridge)
            }
            .buttonStyle(CCButtonStyle(
                variant: storageIsPrimary ? .primary : .secondary,
                compact: true))
            .frame(maxWidth: .infinity)
        }
    }

    private func assessmentPillKind(_ state: StarterState) -> PillKind {
        switch state {
        case .peak:     return .good
        case .prePeak:  return .info
        case .postPeak: return .warn
        case .hungry:   return .bad
        case .sluggish: return .warn
        case .unknown:  return .neutral
        }
    }

    private func makeStarterContext(_ starter: Starter?) -> StarterContext {
        StarterContext(
            hoursSinceFeed: nil,
            kitchenTempC: state.kitchenTempC,
            storage: starter?.storage.rawValue,
            feedRatio: starter?.feedings.first?.ratio
        )
    }

    // MARK: Feeding log

    private func feedingLogCard(starter: Starter) -> some View {
        SurfaceCard(padding: EdgeInsets()) {
            VStack(alignment: .leading, spacing: 0) {
                Kicker("Recent feedings")
                    .padding(.horizontal, PhoneTheme.cardPad)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
                ForEach(starter.feedings) { f in
                    HStack {
                        Text(f.when)
                            .font(Typography.ui(12))
                            .foregroundStyle(Theme.slate900)
                        Spacer()
                        Text(f.ratio)
                            .font(Typography.mono(12))
                            .foregroundStyle(Theme.slate700)
                        Text("\(Int(f.ambientC))°C")
                            .font(Typography.mono(12))
                            .foregroundStyle(Theme.slate500)
                            .frame(width: 44, alignment: .trailing)
                    }
                    .padding(.horizontal, PhoneTheme.cardPad)
                    .padding(.vertical, 10)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Theme.border1).frame(height: 1)
                    }
                }
            }
        }
    }
}

// MARK: - Starter chip (phone)

private struct PhoneStarterChip: View {
    let starter: Starter
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: 0xF2E8D5), Color(hex: 0xD4B896), Color(hex: 0xA47D56)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(starter.name)
                            .font(Typography.display(15, weight: .medium))
                            .foregroundStyle(Theme.slate900)
                        Text("\(starter.flourType) · \(starter.ageDesc)")
                            .font(Typography.ui(10))
                            .foregroundStyle(Theme.slate500)
                            .lineLimit(1)
                    }
                }
                StatusPill(kind: kindFor(starter.stateKind),
                            text: starter.state,
                            dot: starter.stateKind == .warn)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minWidth: 180, alignment: .leading)
            .background(active ? Theme.primaryTint : .white,
                         in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(active ? Theme.primary : Theme.border1, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func kindFor(_ k: StarterStateKind) -> PillKind {
        switch k {
        case .good: return .good
        case .warn: return .warn
        case .info: return .info
        case .bad:  return .bad
        case .neutral: return .neutral
        }
    }
}

// MARK: - Rise chart (phone variant)

private struct PhoneRiseChart: View {
    let values: [Double]
    let peakHeight: Int

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let mx = values.max() ?? 1
            let pts = values.enumerated().map { i, v -> CGPoint in
                let x = CGFloat(i) / CGFloat(max(values.count - 1, 1)) * w
                let y = h - CGFloat(v / mx) * (h - 20) - 6
                return CGPoint(x: x, y: y)
            }
            let peakIdx = values.firstIndex(of: values.max() ?? 0) ?? 0

            ZStack {
                ForEach([0, 0.25, 0.5, 0.75, 1], id: \.self) { p in
                    Path { path in
                        let y = h - CGFloat(p) * (h - 20) - 6
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(Theme.border1,
                            style: p == 0 ? StrokeStyle() : StrokeStyle(dash: [3, 4]))
                }
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.addLine(to: CGPoint(x: 0, y: h))
                    p.closeSubpath()
                }
                .fill(Theme.warm.opacity(0.12))
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(Theme.warm, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if peakIdx < pts.count {
                    Circle().fill(.white)
                        .overlay(Circle().stroke(Theme.warm, lineWidth: 2))
                        .frame(width: 10, height: 10)
                        .position(pts[peakIdx])
                    Text("peak \(peakHeight)%")
                        .font(Typography.ui(10, weight: .semibold))
                        .foregroundStyle(Theme.slate900)
                        .position(x: pts[peakIdx].x, y: max(10, pts[peakIdx].y - 14))
                }
                Path { p in
                    p.move(to: CGPoint(x: w - 10, y: 0))
                    p.addLine(to: CGPoint(x: w - 10, y: h))
                }
                .stroke(Theme.primary, style: StrokeStyle(dash: [3, 3]))
                Text("NOW")
                    .font(Typography.ui(9, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .position(x: w - 22, y: 12)
            }
        }
    }
}

// MARK: - Blur chip used on the AI photo

private struct PhoneBlurChip: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.ui(11, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().fill(Color.black.opacity(0.4)).blendMode(.multiply))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

// MARK: - Empty state

private struct PhoneEmptyStarterView: View {
    let onAdd: () -> Void
    var body: some View {
        ScrollView {
            SurfaceCard {
                VStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Theme.primaryTint).frame(width: 56, height: 56)
                        CCIconView(icon: .starter, size: 22, color: Theme.primary)
                    }
                    VStack(spacing: 4) {
                        Text("No starters yet")
                            .font(Typography.display(20, weight: .medium))
                            .foregroundStyle(Theme.slate900)
                        Text("Add your sourdough starter to log feedings, track peak times, and get bake-ready prompts.")
                            .font(Typography.ui(13))
                            .foregroundStyle(Theme.slate600)
                            .multilineTextAlignment(.center)
                    }
                    Button(action: onAdd) {
                        Label("Add starter", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .ccPrimary()
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, PhoneTheme.screenHPad)
            .padding(.top, 36)
        }
    }
}

// MARK: - Add starter sheet (phone)

private struct PhoneAddStarterSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (String, String) -> Void

    @State private var name: String = ""
    @State private var flourType: String = "White wheat"

    private let flourSuggestions = ["White wheat", "Whole wheat", "Whole rye",
                                    "Spelt", "Einkorn", "Mixed"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(Typography.ui(12, weight: .medium))
                            .foregroundStyle(Theme.slate700)
                        TextField("Ruby, Mort, Buddy…", text: $name)
                            .font(Typography.ui(14))
                            .padding(10)
                            .background(Color.white,
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Theme.border1, lineWidth: 1)
                            )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Flour")
                            .font(Typography.ui(12, weight: .medium))
                            .foregroundStyle(Theme.slate700)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(flourSuggestions, id: \.self) { f in
                                    TagPill(label: f, active: f == flourType) { flourType = f }
                                }
                            }
                        }
                    }
                }
                .padding(PhoneTheme.cardPad)
            }
            .background(Theme.surface1)
            .navigationTitle("New starter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave(name, flourType)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

#Preview("Phone Starter") {
    NavigationStack {
        PhoneStarterScreen(state: AppState(persistence: PersistenceController(filename: "preview-phone-starter.json")))
            .navigationTitle("Starter")
            .navigationBarTitleDisplayMode(.inline)
    }
}
