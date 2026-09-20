import Foundation
import Testing
@testable import AppInfo

struct AppIdentityTests {
    @Test func prefersDisplayName() {
        let identity = AppIdentity(infoDictionary: [
            "CFBundleDisplayName": "Display",
            "CFBundleName": "Bundle",
            "CFBundleIdentifier": "com.example.display",
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "42",
        ])
        #expect(identity.name == "Display")
        #expect(identity.bundleIdentifier == "com.example.display")
        #expect(identity.version == "1.2.3")
        #expect(identity.build == "42")
    }

    @Test func readsTheRepositoryURLFromInfoPlist() {
        let identity = AppIdentity(infoDictionary: ["GitHubRepositoryURL": "https://github.com/poolmoot/sidenote"])
        #expect(identity.repositoryURL == URL(string: "https://github.com/poolmoot/sidenote"))
    }

    @Test func repositoryURLIsNilWhenTheKeyIsMissing() {
        #expect(AppIdentity(infoDictionary: [:]).repositoryURL == nil)
    }

    @Test func fallsBackToBundleNameWhenDisplayNameIsEmpty() {
        let identity = AppIdentity(infoDictionary: ["CFBundleDisplayName": "", "CFBundleName": "Bundle"])
        #expect(identity.name == "Bundle")
    }

    @Test func hasSafeDefaultsWithNoInfoDictionary() {
        let identity = AppIdentity(infoDictionary: [:])
        #expect(identity.name == "App")
        #expect(identity.bundleIdentifier == "local.app")
        #expect(identity.version == "0.0.0")
        #expect(identity.build == "0")
    }
}
