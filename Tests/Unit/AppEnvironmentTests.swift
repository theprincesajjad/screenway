import Testing
@testable import Screenway

@Suite("App environment")
@MainActor
struct AppEnvironmentTests {
    @Test("The production default environment wires the live RFB adapter")
    func defaultIsLiveRFB() {
        // ScreenwayApp boots through forCurrentProcess(), which falls back to
        // AppEnvironment() when the mock launch argument is absent. Gate 2
        // requires that default to be the live RoyalVNCKit adapter.
        let environment = AppEnvironment()
        #expect(environment.remoteDesktopProvider == .live)
        #expect(!environment.usesMockAdaptersOnly)
        #expect(environment.makeRFBClient() is RoyalVNCAdapter)
    }

    @Test("File transfer stays mocked (Citadel is pinned but unused)")
    func fileTransferStaysMock() {
        let environment = AppEnvironment()
        #expect(environment.fileTransferProvider == .mock)
        #expect(environment.makeSFTPClient() is MockSFTPClient)
        #expect(!(environment.makeSFTPClient() is CitadelSFTPAdapter))
    }

    @Test("forCurrentProcess without the mock argument is the live environment")
    func forCurrentProcessDefault() {
        let environment = AppEnvironment.forCurrentProcess(arguments: ["ScreenwayApp"])
        #expect(environment.remoteDesktopProvider == .live)
        #expect(environment.makeRFBClient() is RoyalVNCAdapter)
    }

    @Test("The mock launch argument switches every adapter to mocks")
    func forCurrentProcessMock() {
        let environment = AppEnvironment.forCurrentProcess(
            arguments: ["ScreenwayApp", AppEnvironment.mockAdaptersLaunchArgument]
        )
        #expect(environment.usesMockAdaptersOnly)
        #expect(environment.makeRFBClient() is MockRFBClient)
        #expect(environment.makeSFTPClient() is MockSFTPClient)
    }

    @Test("Tests can still construct an explicit all-mock environment")
    func explicitMockEnvironment() {
        let environment = AppEnvironment(remoteDesktopProvider: .mock, fileTransferProvider: .mock)
        #expect(environment.usesMockAdaptersOnly)
        #expect(environment.makeRFBClient() is MockRFBClient)
        #expect(environment.makeSFTPClient() is MockSFTPClient)
        #expect(environment.credentialStore is InMemoryCredentialStore)
    }
}
