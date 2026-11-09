import Testing
@testable import MyApp

/// Checks the app icon choices match the alternate icon sets.
struct AppIconChoiceTests {

    @Test func namesMatchTheIconSets() {
        #expect(AppIconChoice.automatic.iconName == nil)
        #expect(AppIconChoice.sunrise.iconName == "AppIcon-Sunrise")
        #expect(AppIconChoice.night.iconName == "AppIcon-Night")
    }

    @Test func currentIconIsRecognised() {
        #expect(AppIconChoice(iconName: nil) == .automatic)
        #expect(AppIconChoice(iconName: "AppIcon-Night") == .night)
        #expect(AppIconChoice(iconName: "AppIcon-Sunrise") == .sunrise)
    }

    @Test func unknownNameCountsAsAutomatic() {
        #expect(AppIconChoice(iconName: "Something-Else") == .automatic)
    }
}
