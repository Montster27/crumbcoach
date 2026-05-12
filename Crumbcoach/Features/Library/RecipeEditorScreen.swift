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

    init(state: AppState, editingRecipeId: String?) {
        self.state = state
        self.editingRecipeId = editingRecipeId
        let initial = editingRecipeId.flatMap(state.recipe(_:)) ?? Self.blank()
        _draft = State(initialValue: initial)
        if case .linked(let url, let name, _) = initial.source {
            _sourceURL = State(initialValue: url)
            _sourceName = State(initialValue: name)
        } else {
            _sourceURL = State(initialValue: "")
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
        draft.ingredients.contains { $0.category == .flour && $0.weightGrams > 0 }
            ? nil : "Add at least one flour ingredient"
    }
    private var stagesError: String? {
        draft.stages.isEmpty ? "Add at least one stage" : nil
    }
    private var weightsError: String? {
        let bad = draft.ingredients.contains { $0.weightGrams < 0 }
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
                metadataSection
                if let msg = titleError, triedSave {
                    Section { Text(msg).font(.caption).foregroundStyle(Theme.warm700) }
                }
                ingredientsSection
                if let msg = flourError, triedSave {
                    Section { Text(msg).font(.caption).foregroundStyle(Theme.warm700) }
                }
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
    }

    // MARK: Sections

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
            TextField("Source URL (optional)", text: $sourceURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !sourceURL.isEmpty {
                TextField("Source name (e.g. “King Arthur”)", text: $sourceName)
            }
        }
    }

    @ViewBuilder
    private var ingredientsSection: some View {
        Section {
            ForEach($draft.ingredients) { $ing in
                IngredientRow(ingredient: $ing)
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
            Text("Ingredients")
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
        // Drop blank-name ingredients the user added but never filled in.
        snap.ingredients = snap.ingredients.filter {
            !$0.name.trimmingCharacters(in: .whitespaces).isEmpty || $0.weightGrams > 0
        }
        // Total dough weight is the sum of ingredient weights.
        snap.totalDoughGrams = snap.ingredients.reduce(0) { $0 + $1.weightGrams }
        // Re-derive per-ingredient baker's % from flour total.
        let flour = snap.ingredients
            .filter { $0.category == .flour }
            .reduce(0.0) { $0 + $1.weightGrams }
        if flour > 0 {
            snap.ingredients = snap.ingredients.map { ing in
                var i = ing
                i.bakersPct = ing.weightGrams / flour * 100
                return i
            }
        }
        // And the recipe-level percentages from the ingredient totals.
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
                TextField("0", value: $ingredient.weightGrams, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("g").foregroundStyle(.secondary)
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

            HStack {
                TextField("0", value: $stage.durationMin, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text("min").foregroundStyle(.secondary)
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

#Preview("New recipe") {
    RecipeEditorScreen(
        state: AppState(persistence: PersistenceController(filename: "preview-editor.json")),
        editingRecipeId: nil
    )
}
