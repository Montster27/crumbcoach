import SwiftUI

// Modal recipe editor. New recipes default to `.userCreated`; an existing
// recipe is edited in place, preserving its source unless the user fills in a
// URL (which flips it to `.linked`). Baker's percentages and total dough
// weight are recomputed on save from the ingredient list — no hand-editing
// of percentages, the math is the source of truth.

struct RecipeEditorScreen: View {
    var state: AppState
    let editingRecipeId: String?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: Recipe
    @State private var sourceURL: String
    @State private var sourceName: String
    @State private var showDeleteConfirm: Bool = false
    @State private var triedSave: Bool = false
    @State private var photoPickerOpen: Bool = false
    @State private var isImporting: Bool = false
    @State private var importWarnings: [String] = []
    @State private var importError: String? = nil
    @State private var showOverwriteConfirm: Bool = false
    /// True once we've kicked off the first auto-import on appear. When the
    /// user opens a fresh editor via "Paste URL" or the share extension,
    /// the URL field is pre-filled — auto-firing the import matches what
    /// "paste a recipe URL" implies, and avoids the trap where saving
    /// without tapping Import persisted the `blank()` sourdough skeleton
    /// instead of the URL's actual recipe.
    @State private var didAutoImport: Bool = false

    init(state: AppState,
         editingRecipeId: String?,
         initialSourceURL: String? = nil) {
        self.state = state
        self.editingRecipeId = editingRecipeId
        let initial = editingRecipeId.flatMap(state.recipe(_:)) ?? Self.blank()
        _draft = State(initialValue: initial)
        if case .linked(let url, let name, _) = initial.source {
            _sourceURL = State(initialValue: url)
            _sourceName = State(initialValue: name)
        } else {
            // Share-extension hand-off lands here. When the deep-link
            // carries a URL we seed it as the source so the user only has
            // to tap Import to populate the rest of the editor.
            _sourceURL = State(initialValue: initialSourceURL ?? "")
            _sourceName = State(initialValue: "")
        }
    }

    /// Blank-recipe template — pre-populated with the bare minimum a sourdough
    /// baker expects (flour / water / salt / starter, four-fold bulk) so the
    /// editor doesn't open empty and force the user to compose a recipe from
    /// scratch.
    static func blank() -> Recipe {
        Recipe(
            id: UUID().uuidString,
            title: "",
            breadType: .sourdough,
            source: .userCreated,
            photo: nil,
            hydrationPct: 75,
            saltPct: 2,
            leavenPct: 20,
            totalDoughGrams: 1580,
            loafCount: 1,
            timeToBake: "8h",
            tags: [],
            twinScald: false,
            preferments: [],
            ingredients: [
                Ingredient(name: "Bread flour", category: .flour, weightGrams: 800, bakersPct: 100),
                Ingredient(name: "Water",       category: .liquid, weightGrams: 600, bakersPct: 75),
                Ingredient(name: "Salt",        category: .salt, weightGrams: 16, bakersPct: 2),
                Ingredient(name: "Levain",      category: .leaven, weightGrams: 160, bakersPct: 20),
            ],
            stages: [
                Stage(kind: .mix,       durationMin: 30,  temperatureC: 22, note: nil),
                Stage(kind: .bulkFold,  durationMin: 240, temperatureC: 22,
                      note: "4 sets of stretch & fold, 30 min apart", totalFolds: 4),
                Stage(kind: .preShape,  durationMin: 15,  temperatureC: nil, note: nil),
                Stage(kind: .finalShape, durationMin: 10, temperatureC: nil, note: nil),
                Stage(kind: .coldRetard, durationMin: 720, temperatureC: 4, note: nil),
                Stage(kind: .bake,      durationMin: 50,  temperatureC: 230, note: nil),
            ],
            lastBake: nil
        )
    }

    // MARK: Validation

    private var titleError: String? {
        draft.title.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Title is required" : nil
    }
    private var flourError: String? {
        let mainFlour = draft.ingredients.contains { $0.category == .flour && $0.weightGrams > 0 }
        let prefermentFlour = draft.preferments
            .flatMap(\.ingredients)
            .contains { $0.category == .flour && $0.weightGrams > 0 }
        return (mainFlour || prefermentFlour)
            ? nil
            : "Add at least one flour ingredient"
    }
    private var stagesError: String? {
        draft.stages.isEmpty ? "Add at least one stage" : nil
    }
    private var weightsError: String? {
        let bad = draft.ingredients.contains { $0.weightGrams < 0 }
            || draft.preferments.flatMap(\.ingredients).contains { $0.weightGrams < 0 }
            || draft.stages.contains { $0.durationMin < 0 }
        return bad ? "Weights and durations must be positive" : nil
    }

    private var isValid: Bool {
        titleError == nil && flourError == nil && stagesError == nil && weightsError == nil
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                photoSection
                metadataSection
                if let msg = titleError, triedSave {
                    Section { Text(msg).font(.caption).foregroundStyle(Theme.warm700) }
                }
                ingredientsSection
                if let msg = flourError, triedSave {
                    Section { Text(msg).font(.caption).foregroundStyle(Theme.warm700) }
                }
                prefermentsSection
                stagesSection
                if let msg = stagesError, triedSave {
                    Section { Text(msg).font(.caption).foregroundStyle(Theme.warm700) }
                }
                if let msg = weightsError, triedSave {
                    Section { Text(msg).font(.caption).foregroundStyle(Theme.warm700) }
                }
                if editingRecipeId != nil {
                    deleteSection
                }
            }
            .photoPicker(isPresented: $photoPickerOpen) { image in
                if let filename = state.persistence.savePhoto(image) {
                    draft.photo = filename
                } else {
                    state.photoErrorMessage = "Couldn't save that photo. Try again — your iPad may be low on storage."
                }
            }
            .task {
                // First-appear auto-import. The user reached this editor by
                // pasting a URL or sharing from Safari; firing the import
                // matches what those entry points imply. Gated to new
                // recipes only — editing an existing recipe with a source
                // URL shouldn't silently overwrite the user's data.
                guard !didAutoImport,
                      editingRecipeId == nil,
                      !sourceURL.trimmingCharacters(in: .whitespaces).isEmpty
                else { return }
                didAutoImport = true
                await runImport()
            }
            .navigationTitle(editingRecipeId == nil ? "New recipe" : "Edit recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        triedSave = true
                        if isValid { save() }
                    }
                }
            }
        }
        .frame(minWidth: 640, idealWidth: 760, minHeight: 720, idealHeight: 860)
        .alert("Delete this recipe?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let id = editingRecipeId {
                    state.deleteRecipe(id: id)
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        .alert("Replace recipe with imported one?", isPresented: $showOverwriteConfirm) {
            Button("Import", role: .destructive) {
                Task { await runImport() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Title, ingredients, and stages will be replaced by what's in the source. Stage durations and percentages will need a once-over.")
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var photoSection: some View {
        Section("Photo") {
            HStack(alignment: .center, spacing: 14) {
                BreadPhoto(assetName: draft.photo, kind: .crumb, height: 80)
                    .frame(width: 110, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Theme.border1, lineWidth: 1)
                    )
                    // Stage 27 — drag a photo from Photos / Files / Safari
                    // straight onto the thumbnail. Same persistence path
                    // as the picker, so the photo error surface (Stage 7)
                    // catches save failures the same way.
                    .dropDestination(for: Data.self) { items, _ in
                        guard let data = items.first,
                              let image = UIImage(data: data) else { return false }
                        if let filename = state.persistence.savePhoto(image) {
                            draft.photo = filename
                            return true
                        }
                        state.photoErrorMessage = "Couldn't save that photo. Try again — your iPad may be low on storage."
                        return false
                    }
                VStack(alignment: .leading, spacing: 6) {
                    Button { photoPickerOpen = true } label: {
                        Label(draft.photo == nil ? "Choose photo" : "Replace photo",
                              systemImage: "camera")
                    }
                    if draft.photo != nil {
                        Button(role: .destructive) { draft.photo = nil } label: {
                            Label("Remove photo", systemImage: "trash")
                        }
                    }
                    Text("Shown on the recipe card and the active-bake header. Drag in a photo or use the picker.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var metadataSection: some View {
        Section("Recipe") {
            TextField("Title", text: $draft.title)
            Picker("Bread type", selection: $draft.breadType) {
                ForEach(BreadType.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            Stepper(value: $draft.loafCount, in: 1...12) {
                Text("Loaves: \(draft.loafCount)")
            }
            TextField("Time-to-bake summary (e.g. “8h”)", text: $draft.timeToBake)
            Toggle("Twin scald (yudane + tangzhong)", isOn: $draft.twinScald)
            TextField("Source URL (optional)", text: $sourceURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !sourceURL.isEmpty {
                TextField("Source name (e.g. “King Arthur”)", text: $sourceName)
                HStack {
                    Button {
                        attemptImport()
                    } label: {
                        if isImporting {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Importing…")
                            }
                        } else {
                            Label("Import recipe", systemImage: "square.and.arrow.down")
                        }
                    }
                    .disabled(isImporting)
                    Spacer()
                }
                if let err = importError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(Theme.warm700)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !importWarnings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Import notes")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(importWarnings, id: \.self) { msg in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.warm)
                                    .accessibilityHidden(true)
                                Text(msg)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Decide whether the user has typed enough into the editor to warrant a
    /// confirmation before we overwrite. Empty title + no flour ingredient
    /// is the "fresh import" signal — go straight to fetch. Anything else
    /// asks first.
    private var editorHasUserContent: Bool {
        let hasTitle = !draft.title.trimmingCharacters(in: .whitespaces).isEmpty
        let hasFlour = draft.ingredients.contains {
            $0.category == .flour && $0.weightGrams > 0
                && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
        }
        // The blank() factory seeds a four-row sourdough skeleton, so we
        // also treat that exact starting state as "no user content yet".
        return hasTitle || (hasFlour && draft.ingredients.count > 4)
    }

    private func attemptImport() {
        if editorHasUserContent {
            showOverwriteConfirm = true
        } else {
            Task { await runImport() }
        }
    }

    private func runImport() async {
        importError = nil
        importWarnings = []
        guard let url = URL(string: sourceURL.trimmingCharacters(in: .whitespaces)),
              url.scheme?.hasPrefix("http") == true else {
            importError = RecipeImporterError.invalidURL.errorDescription
            return
        }
        isImporting = true
        defer { isImporting = false }
        do {
            var imported = try await RecipeImporter.import(from: url)
            // Stage 17.5b — opt-in second pass through Apple Foundation
            // Models. `applyAIAssist` no-ops when the framework isn't
            // available, but we also short-circuit on the toggle so we
            // don't spin up sessions on devices that wouldn't gain
            // anything from them.
            if state.aiAssistEnabled && AIRecipeAssist.isAvailable {
                imported = await RecipeImporter.applyAIAssist(to: imported)
            }
            // Stage 24 (haiku.md Tier 1.3) — opt-in structural cleanup
            // via Claude Haiku. Handles the things `AIRecipeAssist`
            // can't: preferment sectioning, bread type, stage
            // temperatures, fold counts, junk-row filtering.
            if state.cloudAIEnabled && RemoteAIClient.isConfigured {
                imported = await RemoteRecipeAssist.apply(to: imported,
                                                           rawHTML: imported.rawHTML)
            }
            await MainActor.run {
                applyImport(imported)
            }
        } catch let err as RecipeImporterError {
            importError = err.errorDescription
        } catch {
            importError = error.localizedDescription
        }
    }

    /// Replace the title / ingredients / stages / source from the imported
    /// draft. Preserves the user's existing `editingRecipeId` (we're editing
    /// the same record, not creating a new one), and re-routes the source-
    /// URL field bindings so the editor surfaces the correct fields.
    private func applyImport(_ imported: ImportedRecipe) {
        var snap = draft
        snap.title = imported.draft.title
        snap.ingredients = imported.draft.ingredients
        snap.preferments = imported.draft.preferments
        snap.stages = imported.draft.stages
        snap.totalDoughGrams = imported.draft.totalDoughGrams
        snap.source = imported.draft.source
        snap.twinScald = imported.draft.twinScald
        draft = snap
        if case .linked(_, let name, _) = imported.draft.source {
            sourceName = name
        }
        importWarnings = imported.warnings
    }

    @ViewBuilder
    private var prefermentsSection: some View {
        Section {
            ForEach($draft.preferments) { $pf in
                PrefermentRow(preferment: $pf, units: state.units)
            }
            .onDelete { offsets in
                let removedIds = offsets.map { draft.preferments[$0].id }
                draft.preferments.remove(atOffsets: offsets)
                // Clean up dangling stage references so a stage doesn't
                // point at a preferment block that no longer exists.
                for i in draft.stages.indices {
                    if let ref = draft.stages[i].scaldRef, removedIds.contains(ref) {
                        draft.stages[i].scaldRef = nil
                    }
                }
            }
            Menu {
                ForEach(PrefermentTemplate.allCases, id: \.id) { tmpl in
                    let exists = draft.preferments.contains { $0.id == tmpl.id }
                    Button {
                        draft.preferments.append(tmpl.makeDefault())
                    } label: {
                        Label(tmpl.displayName, systemImage: exists ? "checkmark" : "plus")
                    }
                    .disabled(exists)
                }
            } label: {
                Label("Add preferment", systemImage: "plus.circle")
            }
        } header: {
            Text("Preferments")
        } footer: {
            Text("Tangzhong / yudane scalds and levain builds. Sub-ingredients are tagged to their preferment so the main-dough flour % isn't double-counted.")
        }
    }

    @ViewBuilder
    private var ingredientsSection: some View {
        Section {
            ForEach($draft.ingredients) { $ing in
                IngredientRow(ingredient: $ing, units: state.units)
            }
            .onDelete { offsets in
                draft.ingredients.remove(atOffsets: offsets)
            }
            Button {
                draft.ingredients.append(
                    Ingredient(name: "", category: .flour, weightGrams: 0, bakersPct: 0)
                )
            } label: {
                Label("Add ingredient", systemImage: "plus.circle")
            }
        } header: {
            Text("Ingredients (\(state.units.inputLabel.lowercased()))")
        } footer: {
            Text("Baker's % and total dough weight recompute automatically on save.")
        }
    }

    @ViewBuilder
    private var stagesSection: some View {
        Section {
            ForEach($draft.stages) { $stage in
                StageRow(stage: $stage)
            }
            .onDelete { offsets in
                draft.stages.remove(atOffsets: offsets)
            }
            .onMove { src, dst in
                draft.stages.move(fromOffsets: src, toOffset: dst)
            }
            Button {
                draft.stages.append(
                    Stage(kind: .mix, durationMin: 30, temperatureC: nil, note: nil)
                )
            } label: {
                Label("Add stage", systemImage: "plus.circle")
            }
        } header: {
            HStack {
                Text("Stages")
                Spacer()
                EditButton().font(.caption)
            }
        }
    }

    @ViewBuilder
    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete recipe", systemImage: "trash")
            }
        }
    }

    // MARK: Save

    private func save() {
        var snap = draft
        snap.title = snap.title.trimmingCharacters(in: .whitespaces)

        // Drop blank-name rows the user added but never filled in, both at
        // the main-dough level and inside every preferment. Keeps the
        // editor forgiving without persisting empty placeholders.
        snap.ingredients = snap.ingredients.filter {
            !$0.name.trimmingCharacters(in: .whitespaces).isEmpty || $0.weightGrams > 0
        }
        // Tag every main-dough ingredient with `section = "main"` so the
        // recipe-detail table can split main vs. preferment cleanly. Seed
        // recipes do this; user-created ones now match.
        snap.ingredients = snap.ingredients.map { ing in
            var i = ing
            i.section = "main"
            return i
        }
        snap.preferments = snap.preferments.map { pf in
            var p = pf
            p.ingredients = p.ingredients
                .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty || $0.weightGrams > 0 }
                .map { ing in
                    var i = ing
                    i.section = p.id
                    return i
                }
            return p
        }

        // Combined flour total includes preferment flour, so baker's
        // percentages stay honest with tangzhong/yudane/levain.
        let combinedFlour =
            snap.ingredients.filter { $0.category == .flour }.reduce(0.0) { $0 + $1.weightGrams }
            + snap.preferments.flatMap(\.ingredients)
                .filter { $0.category == .flour }
                .reduce(0.0) { $0 + $1.weightGrams }

        if combinedFlour > 0 {
            snap.ingredients = snap.ingredients.map { ing in
                var i = ing
                i.bakersPct = ing.weightGrams / combinedFlour * 100
                return i
            }
            snap.preferments = snap.preferments.map { pf in
                var p = pf
                let prefermentFlour = p.ingredients
                    .filter { $0.category == .flour }
                    .reduce(0.0) { $0 + $1.weightGrams }
                p.flourPct = (prefermentFlour / combinedFlour) * 100
                p.ingredients = p.ingredients.map { ing in
                    var i = ing
                    i.bakersPct = ing.weightGrams / combinedFlour * 100
                    return i
                }
                return p
            }
        }

        // Total dough weight is the sum across main + every preferment.
        snap.totalDoughGrams =
            snap.ingredients.reduce(0) { $0 + $1.weightGrams }
            + snap.preferments.flatMap(\.ingredients).reduce(0) { $0 + $1.weightGrams }

        // Recipe-level percentages from the combined totals.
        let pct = BakersMath.computePercentages(for: snap)
        snap.hydrationPct = pct.hydrationPct
        snap.saltPct      = pct.saltPct
        snap.leavenPct    = pct.leavenPct

        // Resolve source from the URL field. A non-empty URL becomes
        // `.linked` regardless of prior source; an empty URL preserves the
        // existing source for edits (so .original/.userCreated round-trip)
        // and defaults to .userCreated for brand-new recipes.
        let trimmedURL = sourceURL.trimmingCharacters(in: .whitespaces)
        let trimmedName = sourceName.trimmingCharacters(in: .whitespaces)
        if !trimmedURL.isEmpty {
            let resolvedName = trimmedName.isEmpty ? "Linked recipe" : trimmedName
            snap.source = .linked(url: trimmedURL,
                                   sourceName: resolvedName,
                                   sourceLogo: nil)
        } else if editingRecipeId == nil {
            snap.source = .userCreated
        }
        // Existing edits keep their original source if no URL was supplied.

        state.updateRecipe(snap)
        state.selectedRecipeId = snap.id
        dismiss()
    }
}

// MARK: - Rows

private struct IngredientRow: View {
    @Binding var ingredient: Ingredient
    let units: Units

    /// Whole-number grams stay tidy in the editor; oz needs two decimals
    /// to round-trip cleanly (1 g ≈ 0.04 oz — integer-only would lose
    /// every value under ~28 g).
    private var weightFormat: FloatingPointFormatStyle<Double> {
        switch units {
        case .grams:  return .number.precision(.fractionLength(0))
        case .ounces: return .number.precision(.fractionLength(0...2))
        }
    }

    /// Display-unit projection over the underlying grams field. Reads the
    /// stored grams, converts to oz when needed, and writes the user's
    /// edit back as grams. Keeps `ingredient.weightGrams` canonical so
    /// baker's-percent math doesn't have to know about units.
    private var displayWeight: Binding<Double> {
        Binding(
            get: {
                switch units {
                case .grams:  return ingredient.weightGrams
                case .ounces: return ingredient.weightGrams / Units.gramsPerOunce
                }
            },
            set: { newValue in
                switch units {
                case .grams:  ingredient.weightGrams = newValue
                case .ounces: ingredient.weightGrams = newValue * Units.gramsPerOunce
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Ingredient name", text: $ingredient.name)
            HStack {
                Picker("Category", selection: $ingredient.category) {
                    ForEach(IngredientCategory.allCases, id: \.self) { c in
                        Text(c.rawValue).tag(c)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Spacer()
                TextField("0", value: displayWeight, format: weightFormat)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text(units.shortLabel).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct StageRow: View {
    @Binding var stage: Stage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Stage", selection: $stage.kind) {
                ForEach(StageKind.allCases, id: \.self) { k in
                    Text(k.rawValue).tag(k)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            HStack(spacing: 8) {
                TextField("0", value: $stage.durationMin, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                // Range upper-bound field appears only when the user opts
                // into a range (or the importer captured one). Keeping the
                // single-value layout default avoids cluttering recipes
                // that don't have a window.
                if stage.durationMaxMin != nil {
                    Text("–").foregroundStyle(.secondary)
                    TextField("max", value: Binding(
                        get: { stage.durationMaxMin ?? 0 },
                        set: { stage.durationMaxMin = $0 == 0 ? nil : $0 }
                    ), format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                }
                Text("min").foregroundStyle(.secondary)
                Button {
                    if stage.durationMaxMin == nil {
                        // Default the upper bound 50% above the lower as a
                        // sane starting point; user can edit immediately.
                        let suggestion = max(stage.durationMin + 15,
                                              Int(Double(stage.durationMin) * 1.5))
                        stage.durationMaxMin = suggestion
                    } else {
                        stage.durationMaxMin = nil
                    }
                } label: {
                    Image(systemName: stage.durationMaxMin == nil
                          ? "plus.rectangle.on.rectangle"
                          : "rectangle.slash")
                        .accessibilityLabel(stage.durationMaxMin == nil
                                            ? "Add range upper bound"
                                            : "Remove range upper bound")
                }
                .buttonStyle(.borderless)
                Spacer()
                TextField("Temp", value: Binding(
                    get: { stage.temperatureC ?? 0 },
                    set: { stage.temperatureC = $0 == 0 ? nil : $0 }
                ), format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                Text("°C").foregroundStyle(.secondary)
            }

            if stage.kind == .bulkFold {
                HStack {
                    Text("Folds")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Stepper(value: Binding(
                        get: { stage.totalFolds ?? 4 },
                        set: { stage.totalFolds = $0 }
                    ), in: 1...10) {
                        Text("\(stage.totalFolds ?? 4)")
                            .font(.body.monospacedDigit())
                    }
                    .labelsHidden()
                    .frame(maxWidth: 160)
                }
            }

            TextField("Note (optional)", text: Binding(
                get: { stage.note ?? "" },
                set: { stage.note = $0.isEmpty ? nil : $0 }
            ))
            .font(.callout)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preferments

/// Fixed catalogue of preferment kinds the editor can add. Each carries a
/// sensible default name / technique / flour-% so the user lands on a
/// row that already makes sense; they can edit any field afterward.
/// Custom preferments aren't exposed in v1 — the id field is referenced
/// by `Stage.scaldRef` and `Ingredient.section`, so keeping ids fixed
/// avoids the freeform-id maintenance burden.
private enum PrefermentTemplate: CaseIterable {
    case levain, yudane, tangzhong, biga, poolish

    var id: String {
        switch self {
        case .levain:    return "levain"
        case .yudane:    return "yudane"
        case .tangzhong: return "tangzhong"
        case .biga:      return "biga"
        case .poolish:   return "poolish"
        }
    }

    var displayName: String {
        switch self {
        case .levain:    return "Levain build"
        case .yudane:    return "Yudane (scald)"
        case .tangzhong: return "Tangzhong (cooked roux)"
        case .biga:      return "Biga"
        case .poolish:   return "Poolish"
        }
    }

    func makeDefault() -> Preferment {
        switch self {
        case .levain:
            return Preferment(
                id: "levain", name: "Levain",
                technique: "1:5:5 build to peak",
                prep: "Feed your starter and let it peak at the kitchen temp before mix.",
                flourPct: 20,
                ingredients: [
                    Ingredient(name: "Starter", category: .leaven, weightGrams: 30, bakersPct: 3, section: "levain"),
                    Ingredient(name: "Bread flour", category: .flour, weightGrams: 150, bakersPct: 19, section: "levain"),
                    Ingredient(name: "Water", category: .liquid, weightGrams: 150, bakersPct: 19, section: "levain"),
                ]
            )
        case .yudane:
            return Preferment(
                id: "yudane", name: "Yudane",
                technique: "1:1 scald · rest 12h",
                prep: "Whisk flour + boiling water 1:1, cover, rest overnight.",
                flourPct: 10,
                ingredients: [
                    Ingredient(name: "Bread flour", category: .flour, weightGrams: 80, bakersPct: 10, section: "yudane"),
                    Ingredient(name: "Boiling water", category: .liquid, weightGrams: 80, bakersPct: 10, section: "yudane"),
                ]
            )
        case .tangzhong:
            return Preferment(
                id: "tangzhong", name: "Tangzhong",
                technique: "1:5 cook to 65°C",
                prep: "Whisk flour + milk in a saucepan over medium heat to 65°C until pudding-thick. Cool.",
                flourPct: 6,
                ingredients: [
                    Ingredient(name: "Bread flour", category: .flour, weightGrams: 48, bakersPct: 6, section: "tangzhong"),
                    Ingredient(name: "Whole milk", category: .liquid, weightGrams: 240, bakersPct: 30, section: "tangzhong"),
                ]
            )
        case .biga:
            return Preferment(
                id: "biga", name: "Biga",
                technique: "55% hydration · rest 16h",
                prep: "Mix flour + water + a pinch of yeast. Rest cool overnight.",
                flourPct: 30,
                ingredients: [
                    Ingredient(name: "Bread flour", category: .flour, weightGrams: 240, bakersPct: 30, section: "biga"),
                    Ingredient(name: "Water", category: .liquid, weightGrams: 132, bakersPct: 16.5, section: "biga"),
                    Ingredient(name: "Instant yeast", category: .leaven, weightGrams: 1, bakersPct: 0.1, section: "biga"),
                ]
            )
        case .poolish:
            return Preferment(
                id: "poolish", name: "Poolish",
                technique: "100% hydration · rest 12h",
                prep: "Mix flour + water 1:1 + a pinch of yeast. Rest cool overnight.",
                flourPct: 25,
                ingredients: [
                    Ingredient(name: "Bread flour", category: .flour, weightGrams: 200, bakersPct: 25, section: "poolish"),
                    Ingredient(name: "Water", category: .liquid, weightGrams: 200, bakersPct: 25, section: "poolish"),
                    Ingredient(name: "Instant yeast", category: .leaven, weightGrams: 1, bakersPct: 0.1, section: "poolish"),
                ]
            )
        }
    }
}

/// Disclosure-group editor for one preferment block. Collapsed view shows the
/// name + technique + flour %; expanded reveals prep notes and sub-ingredients.
private struct PrefermentRow: View {
    @Binding var preferment: Preferment
    let units: Units
    @State private var expanded: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Name", text: $preferment.name)
                TextField("Technique (e.g. “1:5 cook to 65°C”)", text: $preferment.technique)
                TextField("Prep notes", text: $preferment.prep, axis: .vertical)
                    .lineLimit(2...4)
                HStack {
                    Text("Flour %")
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("0", value: $preferment.flourPct, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                    Text("%").foregroundStyle(.secondary)
                }
                SoftDivider()
                Text("Sub-ingredients")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach($preferment.ingredients) { $ing in
                    IngredientRow(ingredient: $ing, units: units)
                }
                .onDelete { offsets in
                    preferment.ingredients.remove(atOffsets: offsets)
                }
                Button {
                    preferment.ingredients.append(
                        Ingredient(name: "", category: .flour, weightGrams: 0, bakersPct: 0,
                                    section: preferment.id)
                    )
                } label: {
                    Label("Add sub-ingredient", systemImage: "plus.circle")
                }
                .font(.callout)
            }
            .padding(.vertical, 6)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(preferment.name.isEmpty ? "Untitled preferment" : preferment.name)
                    .font(.body.weight(.medium))
                HStack(spacing: 6) {
                    Text(preferment.technique)
                        .lineLimit(1)
                    if preferment.flourPct > 0 {
                        Text("·").foregroundStyle(.tertiary)
                        Text("\(preferment.flourPct, format: .number.precision(.fractionLength(0...1)))% flour")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview("New recipe") {
    RecipeEditorScreen(
        state: AppState(persistence: PersistenceController(filename: "preview-editor.json")),
        editingRecipeId: nil
    )
}
