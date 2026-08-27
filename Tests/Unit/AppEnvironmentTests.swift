import Testing
@testable import Screenway

@Suite("App environment")
@MainActor
struct AppEnvironmentTests {
    @Test("The default Gate 1 environment wires mocks only")
    func defaultUsesMocks() {
        let environment = AppEnvironment()
        #expect(environment.usesMockAdaptersOnly)
        #expect(environment.remoteDesktopProvider == .mock)
        #expect(environment.fileTransferProvider == .mock)
        #expect(environment.makeRFBClient() is MockRFBClient)
        #expect(environment.makeSFTPClient() is MockSFTPClient)
        #expect(environment.credentialStore is InMemoryCredentialStore)
    }

    @Test("Live adapters exist but are never the Gate 1 default")
    func liveAdaptersNotDefault() {
        let environment = AppEnvironment()
        #expect(!(environment.makeRFBClient() is RoyalVNCAdapter))
        #expect(!(environment.makeSFTPClient() is CitadelSFTPAdapter))
    }
}
