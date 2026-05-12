import SwiftUI

// AI Crumb Diagnostic screen — 4 states: idle, analyzing, result, feedback.
// AI is a stub here (timed transition); the contextual prompt + region
// annotations + feedback loop UX are real.

struct DiagnosticScreen: View {
    @Bindable var state: AppState

    enum DiagState { case idle, analyzing, result }
    enum Verdict   { case useful, notUseful, wrong }

    @State private var diagState: DiagState = .result   // start in the result view for showcase
    @State private var verdict: Verdict? = nil
    @State private var bakeChoice: String = "current"

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            // LEFT: photo + context
            VStack(spacing: 20) {
                photoPanel
                if diagState == .result {
                    contextBar
                }
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
    }

    // MARK: Photo panel

    private var photoPanel: some View {
        ZStack {
            BreadPhoto(assetName: "crumb_dense", kind: .crumb, height: 480)
                .aspectRatio(4 / 3, contentMode: .fit)

            if diagState == .result {
                AnnotationOverlay()
                bottomStrip
            }

            VStack {
                HStack {
                    topLabel
                    Spacer()
                    if diagState == .result {
                        Button(action: { reset() }) {
                            Label("New photo", systemImage: "camera")
                        }
                        .buttonStyle(BlurChip())
                    }
                }
                .padding(12)
                Spacer()
            }

            if diagState == .idle { idleOverlay }
            if diagState == .analyzing { analyzingOverlay }
        }
        .background(Theme.slate900, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.border1, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var topLabel: some View {
        Text("Country Sourdough · Crumb shot · Today 11:42 AM")
            .font(Typography.ui(12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.65), in: Capsule())
    }

    private var idleOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
            VStack(spacing: 16) {
                Button(action: { startAnalysis() }) {
                    Circle().fill(.white).frame(width: 88, height: 88)
                        .overlay(CCIconView(icon: .camera, size: 36, color: Theme.primary))
                        .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 6))
                }
                .buttonStyle(.plain)
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

    private var bottomStrip: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                HStack(spacing: 18) {
                    HStack(spacing: 6) {
                        Kicker("RUN", color: .white.opacity(0.55), size: 10)
                        Text("on-device · 1.8 s")
                            .font(Typography.ui(11)).foregroundStyle(.white)
                    }
                    Rectangle().fill(.white.opacity(0.35)).frame(width: 1, height: 10)
                    HStack(spacing: 6) {
                        Kicker("MODEL", color: .white.opacity(0.55), size: 10)
                        Text("CC-vlm v1.4 int4")
                            .font(Typography.ui(11)).foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Spacer()

                HStack(spacing: 6) {
                    Circle().fill(Color(hex: 0x86EFAC)).frame(width: 6, height: 6)
                    Text("Private · photo never left this iPad")
                        .font(Typography.ui(11)).foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.7), in: Capsule())
            }
            .padding(12)
        }
    }

    // MARK: Context bar

    private var contextBar: some View {
        SurfaceCard(padding: EdgeInsets()) {
            VStack(spacing: 0) {
                HStack(spacing: 18) {
                    Kicker("Context fed to model")
                    HStack(spacing: 22) {
                        contextDatum("75%", "hydration")
                        Text("·").foregroundStyle(Theme.slate300)
                        Text("Bulk ").font(Typography.ui(12)).foregroundStyle(Theme.slate700)
                        + Text("4h 15m").font(Typography.mono(12, weight: .semibold)).foregroundStyle(Theme.slate900)
                        + Text(" @ ").font(Typography.ui(12)).foregroundStyle(Theme.slate700)
                        + Text("22°C").font(Typography.mono(12, weight: .semibold)).foregroundStyle(Theme.slate900)
                        Text("·").foregroundStyle(Theme.slate300)
                        Text("Levain peaked ").font(Typography.ui(12)).foregroundStyle(Theme.slate700)
                        + Text("−2h").font(Typography.mono(12, weight: .semibold)).foregroundStyle(Theme.slate900)
                        Text("·").foregroundStyle(Theme.slate300)
                        Text("Cold retard ").font(Typography.ui(12)).foregroundStyle(Theme.slate700)
                        + Text("12h").font(Typography.mono(12, weight: .semibold)).foregroundStyle(Theme.slate900)
                    }
                    Spacer()
                    Button("Edit context →") { }.ccGhost(compact: true)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

                HStack(spacing: 8) {
                    Kicker("Comparing to")
                    ForEach([
                        ("current", "This recipe · last 6 bakes"),
                        ("best",    "Your 5-star bakes only"),
                        ("none",    "Recipe target only")
                    ], id: \.0) { id, label in
                        TagPill(label: label, active: id == bakeChoice) { bakeChoice = id }
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Theme.slate50)
                .overlay(alignment: .top) { Rectangle().fill(Theme.border1).frame(height: 1) }
            }
        }
    }

    private func contextDatum(_ value: String, _ label: String) -> some View {
        Text(value).font(Typography.mono(12, weight: .semibold)).foregroundStyle(Theme.slate900)
        + Text(" \(label)").font(Typography.ui(12)).foregroundStyle(Theme.slate700)
    }

    // MARK: Side panels

    private var idleSide: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                Kicker("Photo guide")
                Text("Sliced loaf, flat on the cutting board.")
                    .font(Typography.display(22, weight: .medium))
                    .foregroundStyle(Theme.slate900)
                Text("Overhead light, neutral background. The model needs to see cell distribution from base to top crust.")
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
                Kicker("Running diagnostic")
                Text("Analyzing crumb structure…")
                    .font(Typography.display(22, weight: .medium))
                    .foregroundStyle(Theme.slate900)
                let steps: [(String, Bool)] = [
                    ("Extracting crumb features", true),
                    ("Computing cell density", true),
                    ("Comparing to your bake history", false),
                    ("Drafting actionable insight", false),
                ]
                ForEach(Array(steps.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(item.1 ? Theme.success50 : Theme.slate100)
                                .frame(width: 22, height: 22)
                            if item.1 {
                                CCIconView(icon: .check, size: 13, color: Theme.success600)
                            } else {
                                Circle().fill(Theme.slate400).frame(width: 6, height: 6)
                            }
                        }
                        Text(item.0).font(Typography.ui(13))
                            .foregroundStyle(item.1 ? Theme.slate900 : Theme.slate500)
                    }
                }
            }
        }
    }

    private var resultSide: some View {
        VStack(spacing: 16) {
            // Headline diagnosis
            SurfaceCard(padding: EdgeInsets()) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Kicker("Diagnosis", color: Theme.warm700)
                            Spacer()
                            StatusPill(kind: .warn, text: "87% confidence")
                        }
                        Text("Underproofed bulk fermentation.")
                            .font(Typography.display(26, weight: .medium))
                            .foregroundStyle(Theme.slate900)
                        Text("Crumb shows a tight base with tunneling under the top crust. Compared to your last 5-star Country Sourdough (bake #23), structure is ~20% denser in the bottom third.")
                            .font(Typography.ui(13))
                            .foregroundStyle(Theme.slate600)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 20)
                    .background(
                        LinearGradient(colors: [Theme.warm50, .white],
                                        startPoint: .top, endPoint: .bottom)
                    )
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.border1).frame(height: 1) }

                    VStack(alignment: .leading, spacing: 10) {
                        Kicker("What I'm seeing")
                            .padding(.bottom, 4)
                        ForEach([
                            (1, Color(hex: 0xFBBF24), "Dense base", "Cells 40% smaller than your target"),
                            (2, Color(hex: 0xF87171), "Tunneling under crust", "Classic underproof tell"),
                            (3, Color(hex: 0x10B981), "Even mid-crumb", "This part is on target"),
                        ], id: \.0) { n, c, t, d in
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(c).frame(width: 22, height: 22)
                                    Text("\(n)")
                                        .font(Typography.ui(11, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t).font(Typography.ui(13, weight: .medium)).foregroundStyle(Theme.slate900)
                                    Text(d).font(Typography.ui(11.5)).foregroundStyle(Theme.slate500)
                                }
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                }
            }

            // Likely cause + Next time
            SurfaceCard(padding: EdgeInsets()) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Kicker("Likely cause")
                        Text("Bulk was 4h 15m at 22°C. Your past good bakes at this temperature ran 5h–5h 30m. Volume increase looked like 30% — your 5-star average is closer to 50%.")
                            .font(Typography.ui(13.5))
                            .foregroundStyle(Theme.slate700)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
                    SoftDivider()
                    VStack(alignment: .leading, spacing: 8) {
                        Kicker("Next time", color: Theme.primary)
                        Text("Either bulk 45 min longer, or warm kitchen to 24°C and hold bulk at ~4h 30m. Aim for 50% volume rise, not 30%.")
                            .font(Typography.ui(13.5)).foregroundStyle(Theme.slate700)
                        HStack(spacing: 8) {
                            Button(action: { state.goTo(.scheduler) }) {
                                Text("Adjust next bake schedule")
                                    .frame(maxWidth: .infinity)
                            }.ccPrimary()
                            Button(action: {}) { Image(systemName: "square.and.arrow.up") }
                                .ccSecondary()
                        }
                        .padding(.top, 6)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
                }
            }

            // Feedback
            SurfaceCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Kicker("Was this useful?")
                            Text("Your feedback fine-tunes the on-device model.")
                                .font(Typography.ui(11.5)).foregroundStyle(Theme.slate500)
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            FeedbackButton(icon: .thumbsUp, active: verdict == .useful, kind: .good) {
                                verdict = .useful
                            }
                            FeedbackButton(icon: .thumbsDown, active: verdict == .notUseful, kind: .bad) {
                                verdict = .notUseful
                            }
                            Button("Not what I'm seeing") {
                                verdict = .wrong
                            }
                            .font(Typography.ui(12, weight: .medium))
                            .foregroundStyle(Theme.slate700)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(verdict == .wrong ? Theme.slate100 : .white,
                                         in: Capsule())
                            .overlay(Capsule().stroke(Theme.border1, lineWidth: 1))
                            .buttonStyle(.plain)
                        }
                    }
                    if verdict == .useful {
                        Text("✓ Thanks. Logged to your local feedback set (87 samples).")
                            .font(Typography.ui(12))
                            .foregroundStyle(Theme.success700)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.success50, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
    }

    private func reset() {
        diagState = .idle
        verdict = nil
    }

    private func startAnalysis() {
        diagState = .analyzing
        Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            await MainActor.run { diagState = .result }
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
            .background(Color.black.opacity(0.65), in: Capsule())
    }
}

private struct AnnotationOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Region 1 — tight base
                Ellipse().stroke(Color(hex: 0xFDE68A),
                                  style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    .frame(width: 240, height: 56)
                    .position(x: w * 0.45, y: h * 0.78)
                Circle().fill(Color(hex: 0xFBBF24)).frame(width: 22, height: 22)
                    .overlay(Text("1").font(Typography.ui(11, weight: .bold)).foregroundStyle(Color(hex: 0x1F2937)))
                    .position(x: w * 0.15, y: h * 0.80)

                // Region 2 — tunneling
                Ellipse().stroke(Color(hex: 0xFCA5A5),
                                  style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    .frame(width: 110, height: 44)
                    .position(x: w * 0.60, y: h * 0.26)
                Circle().fill(Color(hex: 0xF87171)).frame(width: 22, height: 22)
                    .overlay(Text("2").font(Typography.ui(11, weight: .bold)).foregroundStyle(.white))
                    .position(x: w * 0.74, y: h * 0.20)

                // Region 3 — uneven holes mid
                Circle().stroke(Color(hex: 0xA7F3D0),
                                 style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    .frame(width: 68, height: 68)
                    .position(x: w * 0.34, y: h * 0.50)
                Circle().fill(Color(hex: 0x10B981)).frame(width: 22, height: 22)
                    .overlay(Text("3").font(Typography.ui(11, weight: .bold)).foregroundStyle(.white))
                    .position(x: w * 0.43, y: h * 0.41)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct FeedbackButton: View {
    let icon: CCIcon
    let active: Bool
    let kind: PillKind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CCIconView(icon: icon, size: 16,
                        color: active ? kind.fg : Theme.slate600)
                .padding(8)
                .background(active ? kind.bg : .white,
                             in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Theme.border1, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
