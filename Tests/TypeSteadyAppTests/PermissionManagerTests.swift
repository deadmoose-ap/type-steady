import Testing
@testable import TypeSteadyApp

struct PermissionManagerTests {
    @Test func privacySettingsUseCurrentMacOSRoute() {
        #expect(
            PrivacyPermission.accessibility.settingsURL.absoluteString ==
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        )
        #expect(
            PrivacyPermission.inputMonitoring.settingsURL.absoluteString ==
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent"
        )
    }

    @Test func repairTargetsOnlyRequiredTCCServices() {
        #expect(Set(PrivacyPermission.allCases.map(\.rawValue)) == ["Accessibility", "ListenEvent"])
    }
}
