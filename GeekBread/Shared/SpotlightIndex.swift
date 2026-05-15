import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

// Stage 27 — Native iPad citizenship. Indexes every Recipe in
// `state.recipes` into Core Spotlight so recipes appear in the iPad's
// system search and Siri suggestions. Tapping a result opens the app to
// that recipe via the `recipe-<id>` activity type, which `GeekBreadApp`
// resolves and routes through `AppState.openRecipe`.
//
// Re-indexing is cheap (a few dozen items) — we rebuild the whole index on
// every recipe-list change rather than diffing additions/removals. The
// `domainIdentifier` lets us scope `deleteSearchableItems` to our own
// records when the user runs "Start over".

enum SpotlightIndex {

    /// Activity type for tap-from-Spotlight, also used by Handoff. The
    /// `userInfo["recipeId"]` carries the routing payload.
    static let activityType = "com.monty.geekbread.app.viewing-recipe"

    /// Spotlight domain scope so reset operations only nuke our items.
    private static let domain = "recipes"

    /// Replace every previously-indexed recipe with the current list.
    /// Idempotent — calling repeatedly with the same recipes leaves
    /// Spotlight in the same state.
    static func index(_ recipes: [Recipe]) {
        let items = recipes.map { recipe -> CSSearchableItem in
            let attrs = CSSearchableItemAttributeSet(contentType: UTType.content)
            attrs.title = recipe.title
            attrs.contentDescription = "\(recipe.breadType.rawValue) · \(recipe.timeToBake)"
            // Keyword search includes the bread type + every tag + a few
            // ingredient names so "sourdough" / "rye" / "tangzhong" / etc.
            // surface the right recipe without an exact-title match.
            var keywords: [String] = [recipe.breadType.rawValue]
            keywords.append(contentsOf: recipe.tags)
            keywords.append(contentsOf: recipe.ingredients
                .filter { $0.category == .flour }
                .map(\.name))
            attrs.keywords = keywords

            let item = CSSearchableItem(
                uniqueIdentifier: recipe.id,
                domainIdentifier: domain,
                attributeSet: attrs
            )
            return item
        }

        CSSearchableIndex.default().deleteSearchableItems(
            withDomainIdentifiers: [domain]
        ) { _ in
            // Index even if the delete failed — the new items overwrite
            // any old ones with the same uniqueIdentifier.
            CSSearchableIndex.default().indexSearchableItems(items) { _ in }
        }
    }

    /// Wipe every indexed recipe. Called from `state.startOver()` so the
    /// system search doesn't surface stale entries after a reset.
    static func clear() {
        CSSearchableIndex.default().deleteSearchableItems(
            withDomainIdentifiers: [domain]
        ) { _ in }
    }

    /// Build the NSUserActivity used by Handoff + Spotlight result tap. The
    /// activity carries the recipe id in `userInfo` and identifies itself
    /// as `eligibleForSearch` + `eligibleForHandoff` so the same payload
    /// surfaces in both surfaces.
    static func userActivity(for recipe: Recipe) -> NSUserActivity {
        let activity = NSUserActivity(activityType: activityType)
        activity.title = recipe.title
        activity.userInfo = ["recipeId": recipe.id]
        activity.requiredUserInfoKeys = ["recipeId"]
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        // No `webpageURL` — NSUserActivity requires http/https there and
        // throws on a custom scheme. Deep-link routing reads `userInfo`
        // via `recipeId(from:)` already; the custom scheme lives in
        // AppState.handleIncomingURL. Re-introduce a webpageURL only
        // when Universal Links are wired (Phase F).
        return activity
    }

    /// Extract a recipe id from an incoming NSUserActivity payload, handling
    /// both our own `viewing-recipe` activities and Core Spotlight item
    /// taps (`CSSearchableItemActionType`).
    static func recipeId(from activity: NSUserActivity) -> String? {
        if activity.activityType == activityType,
           let id = activity.userInfo?["recipeId"] as? String {
            return id
        }
        if activity.activityType == CSSearchableItemActionType,
           let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
            return id
        }
        return nil
    }
}
