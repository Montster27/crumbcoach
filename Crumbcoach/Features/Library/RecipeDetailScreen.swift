import SwiftUI

// Recipe detail — hero numbers row, ingredients table (with twin-scald block
// or tangzhong/yudane conversion), stages list, right-rail with scale +
// hydration sliders.  Uses the BakersMath / Conversion modules for real
// computation when the user adjusts sliders.

struct RecipeDetailScreen: View {
    @Bindable var state: AppState
    let recipeId: String

    @State private var scale: Double = 1.0
    @State private var hydration: Double = 75
    @State private var conversion: ConversionMode = .direct

    enum ConversionMode: String, CaseIterable, Identifiable {
        case direct, tangzhong, yudane
        var id: String { rawValue }
        var label: String {
            switch self {
            case .direct: return "Direct"
            case .tangzhong: return "Tangzhong"
            case .yudane: return "Yudane"
            }
        }
    }

    var recipe: Recipe? { state.recipe(recipeId) }

    var transformed: Recipe? {
        guard let r = recipe else { return nil }
        let scaled = BakersMath.scale(r, toTotalGrams: r.totalDoughGrams * scale)
        let (h, _) = BakersMath.adjustHydration(scaled, to: hydration)
        switch conversion {
        case .direct:    return h
        case .tangzhong: return Conversion.convertToTangzhong(h).0
        case .yudane:    return Conversion.convertToYudane(h).0
        }
    }

    var body: some View {
        guard let recipe, let working = transformed else {
            return AnyView(Text("Recipe not found").foregroundStyle(Theme.slate500))
        }
        let percentages = BakersMath.computePercentages(for: working)

        return AnyView(
            HStack(alignment: .top, spacing: 24) {
                // Left column
                VStack(alignment: .leading, spacing: 18) {
                    detailHeader(recipe: recipe)
                    heroNumbers(recipe: working, percentages: percentages)
                    ingredientsCard(recipe: working, percentages: percentages)
                    stagesCard(recipe: working)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                // Right rail
                VStack(spacing: 16) {
                    SurfaceCard(padding: EdgeInsets()) {
                        BreadPhoto(assetName: recipe.photo, kind: .crumb, height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 0) {
                            Kicker("Scale & convert")
                            scaleSlider(recipe: recipe)
                            hydrationSlider(recipe: recipe)
                        }
                    }

                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Kicker("Last 3 bakes")
                            if let last = recipe.lastBake {
                                HStack {
                                    Text(last.when).font(Typography.ui(13)).foregroundStyle(Theme.slate900)
                                    Spacer()
                                    StarRating(rating: last.rating, size: 13)
                                }
                                if let note = last.note {
                                    Text(note)
                                        .font(Typography.ui(11.5))
                                        .foregroundStyle(Theme.slate500)
                                }
                            } else {
                                Text("You haven't baked this yet.")
                                    .font(Typography.ui(12)).foregroundStyle(Theme.slate500)
                            }
                        }
                    }

                    Button(action: { state.goTo(.scheduler) }) {
                        Label("Schedule a bake", systemImage: "clock")
                            .frame(maxWidth: .infinity)
                    }
                    .ccPrimary()
                }
                .frame(width: 360)
            }
            .onAppear {
                scale = 1.0
                hydration = recipe.hydrationPct
                conversion = .direct
            }
            .onChange(of: recipeId) { _, _ in
                scale = 1.0
                hydration = recipe.hydrationPct
                conversion = .direct
            }
        )
    }

    // MARK: - Subviews

    private func detailHeader(recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { state.goTo(.library) }) {
                Text("← All recipes")
                    .font(Typography.ui(12))
                    .foregroundStyle(Theme.slate600)
            }
            .buttonStyle(.plain)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Kicker(recipe.breadType.rawValue)
                        if case .linked(_, let name, _) = recipe.source {
                            Text("· linked from \(name)")
                                .font(Typography.ui(11.5))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    Text(recipe.title)
                        .font(Typography.display(34, weight: .medium))
                        .foregroundStyle(Theme.slate900)
                        .padding(.top, 6)
                }
                Spacer()
                if case .linked = recipe.source {
                    Button(action: {}) {
                        Label("Open original", systemImage: "link")
                    }.ccSecondary()
                }
            }
            .padding(.top, 8)
            if case .linked(_, let name, _) = recipe.source {
                Text("Recipe by \(name). CrumbCoach extracted the formula for scheduling; full instructions live at the source.")
                    .font(Typography.ui(13))
                    .foregroundStyle(Theme.slate600)
                    .padding(.top, 8)
            }
        }
    }

    private func heroNumbers(recipe: Recipe, percentages: BakersPercentages) -> some View {
        SurfaceCard(padding: EdgeInsets()) {
            HStack(spacing: 0) {
                heroNumber("Hydration", String(format: "%.0f%%", percentages.hydrationPct))
                Rectangle().fill(Theme.border1).frame(width: 1, height: 60)
                heroNumber("Salt", String(format: "%.1f%%", percentages.saltPct))
                Rectangle().fill(Theme.border1).frame(width: 1, height: 60)
                heroNumber("Leavening", String(format: "%.1f%%", percentages.leavenPct))
                Rectangle().fill(Theme.border1).frame(width: 1, height: 60)
                heroNumber("Dough wt", "\(Int(percentages.totalDoughGrams))g")
                Rectangle().fill(Theme.border1).frame(width: 1, height: 60)
                heroNumber("Loaves", "\(max(1, Int(round(Double(recipe.loafCount) * scale))))")
            }
        }
    }

    private func heroNumber(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Kicker(label)
            Text(value)
                .font(Typography.mono(22, weight: .semibold))
                .foregroundStyle(Theme.slate900)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func ingredientsCard(recipe: Recipe, percentages: BakersPercentages) -> some View {
        SurfaceCard(padding: EdgeInsets()) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Kicker("Formula")
                        Text("Ingredients · baker's %")
                            .font(Typography.display(18, weight: .medium))
                            .foregroundStyle(Theme.slate900)
                    }
                    Spacer()
                    if recipe.twinScald {
                        HStack(spacing: 4) {
                            CCIconView(icon: .sparkle, size: 12, color: Theme.primary)
                            Text("Twin scald")
                                .font(Typography.ui(11, weight: .semibold))
                                .foregroundStyle(Theme.primaryDeep)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.primaryTint, in: Capsule())
                    } else {
                        HStack(spacing: 6) {
                            ForEach(ConversionMode.allCases) { m in
                                TagPill(label: m.label, active: m == conversion) {
                                    conversion = m
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)

                // Preferment blocks if present (e.g., twin scald)
                if !recipe.preferments.isEmpty {
                    prefermentBlocks(recipe: recipe)
                }

                ingredientsTable(recipe: recipe, percentages: percentages)
            }
        }
    }

    private func prefermentBlocks(recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ForEach(recipe.preferments) { pf in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(pf.name).font(Typography.display(15, weight: .medium))
                            Spacer()
                            Text("\(Int(pf.flourPct))% flour")
                                .font(Typography.mono(11)).foregroundStyle(Theme.slate500)
                        }
                        Text(pf.technique)
                            .font(Typography.ui(11)).foregroundStyle(Theme.slate500)
                        Text(pf.prep)
                            .font(Typography.ui(12))
                            .foregroundStyle(Theme.slate600)
                            .multilineTextAlignment(.leading)
                            .padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Theme.border1, lineWidth: 1)
                    )
                }
            }
            .padding(12)
            .background(
                LinearGradient(colors: [Theme.primaryTint, Theme.surface2],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .padding(.horizontal, 22)
            .padding(.bottom, 8)
            if recipe.twinScald {
                Text("Twin-scald combines a cold yudane (rest) with a hot tangzhong (cook) — gelatinizes ~14% of total flour. Both flour weights are subtracted from the main dough below.")
                    .font(Typography.ui(11)).foregroundStyle(Theme.slate500)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 8)
            }
        }
    }

    private func ingredientsTable(recipe: Recipe, percentages: BakersPercentages) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Ingredient").frame(maxWidth: .infinity, alignment: .leading)
                Text("Baker's %").frame(width: 80, alignment: .trailing)
                Text("Weight").frame(width: 80, alignment: .trailing)
                Text("Category").frame(width: 90, alignment: .trailing)
            }
            .font(Typography.ui(11, weight: .semibold))
            .foregroundStyle(Theme.slate500)
            .kerning(0.6)
            .textCase(.uppercase)
            .padding(.horizontal, 22)
            .padding(.vertical, 8)
            .background(Theme.slate50)

            // Preferment rows
            ForEach(recipe.preferments) { pf in
                HStack {
                    Text(pf.name.uppercased())
                        .font(Typography.ui(12, weight: .semibold)).foregroundStyle(Theme.primary)
                        .kerning(0.4)
                    Spacer()
                    Text(pf.technique)
                        .font(Typography.mono(11)).foregroundStyle(Theme.slate600)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(Theme.primaryTint)
                .overlay(alignment: .top) { Rectangle().fill(Theme.border1).frame(height: 1) }

                ForEach(pf.ingredients) { ing in
                    ingredientRow(ing, indent: 12)
                }
            }
            if !recipe.preferments.isEmpty {
                Text("Main dough")
                    .font(Typography.ui(12, weight: .semibold)).foregroundStyle(Theme.slate600)
                    .kerning(0.4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Theme.surface2)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.border1).frame(height: 1) }
            }

            ForEach(recipe.ingredients) { ing in
                ingredientRow(ing)
            }
        }
    }

    private func ingredientRow(_ ing: Ingredient, indent: CGFloat = 0) -> some View {
        HStack {
            Text(ing.name)
                .font(Typography.ui(13.5, weight: .medium))
                .foregroundStyle(Theme.slate900)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, indent)
            Text(String(format: "%.1f", ing.bakersPct))
                .font(Typography.mono(13)).foregroundStyle(Theme.slate700)
                .frame(width: 80, alignment: .trailing)
            Text("\(Int(ing.weightGrams))g")
                .font(Typography.mono(13, weight: .semibold)).foregroundStyle(Theme.slate900)
                .frame(width: 80, alignment: .trailing)
            HStack { Spacer()
                Text(ing.category.rawValue)
                    .font(Typography.ui(10.5, weight: .medium))
                    .foregroundStyle(Theme.pillNeutFg)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Theme.pillNeutBg, in: Capsule())
            }
            .frame(width: 90)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border1).frame(height: 1) }
    }

    private func stagesCard(recipe: Recipe) -> some View {
        SurfaceCard(padding: EdgeInsets()) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Kicker("Stages")
                    Text("Bake plan")
                        .font(Typography.display(18, weight: .medium))
                        .foregroundStyle(Theme.slate900)
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 8)

                ForEach(Array(recipe.stages.enumerated()), id: \.offset) { i, s in
                    HStack(spacing: 14) {
                        Text("\(i + 1)")
                            .font(Typography.mono(12, weight: .semibold))
                            .foregroundStyle(Theme.slate600)
                            .frame(width: 28, height: 28)
                            .background(Theme.slate100, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.kind.rawValue)
                                .font(Typography.ui(14, weight: .medium))
                                .foregroundStyle(Theme.slate900)
                            if let n = s.note {
                                Text(n)
                                    .font(Typography.ui(11.5))
                                    .foregroundStyle(Theme.slate500)
                            }
                        }
                        Spacer()
                        Text(CCFormat.duration(s.durationMin))
                            .font(Typography.mono(13))
                            .foregroundStyle(Theme.slate700)
                            .frame(width: 90, alignment: .trailing)
                        Text(s.temperatureC != nil ? "\(Int(s.temperatureC!))°C" : "—")
                            .font(Typography.mono(13))
                            .foregroundStyle(Theme.slate500)
                            .frame(width: 70, alignment: .trailing)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.border1).frame(height: 1) }
                }
            }
        }
    }

    private func scaleSlider(recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Total dough weight").font(Typography.ui(12)).foregroundStyle(Theme.slate600)
                Spacer()
                Text("\(Int(recipe.totalDoughGrams * scale))g")
                    .font(Typography.mono(12, weight: .semibold))
                    .foregroundStyle(Theme.slate900)
            }
            .padding(.top, 12)
            Slider(value: $scale, in: 0.5...3, step: 0.1)
                .tint(Theme.primary)
                .padding(.top, 4)
            HStack {
                Text("50%"); Spacer(); Text("1×"); Spacer(); Text("3×")
            }
            .font(Typography.ui(11)).foregroundStyle(Theme.slate500)
        }
    }

    private func hydrationSlider(recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Hydration").font(Typography.ui(12)).foregroundStyle(Theme.slate600)
                Spacer()
                Text("\(Int(hydration))%")
                    .font(Typography.mono(12, weight: .semibold))
                    .foregroundStyle(Theme.slate900)
            }
            .padding(.top, 16)
            Slider(value: $hydration, in: 55...95, step: 1).tint(Theme.primary).padding(.top, 4)
            Text(hydrationWarning(recipe: recipe))
                .font(Typography.ui(11))
                .foregroundStyle(hydration > recipe.hydrationPct + 5 || hydration < recipe.hydrationPct - 5
                                 ? Theme.warm700 : Theme.slate500)
        }
    }

    private func hydrationWarning(recipe: Recipe) -> String {
        if hydration > recipe.hydrationPct + 5 { return "⚠ Higher hydration than recipe target — bulk will run longer." }
        if hydration < recipe.hydrationPct - 5 { return "⚠ Drier than recipe target — expect tighter crumb." }
        return "Within recipe-safe range."
    }
}
