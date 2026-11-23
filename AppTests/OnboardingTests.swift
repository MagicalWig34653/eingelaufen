import Foundation
import GearCore
import Testing
@testable import Eingelaufen

/// Onboarding-Gerüst (SPEC S01): Sportarten wählen, Health „Später“, erstes Teil optional. Kein Konto.
@Suite struct OnboardingTests {
    @Test func freshStoreIsNotOnboarded() async throws {
        let p = try makePersistence()
        let s = try await p.settings()
        #expect(s.onboardingCompleted == false)
        #expect(s.healthChoice == .undecided)
    }

    @Test func completingStoresSportsAndHealthLater() async throws {
        let p = try makePersistence()
        _ = try await p.apply(.completeOnboarding(OnboardingChoice(categories: [.cycling, .running], health: .later)), now: t0)
        let s = try await p.settings()
        #expect(s.onboardingCompleted)
        #expect(s.healthChoice == .later)
        let profiles = try await p.dataset().sportProfiles
        #expect(Set(profiles.map(\.sportType)) == [SportCategory.cycling.defaultSportType, SportCategory.running.defaultSportType])
        #expect(profiles.allSatisfy { $0.enabled })
        #expect(try await p.dataset().gear.isEmpty, "Onboarding legt keine Ausrüstung ohne Auftrag an")
    }

    @Test func skippingWithoutSportsStillCompletes() async throws {
        let p = try makePersistence()
        _ = try await p.apply(.completeOnboarding(OnboardingChoice(categories: [], health: .later)), now: t0)
        #expect(try await p.settings().onboardingCompleted)
        #expect(try await p.dataset().sportProfiles.isEmpty)
    }

    @Test func completingTwiceDoesNotDuplicateProfiles() async throws {
        let p = try makePersistence()
        let choice = OnboardingChoice(categories: [.swimming], health: .later)
        _ = try await p.apply(.completeOnboarding(choice), now: t0)
        _ = try await p.apply(.completeOnboarding(choice), now: day(1))
        #expect(try await p.dataset().sportProfiles.count == 1)
    }

    @Test func catalogSuggestsAShortTemplateForEveryCategory() {
        for category in SportCategory.allCases {
            #expect(!GearTemplateCatalog.templates(for: category).isEmpty, "SPEC 1.3: je Sportart eine Vorlage (\(category))")
        }
    }
}
