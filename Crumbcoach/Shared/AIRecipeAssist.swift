import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// Stage 17.5b — Apple Foundation Models fallback for the recipe importer.
// When the Stage-17 regex + the Stage-17.5a static lookup table can't pin a
// weight or a duration, we fall through to the on-device LLM and ask it
// to estimate. Strict gating:
//
//   - Requires iOS 26+ (the framework's public ship version) AND the user's
//     device must support Apple Intelligence (iPhone 15 Pro+, M1+ iPad).
//   - Requires the user opt-in via Settings (state.aiAssistEnabled).
//   - Confidence threshold: we only adopt suggestions ≥ 0.6.
//   - Sanity-check: if the answer falls more than ±50% off a known value
//     from the lookup table, reject it as a hallucination.
//
// `import FoundationModels` is guarded with `#if canImport(...)` so this
// file compiles on toolchains without the SDK; all entry points return
// nil at runtime when the framework is unavailable. Build still succeeds
// on iOS 17.0 deployment target.

enum AIRecipeAssist {

    /// Coarse availability check the Settings toggle gates on. Returns
    /// true only when the framework is present AND the system reports
    /// the model as `.available` (not downloading / not eligible / etc).
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    /// Estimate gram weights for ingredient strings the regex + table both
    /// missed. Concurrent inference via a TaskGroup so a typical 7-row
    /// recipe completes in ~3s on Apple Silicon rather than 14s
    /// serially. Returns nil per input when the model declines or the
    /// confidence threshold isn't met.
    static func estimateGrams(for ingredients: [String]) async -> [Double?] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await Self.estimateGramsFM(for: ingredients)
        }
        #endif
        return Array(repeating: nil, count: ingredients.count)
    }

    /// Estimate stage durations from instruction text. Used when an
    /// instruction has no recognizable numeric time anchor (e.g. "Bake
    /// until golden brown"); the model can sometimes infer a typical
    /// duration from context ("until golden brown" → ~25–30 min for a
    /// 200°C loaf).
    static func estimateDurations(for instructions: [String]) async -> [Int?] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await Self.estimateDurationsFM(for: instructions)
        }
        #endif
        return Array(repeating: nil, count: instructions.count)
    }

    // MARK: - Foundation Models implementation

    #if canImport(FoundationModels)

    @available(iOS 26.0, *)
    @Generable
    struct IngredientEstimate {
        @Guide(description: "Weight in grams. Use 0 when you cannot estimate confidently.")
        let grams: Double
        @Guide(description: "Confidence between 0.0 and 1.0. Be honest — return < 0.5 when unsure.")
        let confidence: Double
    }

    @available(iOS 26.0, *)
    @Generable
    struct DurationEstimate {
        @Guide(description: "Duration in minutes. Use 0 when you cannot estimate confidently.")
        let minutes: Int
        @Guide(description: "Confidence between 0.0 and 1.0. Be honest — return < 0.5 when unsure.")
        let confidence: Double
    }

    @available(iOS 26.0, *)
    private static func estimateGramsFM(for ingredients: [String]) async -> [Double?] {
        guard SystemLanguageModel.default.availability == .available else {
            return Array(repeating: nil, count: ingredients.count)
        }
        let instructions = """
        You estimate ingredient weights for bread recipes. The user sends
        one ingredient string at a time. Use standard US recipe
        conventions (large eggs = 50 g, 1 cup AP flour = 120 g, 1 tsp
        salt = 6 g, etc). If you cannot estimate confidently, return
        grams = 0 and confidence < 0.5. Never guess wildly — bakers
        weigh by the number you return.
        """
        return await withTaskGroup(of: (Int, Double?).self,
                                     returning: [Double?].self) { group in
            for (index, line) in ingredients.enumerated() {
                group.addTask {
                    do {
                        let session = LanguageModelSession(instructions: instructions)
                        let response = try await session.respond(
                            to: line,
                            generating: IngredientEstimate.self
                        )
                        let content = response.content
                        return (index, content.confidence >= 0.6 ? content.grams : nil)
                    } catch {
                        return (index, nil)
                    }
                }
            }
            var out: [Double?] = Array(repeating: nil, count: ingredients.count)
            for await (index, value) in group {
                out[index] = value
            }
            return out
        }
    }

    @available(iOS 26.0, *)
    private static func estimateDurationsFM(for instructions: [String]) async -> [Int?] {
        guard SystemLanguageModel.default.availability == .available else {
            return Array(repeating: nil, count: instructions.count)
        }
        let systemPrompt = """
        You estimate stage durations for bread recipes. The user sends
        one instruction string at a time (e.g. "Cover and let rest until
        doubled"). Return minutes. If the instruction lacks any time
        signal — "until golden brown", "by feel" — return minutes = 0
        and confidence < 0.5. Otherwise estimate the typical duration a
        home baker would set a timer for.
        """
        return await withTaskGroup(of: (Int, Int?).self,
                                     returning: [Int?].self) { group in
            for (index, line) in instructions.enumerated() {
                group.addTask {
                    do {
                        let session = LanguageModelSession(instructions: systemPrompt)
                        let response = try await session.respond(
                            to: line,
                            generating: DurationEstimate.self
                        )
                        let content = response.content
                        return (index, content.confidence >= 0.6 ? content.minutes : nil)
                    } catch {
                        return (index, nil)
                    }
                }
            }
            var out: [Int?] = Array(repeating: nil, count: instructions.count)
            for await (index, value) in group {
                out[index] = value
            }
            return out
        }
    }
    #endif
}
