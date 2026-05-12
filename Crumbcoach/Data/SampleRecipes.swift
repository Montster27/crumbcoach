import Foundation

// Seed recipes — ported from bread-remix/project/data.jsx.
// Used as the local-bundled catalog before any user-created recipes exist.

enum SampleRecipes {

    static let all: [Recipe] = [
        country, baguette, focaccia, shokupan, ciabatta, rugbrod, brioche, bagel, hokkaido,
    ]

    // MARK: Country Sourdough — flagship sourdough, hero of the prototype
    static let country = Recipe(
        id: "country",
        title: "Country Sourdough",
        breadType: .sourdough,
        source: .original,
        photo: "bread_country",
        hydrationPct: 75, saltPct: 2.0, leavenPct: 20,
        totalDoughGrams: 1820, loafCount: 2,
        timeToBake: "18h overnight",
        tags: ["weekend", "open-crumb"],
        twinScald: false,
        preferments: [],
        ingredients: [
            Ingredient(name: "Bread flour",        category: .flour,  weightGrams: 800, bakersPct: 80),
            Ingredient(name: "Whole-wheat flour",  category: .flour,  weightGrams: 200, bakersPct: 20),
            Ingredient(name: "Water",              category: .liquid, weightGrams: 750, bakersPct: 75),
            Ingredient(name: "Levain (100% hyd.)", category: .leaven, weightGrams: 200, bakersPct: 20),
            Ingredient(name: "Fine sea salt",      category: .salt,   weightGrams:  20, bakersPct:  2),
        ],
        stages: [
            Stage(kind: .feedLevain,  durationMin: 360, temperatureC: 24, note: "1:5:5 build, 50g starter + 250g flour + 250g water"),
            Stage(kind: .autolyse,    durationMin: 60,  temperatureC: 24, note: "Flour + water rest"),
            Stage(kind: .mix,         durationMin: 15,  temperatureC: 24, note: "Add levain + salt, pinch through"),
            Stage(kind: .bulkFold,    durationMin: 270, temperatureC: 24, note: "4 sets of stretch & fold, 30 min apart"),
            Stage(kind: .preShape,    durationMin: 25,  temperatureC: 24, note: "Bench rest"),
            Stage(kind: .finalShape,  durationMin: 10,  temperatureC: 24, note: "Tight boule into banneton"),
            Stage(kind: .coldRetard,  durationMin: 720, temperatureC: 4,  note: "Overnight in fridge"),
            Stage(kind: .bake,        durationMin: 50,  temperatureC: 250, note: "Dutch oven, 20 lid on / 30 lid off"),
        ],
        lastBake: Recipe.LastBake(rating: 5, when: "3 days ago",
                                  note: "Best crumb yet — bulk extended to 5h15m")
    )

    // MARK: Classic Baguette — linked from King Arthur
    static let baguette = Recipe(
        id: "baguette",
        title: "Classic Baguette",
        breadType: .leanYeasted,
        source: .linked(url: "https://www.kingarthurbaking.com/recipes/classic-baguettes-recipe",
                        sourceName: "King Arthur", sourceLogo: nil),
        photo: "bread_baguette",
        hydrationPct: 72, saltPct: 1.9, leavenPct: 0.4,
        totalDoughGrams: 1040, loafCount: 3,
        timeToBake: "6h same-day",
        tags: ["weekday-evening"],
        twinScald: false,
        preferments: [],
        ingredients: [
            Ingredient(name: "Bread flour",   category: .flour,  weightGrams: 600,  bakersPct: 100),
            Ingredient(name: "Water",         category: .liquid, weightGrams: 432,  bakersPct: 72),
            Ingredient(name: "Salt",          category: .salt,   weightGrams: 11,   bakersPct: 1.9),
            Ingredient(name: "Instant yeast", category: .leaven, weightGrams: 2.4,  bakersPct: 0.4),
        ],
        stages: [
            Stage(kind: .mix,         durationMin: 10,  temperatureC: 24, note: "Combine until shaggy"),
            Stage(kind: .bulkFold,    durationMin: 180, temperatureC: 24, note: "3 folds at 30 min"),
            Stage(kind: .divide,      durationMin: 10,  temperatureC: 24),
            Stage(kind: .preShape,    durationMin: 25,  temperatureC: 24),
            Stage(kind: .finalShape,  durationMin: 10,  temperatureC: 24, note: "Couche, seam-up"),
            Stage(kind: .proof,       durationMin: 60,  temperatureC: 24),
            Stage(kind: .bake,        durationMin: 25,  temperatureC: 245, note: "Score x 5, steam"),
        ],
        lastBake: nil
    )

    // MARK: Overnight Focaccia — linked from The Perfect Loaf
    static let focaccia = Recipe(
        id: "focaccia",
        title: "Overnight Focaccia",
        breadType: .leanYeasted,
        source: .linked(url: "https://www.theperfectloaf.com/overnight-focaccia/",
                        sourceName: "The Perfect Loaf", sourceLogo: nil),
        photo: "bread_focaccia",
        hydrationPct: 82, saltPct: 2.0, leavenPct: 0.2,
        totalDoughGrams: 1430, loafCount: 1,
        timeToBake: "20h overnight",
        tags: ["holiday"],
        twinScald: false,
        preferments: [],
        ingredients: [
            Ingredient(name: "Bread flour",   category: .flour,  weightGrams: 750, bakersPct: 100),
            Ingredient(name: "Water",         category: .liquid, weightGrams: 615, bakersPct: 82),
            Ingredient(name: "Salt",          category: .salt,   weightGrams: 15,  bakersPct: 2),
            Ingredient(name: "Instant yeast", category: .leaven, weightGrams: 1.5, bakersPct: 0.2),
            Ingredient(name: "Olive oil",     category: .fat,    weightGrams: 50,  bakersPct: 7),
        ],
        stages: [
            Stage(kind: .mix,        durationMin: 12, temperatureC: 24, note: "Combine, no kneading"),
            Stage(kind: .bulkFold,   durationMin: 180, temperatureC: 22, note: "3 sets of folds"),
            Stage(kind: .coldRetard, durationMin: 720, temperatureC: 4,  note: "Overnight in pan"),
            Stage(kind: .finalProof, durationMin: 120, temperatureC: 24, note: "Come to room temp, dimple"),
            Stage(kind: .bake,       durationMin: 25,  temperatureC: 230, note: "Olive oil + flaky salt"),
        ],
        lastBake: Recipe.LastBake(rating: 4, when: "2 weeks ago", note: nil)
    )

    // MARK: Tangzhong Shokupan
    static let shokupan = Recipe(
        id: "shokupan",
        title: "Tangzhong Shokupan",
        breadType: .enriched,
        source: .linked(url: "https://www.theperfectloaf.com/japanese-milk-bread/",
                        sourceName: "Maurizio Leo", sourceLogo: nil),
        photo: "bread_shokupan",
        hydrationPct: 70, saltPct: 1.5, leavenPct: 1.0,
        totalDoughGrams: 1200, loafCount: 2,
        timeToBake: "7h same-day",
        tags: ["weekday"],
        twinScald: false,
        preferments: [
            Preferment(
                id: "tangzhong", name: "Tangzhong",
                technique: "1:5 cook to 65°C",
                prep: "Whisk flour + milk in a saucepan over medium heat to 65°C until pudding-thick. Cool.",
                flourPct: 6,
                ingredients: [
                    Ingredient(name: "Bread flour", category: .flour,  weightGrams: 48,  bakersPct: 6,  section: "tangzhong"),
                    Ingredient(name: "Whole milk",  category: .liquid, weightGrams: 240, bakersPct: 30, section: "tangzhong"),
                ]
            )
        ],
        ingredients: [
            Ingredient(name: "Bread flour",     category: .flour,  weightGrams: 752, bakersPct: 94,  section: "main"),
            Ingredient(name: "Whole milk",      category: .liquid, weightGrams: 180, bakersPct: 22.5, section: "main"),
            Ingredient(name: "Egg",             category: .liquid, weightGrams: 50,  bakersPct: 6.3, section: "main"),
            Ingredient(name: "Sugar",           category: .sweet,  weightGrams: 64,  bakersPct: 8,   section: "main"),
            Ingredient(name: "Sea salt",        category: .salt,   weightGrams: 12,  bakersPct: 1.5, section: "main"),
            Ingredient(name: "Instant yeast",   category: .leaven, weightGrams: 8,   bakersPct: 1.0, section: "main"),
            Ingredient(name: "Unsalted butter", category: .fat,    weightGrams: 56,  bakersPct: 7,   section: "main"),
        ],
        stages: [
            Stage(kind: .cookTangzhong, durationMin: 15,  temperatureC: 65,  note: "Cook to 65°C, cool", scaldRef: "tangzhong"),
            Stage(kind: .mix,           durationMin: 18,  temperatureC: 24,  note: "Combine tangzhong, milk, egg, dry"),
            Stage(kind: .addButter,     durationMin: 10,  temperatureC: 24,  note: "Window-pane stage"),
            Stage(kind: .bulk,          durationMin: 90,  temperatureC: 26,  note: "Until doubled"),
            Stage(kind: .divideShape,   durationMin: 20,  temperatureC: 24,  note: "4 rolls per loaf, tight cylinders"),
            Stage(kind: .finalProof,    durationMin: 75,  temperatureC: 28,  note: "85% of pan height"),
            Stage(kind: .bake,          durationMin: 35,  temperatureC: 180, note: "Cover for last 10 if browning fast"),
        ],
        lastBake: Recipe.LastBake(rating: 5, when: "1 week ago", note: nil)
    )

    // MARK: High-Hydration Ciabatta — linked from Foodgeek
    static let ciabatta = Recipe(
        id: "ciabatta",
        title: "High-Hydration Ciabatta",
        breadType: .leanYeasted,
        source: .linked(url: "https://foodgeek.dk/en/ciabatta-recipe/",
                        sourceName: "Foodgeek", sourceLogo: nil),
        photo: "bread_ciabatta",
        hydrationPct: 85, saltPct: 2.0, leavenPct: 0.3,
        totalDoughGrams: 980, loafCount: 4,
        timeToBake: "16h overnight",
        tags: ["weekend"],
        twinScald: false,
        preferments: [],
        ingredients: [
            Ingredient(name: "Bread flour",   category: .flour,  weightGrams: 500, bakersPct: 100),
            Ingredient(name: "Water",         category: .liquid, weightGrams: 425, bakersPct: 85),
            Ingredient(name: "Salt",          category: .salt,   weightGrams: 10,  bakersPct: 2),
            Ingredient(name: "Instant yeast", category: .leaven, weightGrams: 1.5, bakersPct: 0.3),
        ],
        stages: [
            Stage(kind: .mix,        durationMin: 12,  temperatureC: 24, note: "Combine, very wet"),
            Stage(kind: .bulkFold,   durationMin: 240, temperatureC: 22, note: "Coil folds every 30 min"),
            Stage(kind: .coldRetard, durationMin: 720, temperatureC: 4,  note: "Overnight"),
            Stage(kind: .divide,     durationMin: 20,  temperatureC: 22, note: "Generous flour"),
            Stage(kind: .finalProof, durationMin: 45,  temperatureC: 22),
            Stage(kind: .bake,       durationMin: 22,  temperatureC: 240, note: "Steam, slight bake stone"),
        ],
        lastBake: nil
    )

    // MARK: Danish Rugbrød — linked from Brian Lagerstrom
    static let rugbrod = Recipe(
        id: "rye",
        title: "Danish Rugbrød",
        breadType: .rye,
        source: .linked(url: "https://www.youtube.com/watch?v=", sourceName: "Brian Lagerstrom", sourceLogo: nil),
        photo: "bread_rye",
        hydrationPct: 88, saltPct: 1.8, leavenPct: 25,
        totalDoughGrams: 1600, loafCount: 1,
        timeToBake: "30h with seeds",
        tags: ["dense"],
        twinScald: false,
        preferments: [],
        ingredients: [
            Ingredient(name: "Rye flour",       category: .flour,  weightGrams: 600, bakersPct: 75),
            Ingredient(name: "Cracked rye",     category: .flour,  weightGrams: 200, bakersPct: 25),
            Ingredient(name: "Water",           category: .liquid, weightGrams: 704, bakersPct: 88),
            Ingredient(name: "Rye sour",        category: .leaven, weightGrams: 200, bakersPct: 25),
            Ingredient(name: "Sea salt",        category: .salt,   weightGrams: 14,  bakersPct: 1.8),
            Ingredient(name: "Sunflower seeds", category: .inclusion, weightGrams: 100, bakersPct: 12.5),
        ],
        stages: [
            Stage(kind: .mix,         durationMin: 12,  temperatureC: 24, note: "Mix until uniform paste"),
            Stage(kind: .bulk,        durationMin: 720, temperatureC: 22, note: "Long slow ferment"),
            Stage(kind: .finalShape,  durationMin: 10,  temperatureC: 22, note: "Into pullman pan"),
            Stage(kind: .finalProof,  durationMin: 240, temperatureC: 22, note: "Until cracks form"),
            Stage(kind: .bake,        durationMin: 90,  temperatureC: 180, note: "Long, low and slow"),
        ],
        lastBake: Recipe.LastBake(rating: 4, when: "3 weeks ago", note: nil)
    )

    // MARK: Butter Brioche
    static let brioche = Recipe(
        id: "brioche",
        title: "Butter Brioche",
        breadType: .enriched,
        source: .original,
        photo: "bread_brioche",
        hydrationPct: 50, saltPct: 1.5, leavenPct: 1.5,
        totalDoughGrams: 900, loafCount: 1,
        timeToBake: "10h same-day",
        tags: ["weekend"],
        twinScald: false,
        preferments: [],
        ingredients: [
            Ingredient(name: "Bread flour",     category: .flour,  weightGrams: 500, bakersPct: 100),
            Ingredient(name: "Whole milk",      category: .liquid, weightGrams: 100, bakersPct: 20),
            Ingredient(name: "Egg",             category: .liquid, weightGrams: 150, bakersPct: 30),
            Ingredient(name: "Sugar",           category: .sweet,  weightGrams:  60, bakersPct: 12),
            Ingredient(name: "Salt",            category: .salt,   weightGrams:   8, bakersPct: 1.5),
            Ingredient(name: "Instant yeast",   category: .leaven, weightGrams:   7.5, bakersPct: 1.5),
            Ingredient(name: "Unsalted butter", category: .fat,    weightGrams: 200, bakersPct: 40),
        ],
        stages: [
            Stage(kind: .mix,         durationMin: 20, temperatureC: 22, note: "Dough hook 8 min"),
            Stage(kind: .addButter,   durationMin: 25, temperatureC: 22, note: "Cubed cold butter, slowly"),
            Stage(kind: .bulk,        durationMin: 90, temperatureC: 24),
            Stage(kind: .coldRetard,  durationMin: 360, temperatureC: 4, note: "Firms up for shaping"),
            Stage(kind: .divideShape, durationMin: 20, temperatureC: 22, note: "8 rolls or 1 loaf"),
            Stage(kind: .finalProof,  durationMin: 120, temperatureC: 24),
            Stage(kind: .bake,        durationMin: 30,  temperatureC: 180, note: "Egg wash"),
        ],
        lastBake: nil
    )

    // MARK: NY Bagels
    static let bagel = Recipe(
        id: "bagel",
        title: "NY Bagels",
        breadType: .leanYeasted,
        source: .original,
        photo: "bread_bagel",
        hydrationPct: 56, saltPct: 2.0, leavenPct: 0.8,
        totalDoughGrams: 1100, loafCount: 8,
        timeToBake: "18h overnight",
        tags: ["weekend"],
        twinScald: false,
        preferments: [],
        ingredients: [
            Ingredient(name: "High-protein bread flour", category: .flour,  weightGrams: 660, bakersPct: 100),
            Ingredient(name: "Water",                    category: .liquid, weightGrams: 370, bakersPct: 56),
            Ingredient(name: "Salt",                     category: .salt,   weightGrams: 13,  bakersPct: 2),
            Ingredient(name: "Instant yeast",            category: .leaven, weightGrams: 5,   bakersPct: 0.8),
            Ingredient(name: "Barley malt syrup",        category: .sweet,  weightGrams: 12,  bakersPct: 2),
        ],
        stages: [
            Stage(kind: .mix,         durationMin: 12,  temperatureC: 22, note: "Stiff dough"),
            Stage(kind: .bulk,        durationMin: 60,  temperatureC: 22),
            Stage(kind: .divideShape, durationMin: 30,  temperatureC: 22, note: "Roll, ring, pinch"),
            Stage(kind: .coldRetard,  durationMin: 720, temperatureC: 4,  note: "Overnight in fridge"),
            Stage(kind: .bake,        durationMin: 22,  temperatureC: 245, note: "Boil 30s/side, then bake"),
        ],
        lastBake: Recipe.LastBake(rating: 4, when: "1 month ago", note: nil)
    )

    // MARK: Hokkaido Milk Bread — twin-scald (yudane + tangzhong)
    static let hokkaido = Recipe(
        id: "hokkaido",
        title: "Hokkaido Milk Bread",
        breadType: .enriched,
        source: .original,
        photo: "bread_shokupan",
        hydrationPct: 72, saltPct: 1.5, leavenPct: 1.0,
        totalDoughGrams: 1180, loafCount: 2,
        timeToBake: "14h overnight",
        tags: ["twin-scald", "shokupan"],
        twinScald: true,
        preferments: [
            Preferment(
                id: "yudane", name: "Yudane", technique: "1:1 scald · rest 12h",
                prep: "Pour boiling water over flour, mix to a paste, cover, rest overnight in fridge.",
                flourPct: 8,
                ingredients: [
                    Ingredient(name: "Bread flour",   category: .flour,  weightGrams: 64, bakersPct: 8, section: "yudane"),
                    Ingredient(name: "Boiling water", category: .liquid, weightGrams: 64, bakersPct: 8, section: "yudane"),
                ]
            ),
            Preferment(
                id: "tangzhong", name: "Tangzhong", technique: "1:5 cook to 65°C",
                prep: "Whisk flour + milk in a saucepan over medium heat to 65°C until pudding-thick. Cool.",
                flourPct: 6,
                ingredients: [
                    Ingredient(name: "Bread flour", category: .flour,  weightGrams: 48,  bakersPct: 6,  section: "tangzhong"),
                    Ingredient(name: "Whole milk",  category: .liquid, weightGrams: 240, bakersPct: 30, section: "tangzhong"),
                ]
            ),
        ],
        ingredients: [
            Ingredient(name: "Bread flour",     category: .flour,  weightGrams: 688, bakersPct: 86,  section: "main"),
            Ingredient(name: "Whole milk",      category: .liquid, weightGrams: 200, bakersPct: 25,  section: "main"),
            Ingredient(name: "Egg",             category: .liquid, weightGrams: 50,  bakersPct: 6.3, section: "main"),
            Ingredient(name: "Sugar",           category: .sweet,  weightGrams: 64,  bakersPct: 8,   section: "main"),
            Ingredient(name: "Sea salt",        category: .salt,   weightGrams: 12,  bakersPct: 1.5, section: "main"),
            Ingredient(name: "Instant yeast",   category: .leaven, weightGrams: 8,   bakersPct: 1.0, section: "main"),
            Ingredient(name: "Unsalted butter", category: .fat,    weightGrams: 56,  bakersPct: 7,   section: "main"),
        ],
        stages: [
            Stage(kind: .prepYudane,    durationMin: 720, temperatureC: 4,   note: "Scald, mix, cover, rest in fridge overnight", scaldRef: "yudane"),
            Stage(kind: .cookTangzhong, durationMin: 15,  temperatureC: 65,  note: "Whisk flour + milk to 65°C, cool to room temp", scaldRef: "tangzhong"),
            Stage(kind: .mix,           durationMin: 18,  temperatureC: 24,  note: "Combine yudane, tangzhong, milk, egg, dry. Knead to develop."),
            Stage(kind: .addButter,     durationMin: 10,  temperatureC: 24,  note: "Window-pane stage"),
            Stage(kind: .bulk,          durationMin: 90,  temperatureC: 26,  note: "Until doubled"),
            Stage(kind: .divideShape,   durationMin: 20,  temperatureC: 24,  note: "4 rolls per loaf, tight cylinders"),
            Stage(kind: .finalProof,    durationMin: 75,  temperatureC: 28,  note: "85% of pan height"),
            Stage(kind: .bake,          durationMin: 35,  temperatureC: 180, note: "Cover for last 10 min if browning fast"),
        ],
        lastBake: nil
    )
}
