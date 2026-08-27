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
/// Gate 1 invariant (tested): the default environment wires mocks only.
/// `RoyalVNCAdapter` / `CitadelSFTPAdapter` compile but are never
/// instantiated here until Gate 2.
@MainActor
@Observable
public final class AppEnvironment {
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
        remoteDesktopProvider: AdapterProvider = .mock,
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
        self.rfbClientFactory = rfbClientFactory ?? { MockRFBClient() }
        self.sftpClientFactory = sftpClientFactory ?? { MockSFTPClient() }
    }

    public func makeRFBClient() -> any RFBClientProtocol {
        rfbClientFactory()
    }

    public func makeSFTPClient() -> any SFTPClientProtocol {
        sftpClientFactory()
    }
}
