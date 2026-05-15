import Foundation

// Seed journal entries — ported from JOURNAL[] in data.jsx. Each entry has
// a real `bakedAt` Date computed as N-days-ago from the seed reference.

enum SampleJournal {
    private static func daysAgo(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -n, to: Date()) ?? Date()
    }

    static let all: [JournalEntry] = [
        JournalEntry(id: "j1", recipeId: "country",  bakedAt: daysAgo(2),  rating: 5,
                     hydrationPct: 75, bulkMinutes: 315, kitchenC: 22,
                     note: "Best crumb yet. Extended bulk paid off.", photoAsset: "crumb_open",  diagnosis: "Well proofed"),
        JournalEntry(id: "j2", recipeId: "shokupan", bakedAt: daysAgo(7),  rating: 5,
                     hydrationPct: 70, bulkMinutes: 90,  kitchenC: 23,
                     note: "Tangzhong tender. Holding 4 days.",       photoAsset: nil,           diagnosis: "Optimal"),
        JournalEntry(id: "j3", recipeId: "country",  bakedAt: daysAgo(5),  rating: 3,
                     hydrationPct: 75, bulkMinutes: 255, kitchenC: 21,
                     note: "Slightly tight crumb at base.",            photoAsset: "crumb_dense", diagnosis: "Underproofed bulk"),
        JournalEntry(id: "j4", recipeId: "rye",      bakedAt: daysAgo(9),  rating: 4,
                     hydrationPct: 88, bulkMinutes: 720, kitchenC: 22,
                     note: "Dense as intended. Caraway forward.",      photoAsset: nil,           diagnosis: "On target"),
        JournalEntry(id: "j5", recipeId: "country",  bakedAt: daysAgo(14), rating: 4,
                     hydrationPct: 75, bulkMinutes: 270, kitchenC: 22,
                     note: "Good ear, slightly tight base.",           photoAsset: nil,           diagnosis: "Edge of underproof"),
        JournalEntry(id: "j6", recipeId: "focaccia", bakedAt: daysAgo(13), rating: 5,
                     hydrationPct: 82, bulkMinutes: 540, kitchenC: 21,
                     note: "Big open holes, crispy bottom.",           photoAsset: nil,           diagnosis: "Well proofed"),
    ]
}
