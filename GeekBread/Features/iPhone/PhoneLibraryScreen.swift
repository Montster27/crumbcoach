import SwiftUI
import UIKit

// iPhone Library — 2-column recipe grid + system search + horizontally
// scrolling filter chips. Reuses the iPad `RecipeCard` and `SourceBadge`
// since those are public structs in Features/Library/LibraryScreen.swift
// and don't assume a particular column width.
//
// Recipe detail navigation pushes onto the Library tab's NavigationStack
// via a NavigationLink rather than syncing with `AppState.screen`. Deep
// links from Handoff/Spotlight that call `state.openRecipe(...)` will
// land on the Library tab today; full path-sync with state.screen is a
// follow-up.

struct PhoneLibraryScreen: View {
    var state: AppState
    @State private var search: String = ""
    @State private var filter: String = "all"
    @State private var editorOpen: Bool = false
    @State private var editorImportSeed: String? = nil
    @State private var showClipboardEmptyAlert: Bool = false

    // Same canonical filter list as the iPad shell.
    private let filters: [(String, String)] = [
        ("all",       "All"),
        ("sourdough", "Sourdough"),
        ("yeasted",   "Lean yeasted"),
        ("enriched",  "Enriched"),
        ("rye",       "Rye"),
        ("favorites", "Family favorites"),
        ("quick",     "Under 6 hours"),
        ("never",     "Never baked"),
    ]

    private var filtered: [Recipe] {
        state.recipes.filter { r in
            if !search.isEmpty {
                let q = search.lowercased()
                if !r.title.lowercased().contains(q),
                   !r.breadType.rawValue.lowercased().contains(q) { return false }
            }
            switch filter {
            case "all":       return true
            case "sourdough": return r.breadType == .sourdough
            case "yeasted":   return r.breadType == .leanYeasted
            case "enriched":  return r.breadType == .enriched
            case "rye":       return r.breadType == .rye
            case "quick":
                let h = Int(r.timeToBake.prefix(while: \.isNumber)) ?? 99
                return h <= 6
            case "never":     return r.lastBake == nil
            case "favorites": return (r.lastBake?.rating ?? 0) >= 5
            default:          return true
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PhoneTheme.cardSpacing) {
                // Filter chips — horizontal scroll on iPhone (the iPad
                // version wraps with FlowLayout; both work but horizontal
                // scroll keeps content density predictable on narrow
                // canvases).
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filters, id: \.0) { id, label in
                            TagPill(label: label, active: id == filter) { filter = id }
                        }
                    }
                    .padding(.horizontal, PhoneTheme.screenHPad)
                    .padding(.vertical, 2)
                }
                .padding(.horizontal, -PhoneTheme.screenHPad)

                // Stat line
                HStack(spacing: 14) {
                    statCount(state.recipes.count, "recipes")
                    if !filtered.isEmpty {
                        Text("·")
                            .font(Typography.ui(11))
                            .foregroundStyle(Theme.slate400)
                        Text("\(filtered.count) shown")
                            .font(Typography.ui(11.5))
                            .foregroundStyle(Theme.slate500)
                    }
                    Spacer()
                }

                if filtered.isEmpty {
                    PhoneLibraryEmpty(search: search, filter: filter, hasAnyRecipes: !state.recipes.isEmpty) {
                        editorOpen = true
                    }
                    .padding(.top, 24)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                        GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(filtered) { r in
                            NavigationLink {
                                PhoneRecipeDetailScreen(state: state, recipeId: r.id)
                            } label: {
                                RecipeCard(recipe: r, units: state.units) {
                                    // No-op — outer NavigationLink handles the push.
                                    // The RecipeCard's button action remains required
                                    // by its API but we drive navigation declaratively.
                                }
                                .allowsHitTesting(false)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, PhoneTheme.screenHPad)
            .padding(.top, PhoneTheme.screenVPad)
            .padding(.bottom, PhoneTheme.sectionSpacing)
        }
        .background(Theme.surface1)
        .searchable(text: $search, prompt: "Search recipes, ingredients…")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { editorOpen = true } label: {
                        Label("New recipe", systemImage: "plus")
                    }
                    Button { pasteURLFromClipboard() } label: {
                        Label("Paste URL from clipboard", systemImage: "link")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 19, weight: .medium))
                }
                .accessibilityLabel("Add recipe")
            }
        }
        .sheet(isPresented: $editorOpen, onDismiss: { editorImportSeed = nil }) {
            RecipeEditorScreen(state: state,
                               editingRecipeId: nil,
                               initialSourceURL: editorImportSeed)
        }
        .onAppear { openEditorIfPendingImport() }
        .onChange(of: state.pendingImportURL) { _, _ in
            openEditorIfPendingImport()
        }
        .alert("No URL on clipboard", isPresented: $showClipboardEmptyAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Copy a recipe URL (any http/https link), then tap Paste URL again — the editor will open with it pre-filled.")
        }
    }

    private func openEditorIfPendingImport() {
        guard let pending = state.pendingImportURL, !pending.isEmpty else { return }
        editorImportSeed = pending
        editorOpen = true
        state.pendingImportURL = nil
    }

    private func pasteURLFromClipboard() {
        let raw = (UIPasteboard.general.string ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty,
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            showClipboardEmptyAlert = true
            return
        }
        editorImportSeed = raw
        editorOpen = true
    }

    private func statCount(_ n: Int, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text("\(n)")
                .font(Typography.mono(12, weight: .semibold))
                .foregroundStyle(Theme.slate900)
            Text(label)
                .font(Typography.ui(11.5))
                .foregroundStyle(Theme.slate600)
        }
    }
}

// MARK: - Empty state

private struct PhoneLibraryEmpty: View {
    let search: String
    let filter: String
    let hasAnyRecipes: Bool
    let onAdd: () -> Void

    private var title: String {
        if !search.isEmpty { return "No matches" }
        if !hasAnyRecipes  { return "No recipes yet" }
        return "Nothing here"
    }

    private var blurb: String {
        if !search.isEmpty {
            return "Try a different search, or clear it to see all recipes."
        }
        if !hasAnyRecipes {
            return "Add your first recipe — paste a URL from the web, type one in manually, or share from Safari."
        }
        return "No recipes match the current filter. Tap All to see your full library."
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.primaryTint).frame(width: 56, height: 56)
                Image(systemName: "book.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.primary)
            }
            VStack(spacing: 6) {
                Text(title)
                    .font(Typography.display(20, weight: .medium))
                    .foregroundStyle(Theme.slate900)
                Text(blurb)
                    .font(Typography.ui(13))
                    .foregroundStyle(Theme.slate600)
                    .multilineTextAlignment(.center)
            }
            if !hasAnyRecipes {
                Button { onAdd() } label: {
                    Label("Add recipe", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .ccPrimary()
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
    }
}

// MARK: - Recipe detail (iPhone stub)

// Placeholder until a dedicated iPhone recipe detail lands. Renders the
// hero photo, title, key stats, stage list, and ingredient list — enough
// to be informative when tapped from the Library grid. The iPad version
// (RecipeDetailScreen) has more (editing, scheduler shortcuts, photo
// pinboard); those will arrive in a follow-up.

struct PhoneRecipeDetailScreen: View {
    var state: AppState
    let recipeId: String

    private var recipe: Recipe? { state.recipe(recipeId) }

    var body: some View {
        Group {
            if let recipe {
                content(recipe: recipe)
            } else {
                Text("Recipe not found")
                    .font(Typography.ui(14))
                    .foregroundStyle(Theme.slate500)
            }
        }
        .background(Theme.surface1)
        .navigationTitle(recipe?.title ?? "Recipe")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(recipe: Recipe) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PhoneTheme.cardSpacing) {
                ZStack(alignment: .bottomLeading) {
                    BreadPhoto(assetName: recipe.photo, kind: .crumb, height: 220)
                    LinearGradient(colors: [.clear, .black.opacity(0.65)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 220)
                    VStack(alignment: .leading, spacing: 6) {
                        SourceBadge(source: recipe.source)
                        Text(recipe.title)
                            .font(Typography.display(24, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: PhoneTheme.cardRadius, style: .continuous))

                // Stats grid
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        stat("Hydration", "\(Int(recipe.hydrationPct))%")
                        stat("Salt", String(format: "%.1f%%", recipe.saltPct))
                    }
                    HStack(spacing: 10) {
                        stat("Total dough",
                             CCFormat.weight(grams: recipe.totalDoughGrams, units: state.units))
                        stat("Time", recipe.timeToBake)
                    }
                }

                // Stages summary
                SurfaceCard(padding: EdgeInsets()) {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 2) {
                            Kicker("Stages")
                            Text("\(recipe.stages.count) steps")
                                .font(Typography.ui(11.5))
                                .foregroundStyle(Theme.slate500)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, PhoneTheme.cardPad)
                        .padding(.vertical, 12)

                        ForEach(Array(recipe.stages.enumerated()), id: \.offset) { idx, stage in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(idx + 1)")
                                    .font(Typography.mono(12, weight: .semibold))
                                    .foregroundStyle(Theme.slate500)
                                    .frame(width: 18, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stage.kind.rawValue)
                                        .font(Typography.ui(13, weight: .medium))
                                        .foregroundStyle(Theme.slate900)
                                    if let note = stage.note {
                                        Text(note)
                                            .font(Typography.ui(11.5))
                                            .foregroundStyle(Theme.slate500)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                Spacer(minLength: 0)
                                Text(CCFormat.stageDuration(stage))
                                    .font(Typography.mono(11.5))
                                    .foregroundStyle(Theme.slate500)
                            }
                            .padding(.horizontal, PhoneTheme.cardPad)
                            .padding(.vertical, 10)
                            .overlay(alignment: .top) {
                                if idx > 0 { Rectangle().fill(Theme.border1).frame(height: 1) }
                            }
                        }
                    }
                }

                // Ingredients
                SurfaceCard(padding: EdgeInsets()) {
                    VStack(alignment: .leading, spacing: 0) {
                        Kicker("Ingredients")
                            .padding(.horizontal, PhoneTheme.cardPad)
                            .padding(.top, 12)
                        ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { idx, ing in
                            HStack {
                                Text(ing.name)
                                    .font(Typography.ui(13))
                                    .foregroundStyle(Theme.slate800)
                                Spacer()
                                Text(CCFormat.weight(grams: ing.weightGrams, units: state.units))
                                    .font(Typography.mono(12, weight: .semibold))
                                    .foregroundStyle(Theme.slate900)
                            }
                            .padding(.horizontal, PhoneTheme.cardPad)
                            .padding(.vertical, 10)
                            .overlay(alignment: .top) {
                                if idx > 0 { Rectangle().fill(Theme.border1).frame(height: 1) }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
            .padding(.horizontal, PhoneTheme.screenHPad)
            .padding(.top, PhoneTheme.screenVPad)
            .padding(.bottom, PhoneTheme.sectionSpacing)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Kicker(label, size: 10)
            Text(value)
                .font(Typography.mono(15, weight: .semibold))
                .foregroundStyle(Theme.slate900)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PhoneTheme.cardPad)
        .background(Color.white,
                    in: RoundedRectangle(cornerRadius: PhoneTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PhoneTheme.cardRadius, style: .continuous)
                .stroke(Theme.border1, lineWidth: 1)
        )
    }
}

#Preview("Phone Library") {
    NavigationStack {
        PhoneLibraryScreen(state: AppState(persistence: PersistenceController(filename: "preview-phone-library.json")))
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
    }
}
