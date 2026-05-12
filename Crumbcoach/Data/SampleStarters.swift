import Foundation

// Seed starters — Marisol's two starters from the prototype.

enum SampleStarters {
    static let all: [Starter] = [ruby, ozzy]

    static let ruby = Starter(
        id: "ruby",
        name: "Ruby",
        flourType: "White wheat",
        hydrationPct: 100,
        ageDesc: "2y 4mo",
        weightGrams: 180,
        state: "Peaked 2h ago",
        stateKind: .warn,
        storage: .counter,
        lastFeed: "8h ago",
        peakAt: "−2h 14m",
        nextFeed: "In 4h 12m",
        peakHeightPct: 162,
        riseHistory: [12, 18, 32, 48, 78, 110, 138, 152, 158, 162, 148, 130],
        feedings: [
            StarterFeeding(when: "Today 8:14 AM",     ratio: "1:5:5", ambientC: 23),
            StarterFeeding(when: "Yesterday 8:02 AM", ratio: "1:5:5", ambientC: 22),
            StarterFeeding(when: "Sun 8:30 AM",       ratio: "1:1:1", ambientC: 22),
        ]
    )

    static let ozzy = Starter(
        id: "ozzy",
        name: "Ozzy",
        flourType: "Whole rye",
        hydrationPct: 100,
        ageDesc: "11mo",
        weightGrams: 90,
        state: "Resting · fridge",
        stateKind: .info,
        storage: .fridge,
        lastFeed: "5 days ago",
        peakAt: "—",
        nextFeed: "In 2 days",
        peakHeightPct: 22,
        riseHistory: [0, 0, 0, 5, 8, 12, 15, 18, 20, 22, 22, 21],
        feedings: [
            StarterFeeding(when: "5 days ago", ratio: "1:3:3", ambientC: 22),
            StarterFeeding(when: "12 days ago", ratio: "1:3:3", ambientC: 21),
        ]
    )
}
