import Foundation

// Seed journal entries — ported from JOURNAL[] in data.jsx.

enum SampleJournal {
    static let all: [JournalEntry] = [
        JournalEntry(id: "j1", recipeId: "country",  date: "Tue", rating: 5, hydrationPct: 75, bulkMinutes: 315, kitchenC: 22,
                     note: "Best crumb yet. Extended bulk paid off.", photoAsset: "crumb_open",  diagnosis: "Well proofed"),
        JournalEntry(id: "j2", recipeId: "shokupan", date: "Sun", rating: 5, hydrationPct: 70, bulkMinutes: 90,  kitchenC: 23,
                     note: "Tangzhong tender. Holding 4 days.",       photoAsset: nil,           diagnosis: "Optimal"),
        JournalEntry(id: "j3", recipeId: "country",  date: "Fri", rating: 3, hydrationPct: 75, bulkMinutes: 255, kitchenC: 21,
                     note: "Slightly tight crumb at base.",            photoAsset: "crumb_dense", diagnosis: "Underproofed bulk"),
        JournalEntry(id: "j4", recipeId: "rye",      date: "Wed", rating: 4, hydrationPct: 88, bulkMinutes: 720, kitchenC: 22,
                     note: "Dense as intended. Caraway forward.",      photoAsset: nil,           diagnosis: "On target"),
        JournalEntry(id: "j5", recipeId: "country",  date: "Sun", rating: 4, hydrationPct: 75, bulkMinutes: 270, kitchenC: 22,
                     note: "Good ear, slightly tight base.",           photoAsset: nil,           diagnosis: "Edge of underproof"),
        JournalEntry(id: "j6", recipeId: "focaccia", date: "Sat", rating: 5, hydrationPct: 82, bulkMinutes: 540, kitchenC: 21,
                     note: "Big open holes, crispy bottom.",           photoAsset: nil,           diagnosis: "Well proofed"),
    ]
}
