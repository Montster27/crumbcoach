import Foundation
import UIKit

// Stage 24 (haiku.md Tier 1.1) — replaces the long-term on-device VLM
// plan with a Haiku vision call. Takes a crumb photo + the bake's
// recipe context and returns a typed `Diagnosis`. The DiagnosticScreen
// uses this BEFORE the 24a similarity card; on low confidence (<70%)
// or any error, the similarity card promotes to primary and the
// honesty copy admits the diagnosis didn't run.
//
// The output is honest by construction:
//   - The model is instructed to return `unknown` + confidence <0.7
//     when the photo lacks the cues a diagnosis needs (out of focus,
//     no crumb visible, decorative shot).
//   - The label set is fixed; we reject any string outside it.
//   - We never invent a label client-side from heuristics — the
//     fallback is the 24a similarity card, not a synthesized
//     "probably underproofed".

enum CrumbDiagnosis {

    /// Pinned per haiku.md "Versioning" — each surface upgrades on its
    /// own eval pass, not as a global swap.
    static let model = "claude-haiku-4-5-20251001"

    /// Run a diagnosis against a single crumb image. Returns nil on
    /// network failure, decode failure, or when the model declined to
    /// classify the image. The caller (DiagnosticScreen) treats nil
    /// identically to a low-confidence response — fall back to the
    /// similarity card.
    static func diagnose(image: UIImage, context: BakeContext) async -> Diagnosis? {
        guard RemoteAIClient.isConfigured else { return nil }

        let payload = RemoteAIClient.ImagePayload(uiImage: image)
        guard !payload.jpegData.isEmpty else { return nil }

        let userText = """
        Bake context: \(context.promptSummary)

        Diagnose the crumb structure in this photo.

        Return ONLY a JSON object matching the schema. No prose, no
        markdown fence. If the photo isn't a crumb shot (decorative
        shot, out of focus, no slice visible), return primaryLabel
        "unknown" with confidence below 0.5.
        """

        do {
            let response: DiagnosisResponse = try await RemoteAIClient.generate(
                model: model,
                systemPrompt: systemPrompt,
                userText: userText,
                images: [payload],
                outputType: DiagnosisResponse.self,
                maxTokens: 800
            )
            return response.makeDiagnosis()
        } catch {
            return nil
        }
    }

    // MARK: - System prompt

    private static let systemPrompt: String = """
    You are a bread crumb diagnostician. The user sends one photo of a
    sliced loaf or a close-up of its crumb, plus a short bake-context
    summary (hydration, bulk time, kitchen temperature, retard, bake
    temp / time). Return a single structured diagnosis.

    Allowed primary labels (use the rawValue exactly):
      - "underproofed"   — tight, dense, gummy interior. Often paired
                            with poor oven spring.
      - "overproofed"    — collapsed structure, large irregular
                            craters next to dense bands, gummy.
      - "underbaked"     — wet / doughy patches, pale crumb,
                            cell walls still tacky.
      - "overferment"    — sour, alcohol-smelling crumb (you'll have
                            to infer this from extreme open cells +
                            collapsed shape).
      - "tightCrumb"     — uniformly small, dense cells; often from
                            stiff dough or poor fermentation.
      - "openCrumb"      — large, irregular, shiny cell walls;
                            high-hydration target hit.
      - "even"           — uniform, medium cells; well-proofed.
      - "unknown"        — the photo doesn't show enough crumb to
                            decide. Use this whenever you'd
                            otherwise have to guess.

    Output JSON schema (omit nothing — emit every key):
    {
      "primaryLabel": "<one of the labels above>",
      "explanation": "<one or two sentences naming the visual cues you used>",
      "confidence": <number between 0.0 and 1.0>,
      "suggestions": ["<short concrete next-bake action>", ...],
      "secondaryLabels": { "<label>": <probability>, ... }
    }

    Rules:
      1. Be calibrated. If you wouldn't bet your reputation on a
         label, the confidence is below 0.7. Bakers will change
         their schedule based on this number — never bluff.
      2. Anchor the explanation in what's visible: cell size,
         distribution, crust thickness, gum line, color. Don't
         restate the bake context as if it were observation.
      3. `secondaryLabels` should list the next 1–2 most plausible
         labels and their probabilities. The whole distribution
         (primary + secondaries) doesn't have to sum to 1.0.
      4. Suggestions must be specific ("shorten bulk by 30 min at
         24 °C", "raise oven 10 °C and add 5 min", "lower
         hydration 3% next bake"). Not generic ("try again").
      5. Return ONLY the JSON. No markdown fence.
    """

    // MARK: - Response shape

    /// Wire shape the model emits. We map to the storage `Diagnosis`
    /// type after validating the label string and clamping confidence
    /// into [0, 1].
    private struct DiagnosisResponse: Decodable {
        let primaryLabel: String
        let explanation: String
        let confidence: Double
        let suggestions: [String]
        let secondaryLabels: [String: Double]?

        func makeDiagnosis() -> Diagnosis? {
            guard let label = DiagnosisLabel(rawValue: primaryLabel) else {
                return nil
            }
            let clamped = max(0, min(1, confidence))
            return Diagnosis(
                primaryLabel: label,
                explanation: explanation,
                confidence: clamped,
                suggestions: suggestions,
                secondaryLabels: (secondaryLabels ?? [:]).filter { key, _ in
                    DiagnosisLabel(rawValue: key) != nil
                },
                producedAt: Date()
            )
        }
    }
}
