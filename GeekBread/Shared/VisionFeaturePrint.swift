import Foundation
import Vision
import UIKit

// Stage 24a — Apple's `VNGenerateImageFeaturePrintRequest` produces a
// 2048-dimensional embedding for any image. Two prints can be compared
// via `computeDistance(_:to:)` which returns a Float (lower = more
// similar visually). This is the honest backbone of the Diagnose
// screen's "which past bake does this crumb look most like?" answer —
// no bundled VLM, no claims of detecting underproofing, just a
// comparison the user can verify against their own ratings.
//
// Inference is cheap (~30–80ms per image on Apple Silicon) and runs on
// the Neural Engine when available. We compute on-the-fly per Diagnose
// run rather than caching — typical journals are <50 entries, so the
// total run takes a few seconds.

enum VisionFeaturePrint {

    /// Compute the feature-print embedding for the given image. Off-main
    /// (Vision is happy on a background queue) so callers can `await` from
    /// any context. Returns nil when Vision can't process the image (e.g.
    /// a malformed JPEG).
    static func compute(for image: UIImage) async -> VNFeaturePrintObservation? {
        guard let cgImage = image.cgImage else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> VNFeaturePrintObservation? in
            let request = VNGenerateImageFeaturePrintRequest()
            // Scale-fill matches the visual framing in the recipe / journal
            // UI (photos are clipped to fit the photo strip), so two photos
            // of the same crumb composed differently still embed close.
            request.imageCropAndScaleOption = .scaleFill
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
                return request.results?.first
            } catch {
                return nil
            }
        }.value
    }

    /// Distance between two prints. Lower = more visually similar. Returns
    /// `Float.greatestFiniteMagnitude` when the comparison itself errors,
    /// so callers can treat that as "no match."
    static func distance(_ lhs: VNFeaturePrintObservation,
                          _ rhs: VNFeaturePrintObservation) -> Float {
        var d: Float = .greatestFiniteMagnitude
        do {
            try lhs.computeDistance(&d, to: rhs)
        } catch {
            return .greatestFiniteMagnitude
        }
        return d
    }

    /// Map a Vision distance to a 0–100 similarity percentage. Empirically
    /// distances cluster in the 0.0–2.0 range for typical photo pairs;
    /// 0.0 ≈ identical, 2.0+ ≈ no shared features. Linear mapping over
    /// [0, 2] is honest enough — the UI shows this as "X% similar" with
    /// a verb that admits it's a comparison heuristic, not a diagnosis.
    static func similarityPercent(distance: Float) -> Int {
        let raw = (1.0 - distance / 2.0) * 100.0
        return max(0, min(100, Int(raw.rounded())))
    }
}
