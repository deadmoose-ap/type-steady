import Testing
@testable import TypeSteadyApp

struct SettingsNavigationTests {
    @Test func exposesEverySettingsAreaInStableOrder() {
        #expect(SettingsDestination.allCases == [
            .general,
            .languages,
            .detection,
            .applications,
            .privacy
        ])
    }

    @Test func everyDestinationHasCompletePresentationMetadata() {
        let titles = SettingsDestination.allCases.map(\.title)
        let symbols = SettingsDestination.allCases.map(\.systemImage)

        #expect(Set(titles).count == SettingsDestination.allCases.count)
        #expect(Set(symbols).count == SettingsDestination.allCases.count)

        for destination in SettingsDestination.allCases {
            #expect(!destination.rawValue.isEmpty)
            #expect(!destination.title.isEmpty)
            #expect(!destination.subtitle.isEmpty)
            #expect(!destination.systemImage.isEmpty)
        }
    }
}
