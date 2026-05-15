import Foundation
import UIKit

// Stage 24 (haiku.md Tier 1.2) — Cloud AI starter assessment. Mirrors
// `CrumbDiagnosis`: take an image + a small structured context, send
// to Claude Haiku, decode to `StarterAssessment`. Nil-return on any
// failure so the caller can fall through to neutral copy.

enum StarterHealthCheck {

    /// Pinned per haiku.md "Versioning" — Starter's eval set is
    /// independent from the crumb diagnostic, so upgrades happen
    /// independently.
    static let model = "claude-haiku-4-5-20251001"

    static func assess(image: UIImage, context: StarterContext) async -> StarterAssessment? {
        guard RemoteAIClient.isConfigured else { return nil }

        let payload = RemoteAIClient.ImagePayload(uiImage: image)
        guard !payload.jpegData.isEmpty else { return nil }

        let userText = """
        Starter context: \(context.promptSummary)

        Assess this sourdough starter's state from the photo and
        context, then recommend the next action. Return ONLY the
        JSON object per the schema. If the photo isn't a starter
        jar / vessel (or is too dark / blurry to read), return
        state "unknown" with confidence below 0.5.
        """

        do {
            let response: AssessmentResponse = try await RemoteAIClient.generate(
                model: model,
                systemPrompt: systemPrompt,
                userText: userText,
                images: [payload],
                outputType: AssessmentResponse.self,
                maxTokens: 700
            )
            return response.make()
        } catch {
            return nil
        }
    }

    private static let systemPrompt: String = """
    You are a sourdough-starter assessor. The user sends one photo of
    their starter jar (or vessel) plus a context summary (hours since
    last feed, kitchen temperature, storage). Return a single
    structured assessment naming the starter's state and what to do
    next.

    Allowed state values (use the rawValue exactly):
      - "peak"     — at peak rise. Domed surface, even small-to-
                      medium bubbles, springy. Ideal for an active
                      sourdough bake.
      - "prePeak"  — still rising. Climbing the jar walls but the
                      surface hasn't domed yet.
      - "postPeak" — past peak. Surface flat or sunken, large
                      open craters, smell sharp. Use soon, fridge,
                      or feed.
      - "hungry"   — flat, very few bubbles, hooch on top. Needs
                      feeding before it's bake-ready.
      - "sluggish" — bubbles small / sparse despite hours at room
                      temp. Cold kitchen, weak culture, or off
                      feed ratio.
      - "unknown"  — photo or context don't support a call.

    Allowed suggestedAction values:
      - "useNow"         — bake with it now.
      - "refrigerate"    — park it; you're not baking soon.
      - "feedNow"        — refresh to wake it up.
      - "wait"           — let it keep going. Pair with
                            `waitHours` (decimal hours).
      - "bringToCounter" — wake from fridge.

    Output JSON schema (emit every key; omit only `waitHours` when
    the action isn't "wait"):
    {
      "state": "<one of the state values>",
      "suggestedAction": "<one of the action values>",
      "waitHours": <number, only when suggestedAction is "wait">,
      "explanation": "<one or two sentences naming the visual cues>",
      "confidence": <number between 0.0 and 1.0>
    }

    Rules:
      1. Be calibrated. Below 0.7 confidence the UI shows neutral
         copy instead of your verdict — don't bluff to fill that
         gap.
      2. Anchor `explanation` in observable cues: dome shape, jar
         level vs. feed line, bubble pattern, smell signs visible
         as froth.
      3. Don't restate the context as if it were observation.
      4. Return ONLY the JSON. No markdown fence.
    """

    private struct AssessmentResponse: Decodable {
        let state: String
        let suggestedAction: String
        let waitHours: Double?
        let explanation: String
        let confidence: Double

        func make() -> StarterAssessment? {
            guard let s = StarterState(rawValue: state) else { return nil }
            guard let action = StarterAction(rawValue: suggestedAction) else { return nil }
            let clamped = max(0, min(1, confidence))
            return StarterAssessment(
                state: s,
                suggestedAction: action,
                waitHours: action == .wait ? waitHours.map { max(0, $0) } : nil,
                explanation: explanation,
                confidence: clamped,
                producedAt: Date()
            )
        }
    }
}
