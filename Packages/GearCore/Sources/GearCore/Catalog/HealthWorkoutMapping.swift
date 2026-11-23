import Foundation

/// Zentral testbare Tabelle `HKWorkoutActivityType.rawValue → Kategorie/Unterkategorie` (SPEC 3.3).
///
/// Geprüft gegen HealthKit/HKWorkoutActivityType.h im iOS-SDK 27.2 (23.11.2026): 1–80, 82–84 und 3000
/// (`Rest` 2998 und `Group` 2999 sind auf iOS nicht verfügbar und landen wie alles Unbekannte in „Sonstige“).
/// Bei neuem SDK diese Liste und den Test `mappingCoversExactlySDKList` gemeinsam anpassen.
///
/// Einordnungsentscheidungen (umkehrbar, nur Mapping, keine Nutzerdaten):
/// - Kampfsport, Tanz-Sport außerhalb Studio, Eis-/Rollsport, Golf, Reiten u. Ä. → „Sonstige“, weil die Spec dafür
///   keine eigene Kategorie nennt; dort ist alles frei definierbar.
/// - Tanz, Yoga, Pilates, HIIT, Cardio-Geräte → „Fitness & Kraft“ (Studio/Matte/Zubehör).
/// - Wasserball → Ballsport, Tauchen → „Wasser & Paddeln“.
/// - Indoor/Outdoor wird **nicht** aus dem Typ abgeleitet (SPEC 3.3); nur eindeutige Typen tragen eine Unterkategorie.
public enum HealthWorkoutMapping {
    public static let table: [Int: SportClassification] = {
        var t: [Int: SportClassification] = [:]
        func add(_ category: SportCategory, _ raws: [Int], subtype: SportSubtype? = nil) {
            for raw in raws { t[raw] = SportClassification(category, subtype) }
        }
        add(.cycling, [13, 74])                                   // Cycling, HandCycling
        add(.running, [37, 49, 71])                               // Running, TrackAndField, WheelchairRunPace
        add(.walkingHiking, [52, 70])                             // Walking, WheelchairWalkPace
        add(.walkingHiking, [24], subtype: .hiking)               // Hiking
        add(.swimming, [46, 53])                                  // Swimming, WaterFitness
        add(.fitness, [11, 14, 15, 16, 20, 29, 30, 33, 44, 50, 57, 58, 59, 62, 63, 64, 66, 68, 69, 72, 73, 76, 77, 78, 80])
        // CrossTraining, Dance, DanceInspired, Elliptical, FunctionalStrength, MindAndBody, MixedMetabolic,
        // PrepAndRecovery, StairClimbing, TraditionalStrength, Yoga, Barre, Core, Flexibility, HIIT, JumpRope,
        // Pilates, Stairs, StepTraining, TaiChi, MixedCardio, FitnessGaming, CardioDance, SocialDance, Cooldown
        add(.winterSports, [40], subtype: .ski)                   // SnowSports
        add(.winterSports, [60], subtype: .crossCountrySkiing)
        add(.winterSports, [61], subtype: .ski)                   // DownhillSkiing
        add(.winterSports, [67], subtype: .snowboard)
        add(.ballSports, [1, 3, 5, 10, 23, 25, 27, 36, 42, 54, 75])
        // AmericanFootball, AustralianFootball, Baseball, Cricket, Handball, Hockey, Lacrosse, Rugby, Softball,
        // WaterPolo, DiscSports
        add(.ballSports, [6], subtype: .basketball)
        add(.ballSports, [41], subtype: .football)                // Soccer
        add(.ballSports, [51], subtype: .volleyball)
        add(.racketSports, [34, 47, 79])                          // Racquetball, TableTennis, Pickleball
        add(.racketSports, [4], subtype: .badminton)
        add(.racketSports, [43], subtype: .squash)
        add(.racketSports, [48], subtype: .tennis)
        add(.waterPaddle, [31, 38, 55, 84])                       // PaddleSports, Sailing, WaterSports, UnderwaterDiving
        add(.waterPaddle, [35], subtype: .rowing)
        add(.waterPaddle, [45], subtype: .surfing)                // SurfingSports
        add(.triathlonMultisport, [82, 83])                       // SwimBikeRun, Transition
        add(.climbing, [9])                                       // Climbing (Indoor/Outdoor unbekannt)
        add(.other, [2, 7, 8, 12, 17, 18, 19, 21, 22, 26, 28, 32, 39, 56, 65, 3000])
        // Archery, Bowling, Boxing, Curling, Equestrian, Fencing, Fishing, Golf, Gymnastics, Hunting, MartialArts,
        // Play, SkatingSports, Wrestling, Kickboxing, Other
        return t
    }()
}
