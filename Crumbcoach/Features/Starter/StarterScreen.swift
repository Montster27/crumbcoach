import SwiftUI

// Starter screen — switcher chips + rise chart + AI starter-check + Sidekick
// status + feeding log.  Mirrors StarterScreen in screen-rest.jsx.

struct StarterScreen: View {
    var state: AppState
    @State private var selectedId: String
    @State private var range: String = "12h"
    @State private var photoPickerOpen = false

    init(state: AppState) {
        self.state = state
        // Default to the first available starter rather than hard-coding "ruby"
        // — after onboarding the user's data may not include the demo starter.
        _selectedId = State(initialValue: state.starters.first?.id ?? "")
    }

    var selected: Starter? { state.starter(selectedId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Switcher
            HStack(spacing: 12) {
                ForEach(state.starters) { st in
                    StarterChip(starter: st, active: st.id == selectedId) { selectedId = st.id }
                }
                addStarterButton
            }

            if let s = selected {
                HStack(alignment: .top, spacing: 18) {
                    // Rise chart card
                    riseCard(starter: s)
                        .frame(maxWidth: .infinity)

                    // Side stack
                    VStack(spacing: 16) {
                        aiCheckCard(starter: s)
                        sidekickCard
                        feedingLogCard(starter: s)
                    }
                    .frame(width: 360)
                }
            }
        }
        .photoPicker(isPresented: $photoPickerOpen) { image in
            state.setStarterPhoto(image, starterId: selectedId)
        }
    }

    private var addStarterButton: some View {
        Button(action: {}) {
            HStack(spacing: 8) {
                CCIconView(icon: .plus, size: 15, color: Theme.slate500)
                Text("Add starter")
                    .font(Typography.ui(13, weight: .medium)).foregroundStyle(Theme.slate500)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(minWidth: 180, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.border1, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Rise chart card

    private func riseCard(starter: Starter) -> some View {
        SurfaceCard(padding: EdgeInsets()) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Kicker("Rise activity · last 12 hours")
                        Text("\(starter.name) peaked 2h ago")
                            .font(Typography.display(20, weight: .medium))
                            .foregroundStyle(Theme.slate900)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(["12h", "3d", "30d"], id: \.self) { t in
                            TagPill(label: t, active: t == range) { range = t }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)

                RiseChart(values: starter.riseHistory, peakHeight: starter.peakHeightPct)
                    .frame(height: 200)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 16)

                HStack(spacing: 0) {
                    starterMeta("Last fed",    starter.lastFeed)
                    Rectangle().fill(Theme.border1).frame(width: 1)
                    starterMeta("Peak height", "\(starter.peakHeightPct)%")
                    Rectangle().fill(Theme.border1).frame(width: 1)
                    starterMeta("Peak at",     starter.peakAt)
                    Rectangle().fill(Theme.border1).frame(width: 1)
                    starterMeta("Next feed",   starter.nextFeed)
                }
                .frame(height: 60)
                .overlay(alignment: .top) { Rectangle().fill(Theme.border1).frame(height: 1) }
            }
        }
    }

    private func starterMeta(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Kicker(label)
            Text(value).font(Typography.mono(16, weight: .semibold)).foregroundStyle(Theme.slate900)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: AI starter check card

    private func aiCheckCard(starter: Starter) -> some View {
        let timeLabel = starter.lastPhotoTime ?? "6:14 PM today"
        return SurfaceCard(padding: EdgeInsets()) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    BreadPhoto(assetName: starter.lastPhoto ?? "starter",
                               kind: .starter, height: 130)
                    LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 130)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Photo · \(timeLabel)").font(Typography.ui(11)).foregroundStyle(.white.opacity(0.8))
                        Text("Surface starting to recede")
                            .font(Typography.display(17, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)

                    VStack {
                        HStack {
                            Spacer()
                            Button(action: { photoPickerOpen = true }) {
                                Label("Add photo", systemImage: "camera")
                            }
                            .buttonStyle(BlurChipStarter())
                        }
                        Spacer()
                    }
                    .padding(10)
                }
                .frame(height: 130)
                .clipped()

                VStack(alignment: .leading, spacing: 12) {
                    Kicker("Starter health AI")
                    Text("State: ")
                        .font(Typography.ui(13)).foregroundStyle(Theme.slate700)
                    + Text("post-peak").font(Typography.ui(13, weight: .semibold)).foregroundStyle(Theme.slate900)
                    + Text(". Surface flattening, large open bubbles. Use now for an active bake, refrigerate, or feed within ").font(Typography.ui(13)).foregroundStyle(Theme.slate700)
                    + Text("4h").font(Typography.mono(13, weight: .semibold)).foregroundStyle(Theme.slate900)
                    + Text(".").font(Typography.ui(13)).foregroundStyle(Theme.slate700)

                    HStack(spacing: 6) {
                        Button("Feed now") { }.ccPrimary(compact: true).frame(maxWidth: .infinity)
                        Button("Refrigerate") { }.ccSecondary(compact: true).frame(maxWidth: .infinity)
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: Sidekick card

    private var sidekickCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    CCIconView(icon: .device, size: 18, color: Theme.primary)
                    Kicker("Sidekick", color: Theme.primary)
                    StatusPill(kind: .good, text: "Connected", dot: true)
                }
                Text("Preset: ").font(Typography.ui(13)).foregroundStyle(Theme.slate700)
                + Text("Counter-active").font(Typography.ui(13, weight: .semibold)).foregroundStyle(Theme.slate900)
                + Text(" · fed daily, ready for spontaneous baking.").font(Typography.ui(13)).foregroundStyle(Theme.slate700)
                Text("Last feed at 8:14 AM · jar temp 23.1°C · 152% peak observed.")
                    .font(Typography.ui(11.5)).foregroundStyle(Theme.slate500)
            }
        }
    }

    // MARK: Feeding log

    private func feedingLogCard(starter: Starter) -> some View {
        SurfaceCard(padding: EdgeInsets()) {
            VStack(alignment: .leading, spacing: 0) {
                Kicker("Recent feedings")
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
                ForEach(starter.feedings) { f in
                    HStack {
                        Text(f.when).font(Typography.ui(12.5)).foregroundStyle(Theme.slate900)
                        Spacer()
                        Text(f.ratio).font(Typography.mono(12.5)).foregroundStyle(Theme.slate700)
                        Text("\(Int(f.ambientC))°C")
                            .font(Typography.mono(12.5)).foregroundStyle(Theme.slate500)
                            .frame(width: 50, alignment: .trailing)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.border1).frame(height: 1) }
                }
            }
        }
    }
}

// MARK: - Switcher chip

private struct StarterChip: View {
    let starter: Starter
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: 0xF2E8D5), Color(hex: 0xD4B896), Color(hex: 0xA47D56)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(starter.name).font(Typography.display(17, weight: .medium))
                            .foregroundStyle(Theme.slate900)
                        Text("\(starter.flourType) · \(starter.ageDesc)")
                            .font(Typography.ui(11)).foregroundStyle(Theme.slate500)
                    }
                }
                StatusPill(kind: kindFor(starter.stateKind),
                            text: starter.state,
                            dot: starter.stateKind == .warn)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(minWidth: 220, alignment: .leading)
            .background(active ? Theme.primaryTint : .white,
                         in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
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

// MARK: - Rise chart

private struct RiseChart: View {
    let values: [Double]
    let peakHeight: Int

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let mx = values.max() ?? 1
            let pts = values.enumerated().map { i, v -> CGPoint in
                let x = CGFloat(i) / CGFloat(values.count - 1) * w
                let y = h - CGFloat(v / mx) * (h - 24) - 8
                return CGPoint(x: x, y: y)
            }
            let peakIdx = values.firstIndex(of: values.max() ?? 0) ?? 0

            ZStack {
                // Grid lines
                ForEach([0, 0.25, 0.5, 0.75, 1], id: \.self) { p in
                    Path { path in
                        let y = h - CGFloat(p) * (h - 24) - 8
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(Theme.border1,
                            style: p == 0 ? StrokeStyle() : StrokeStyle(dash: [3, 4]))
                }
                // Area
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.addLine(to: CGPoint(x: 0, y: h))
                    p.closeSubpath()
                }
                .fill(Theme.warm.opacity(0.12))
                // Line
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(Theme.warm, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                // Peak marker
                if peakIdx < pts.count {
                    Circle().fill(.white)
                        .overlay(Circle().stroke(Theme.warm, lineWidth: 2))
                        .frame(width: 12, height: 12)
                        .position(pts[peakIdx])
                    Text("peak \(peakHeight)%")
                        .font(Typography.ui(11, weight: .semibold))
                        .foregroundStyle(Theme.slate900)
                        .position(x: pts[peakIdx].x, y: max(12, pts[peakIdx].y - 16))
                }

                // Now marker
                Path { p in
                    p.move(to: CGPoint(x: w - 12, y: 0))
                    p.addLine(to: CGPoint(x: w - 12, y: h))
                }
                .stroke(Theme.primary, style: StrokeStyle(dash: [3, 3]))
                Text("NOW")
                    .font(Typography.ui(10, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .position(x: w - 24, y: 14)
            }
        }
    }
}

// MARK: - Translucent chip used over the starter photo

private struct BlurChipStarter: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.ui(12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().fill(Color.black.opacity(0.4)).blendMode(.multiply))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

#Preview("Starter") {
    StarterScreen(state: AppState(persistence: PersistenceController(filename: "preview-starter.json")))
        .padding()
        .background(Theme.surface1)
        .frame(width: 1100, height: 800)
}
