import Foundation
import Observation

/// Which implementation family the environment hands to features.
public enum AdapterProvider: String, Sendable, Equatable {
    case mock
    case live
}

/// Dependency container handed to every feature through the SwiftUI
/// environment.
///
/// Gate 2 invariant (tested): the default environment wires the LIVE
/// `RoyalVNCAdapter` for remote desktop. File transfer stays on
/// `MockSFTPClient` (Citadel remains pinned but unused in the live path
/// until the file gate). Tests and previews construct explicit mock
/// environments, or launch the app with `mockAdaptersLaunchArgument`.
@MainActor
@Observable
public final class AppEnvironment {
    /// Launch argument that switches the whole app to mock adapters
    /// (used by UI tests and previews; see `forCurrentProcess`).
    public static let mockAdaptersLaunchArgument = "-screenway-mock-adapters"
    public let remoteDesktopProvider: AdapterProvider
    public let fileTransferProvider: AdapterProvider
    public let credentialStore: any CredentialStore
    public let profileRepository: MacProfileRepository
    public let hostKeyStore: SSHHostKeyStore
    private let rfbClientFactory: @Sendable () -> any RFBClientProtocol
    private let sftpClientFactory: @Sendable () -> any SFTPClientProtocol

    public var usesMockAdaptersOnly: Bool {
        remoteDesktopProvider == .mock && fileTransferProvider == .mock
    }

    public init(
        remoteDesktopProvider: AdapterProvider = .live,
        fileTransferProvider: AdapterProvider = .mock,
        credentialStore: (any CredentialStore)? = nil,
        profileStore: (any MacProfileStore)? = nil,
        rfbClientFactory: (@Sendable () -> any RFBClientProtocol)? = nil,
        sftpClientFactory: (@Sendable () -> any SFTPClientProtocol)? = nil
    ) {
        self.remoteDesktopProvider = remoteDesktopProvider
        self.fileTransferProvider = fileTransferProvider
        let credentials = credentialStore ?? InMemoryCredentialStore()
        self.credentialStore = credentials
        self.profileRepository = MacProfileRepository(
            profileStore: profileStore ?? InMemoryMacProfileStore(),
            credentialStore: credentials
        )
        self.hostKeyStore = SSHHostKeyStore()
        self.rfbClientFactory = rfbClientFactory ?? Self.defaultRFBClientFactory(for: remoteDesktopProvider)
        self.sftpClientFactory = sftpClientFactory ?? { MockSFTPClient() }
    }

    /// The environment `ScreenwayApp` boots with: live RFB by default, mocks
    /// when the mock launch argument is present (UI tests, previews).
    public static func forCurrentProcess(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> AppEnvironment {
        if arguments.contains(mockAdaptersLaunchArgument) {
            return AppEnvironment(remoteDesktopProvider: .mock, fileTransferProvider: .mock)
        }
        return AppEnvironment()
    }

    private static func defaultRFBClientFactory(
        for provider: AdapterProvider
    ) -> @Sendable () -> any RFBClientProtocol {
        switch provider {
        case .live: { RoyalVNCAdapter() }
        case .mock: { MockRFBClient() }
        }
    }

    public func makeRFBClient() -> any RFBClientProtocol {
        rfbClientFactory()
    }

    public func makeSFTPClient() -> any SFTPClientProtocol {
        sftpClientFactory()
    }
}
