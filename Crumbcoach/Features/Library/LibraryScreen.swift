import SwiftUI
import UIKit

// Recipe library — search + filter chips + 3-column grid of recipe cards.

struct LibraryScreen: View {
    var state: AppState
    @State private var search: String = ""
    @State private var filter: String = "all"
    @State private var editorOpen: Bool = false
    /// URL seed for the editor when the user lands here via a
    /// `crumbcoach://import?url=…` deep link from the share extension,
    /// or via the toolbar's "Paste URL" button.
    @State private var editorImportSeed: String? = nil
    @State private var showClipboardEmptyAlert: Bool = false

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

    var filtered: [Recipe] {
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

    var sourceTotals: (original: Int, linked: Int) {
        let o = state.recipes.filter { $0.source.kindKey == "original" }.count
        let l = state.recipes.filter { $0.source.kindKey == "linked" }.count
        return (o, l)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Search row
            HStack(spacing: 10) {
                ZStack(alignment: .leading) {
                    HStack {
                        CCIconView(icon: .search, size: 16, color: Theme.slate400)
                            .padding(.leading, 14)
                        TextField("Search recipes, ingredients, source…", text: $search)
                            .font(Typography.ui(14))
                            .padding(.vertical, 11)
                            .padding(.trailing, 14)
                    }
                }
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.border1, lineWidth: 1)
                )

                Button(action: { pasteURLFromClipboard() }) {
                    Label("Paste URL", systemImage: "link")
                }
                .ccSecondary()
                Button(action: { editorOpen = true }) { Label("New recipe", systemImage: "plus") }
                    .ccPrimary()
            }

            // Source totals
            HStack(spacing: 24) {
                statCount(state.recipes.count, "recipes")
                statCount(sourceTotals.original, "CrumbCoach originals")
                statCount(sourceTotals.linked, "linked from authors")
                Spacer()
                Text("Sorted by recently baked")
                    .font(Typography.ui(12))
                    .foregroundStyle(Theme.slate500)
            }
            .padding(.bottom, 14)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.border1).frame(height: 1)
            }

            // Filter chips
            FlowingChips(items: filters, active: filter) { id in filter = id }

            // Grid
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16)], spacing: 16) {
                ForEach(filtered) { r in
                    RecipeCard(recipe: r, units: state.units) { state.openRecipe(r.id) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            Text("Copy a recipe URL (any http/https link), then tap Paste URL again — the editor will open with it pre-filled and Import does the rest.")
        }
    }

    /// Drain `state.pendingImportURL` (set by the deep-link handler) and
    /// present the editor with that URL seeded. Idempotent — the seed
    /// clears via `onDismiss` so a second share doesn't reuse stale state.
    private func openEditorIfPendingImport() {
        guard let pending = state.pendingImportURL, !pending.isEmpty else { return }
        editorImportSeed = pending
        editorOpen = true
        state.pendingImportURL = nil
    }

    /// Read the system pasteboard, validate it looks like an http(s) URL,
    /// and seed the editor with it. If the clipboard is empty or holds
    /// something that isn't a URL, show an explanatory alert rather than
    /// silently opening a blank editor — "Paste URL" doing nothing is
    /// confusing.
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
                .font(Typography.mono(13, weight: .semibold))
                .foregroundStyle(Theme.slate900)
            Text(label).font(Typography.ui(13)).foregroundStyle(Theme.slate600)
        }
    }
}

// MARK: - Filter chip flow

struct FlowingChips: View {
    let items: [(String, String)]
    let active: String
    let onSelect: (String) -> Void
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.0) { id, label in
                TagPill(label: label, active: id == active) { onSelect(id) }
            }
        }
    }
}

// Simple flow layout for wrapping chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}

// MARK: - Recipe card (grid tile)

struct RecipeCard: View {
    let recipe: Recipe
    let units: Units
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    BreadPhoto(assetName: recipe.photo, kind: .crumb, height: 156)
                    SourceBadge(source: recipe.source)
                        .padding(10)
                    if let last = recipe.lastBake {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                HStack(spacing: 4) {
                                    StarRating(rating: last.rating, size: 9)
                                    Text(last.whenDisplay)
                                        .font(Typography.ui(11))
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.7), in: Capsule())
                                .padding(10)
                            }
                        }
                    }
                }
                .frame(height: 156)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous).trim(from: 0, to: 1))

                VStack(alignment: .leading, spacing: 4) {
                    Text(recipe.title)
                        .font(Typography.display(18, weight: .medium))
                        .foregroundStyle(Theme.slate900)
                    Text("\(recipe.breadType.rawValue) · \(recipe.timeToBake)")
                        .font(Typography.ui(11.5))
                        .foregroundStyle(Theme.slate500)
                    HStack(spacing: 14) {
                        statBlock("\(Int(recipe.hydrationPct))%", "hyd.")
                        statBlock(String(format: "%.1f%%", recipe.saltPct), "salt")
                        statBlock(CCFormat.weightValue(grams: recipe.totalDoughGrams, units: units),
                                  "\(units.shortLabel) · \(recipe.loafCount)")
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border1, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func statBlock(_ value: String, _ label: String) -> some View {
        HStack(spacing: 2) {
            Text(value).font(Typography.mono(12, weight: .semibold)).foregroundStyle(Theme.slate700)
            Text(label).font(Typography.ui(11)).foregroundStyle(Theme.slate500)
        }
    }
}

struct SourceBadge: View {
    let source: RecipeSource
    var body: some View {
        switch source {
        case .original:
            Text("CRUMBCOACH")
                .font(Typography.ui(10.5, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.85), in: Capsule())
        case .linked(_, let label, _):
            HStack(spacing: 6) {
                CCIconView(icon: .link, size: 11, color: Theme.accent)
                Text(label).font(Typography.ui(11, weight: .medium))
                    .foregroundStyle(Theme.slate700)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.95), in: Capsule())
        case .userCreated:
            Text("YOURS")
                .font(Typography.ui(10.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.accent, in: Capsule())
        case .photoScanned:
            Text("SCANNED")
                .font(Typography.ui(10.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.warm700, in: Capsule())
        }
    }
}

#Preview("Library") {
    LibraryScreen(state: AppState(persistence: PersistenceController(filename: "preview-library.json")))
        .padding()
        .background(Theme.surface1)
        .frame(width: 1100, height: 800)
}
