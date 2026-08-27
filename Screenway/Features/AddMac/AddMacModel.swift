import Foundation
import Observation

@MainActor
@Observable
final class AddMacModel {
    enum TestResult: Equatable {
        case idle
        case testing
        case success
        case failure(String)
    }

    var name = ""
    var address = ""
    var vncPortText = "5900"
    var authMode: VNCAuthMode = .automatic
    var macUsername = ""
    var password = ""
    var rememberPassword = false
    var enableFiles = false
    var sshUsername = ""
    var sshPortText = "22"
    private(set) var testResult: TestResult = .idle
    private(set) var validationMessage: String?

    private let repository: MacProfileRepository
    private let makeRFBClient: @MainActor () -> any RFBClientProtocol

    init(
        repository: MacProfileRepository,
        makeRFBClient: @escaping @MainActor () -> any RFBClientProtocol
    ) {
        self.repository = repository
        self.makeRFBClient = makeRFBClient
    }

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && parsedHost() != nil
    }

    private func parsedHost() -> ParsedHost? {
        try? HostParser.parse(address)
    }

    private func vncPort(from parsed: ParsedHost?) -> UInt16 {
        parsed?.port ?? UInt16(vncPortText) ?? 5900
    }

    /// Drives the environment's RFB client through a full connect cycle.
    /// With the live adapter this is a real reachability + sign-in check
    /// (destination policy enforced before any socket opens).
    func testConnection() async {
        guard let parsed = parsedHost() else {
            testResult = .failure(HostParseError.malformed.userMessage)
            return
        }
        testResult = .testing
        let client = makeRFBClient()
        let endpoint = RFBEndpoint(host: address, port: vncPort(from: parsed))
        do {
            try await client.connect(to: endpoint)
            try await client.authenticate(
                RFBCredentials(
                    mode: authMode,
                    username: macUsername.isEmpty ? nil : macUsername,
                    password: password.isEmpty ? nil : password
                )
            )
            await client.disconnect()
            testResult = .success
        } catch let error as ScreenwayError {
            testResult = .failure("\(error.code.title) (\(error.code.rawValue))")
        } catch {
            testResult = .failure(error.localizedDescription)
        }
    }

    /// Persists a non-secret profile; secrets go to the credential store.
    /// Returns true on success.
    func save() async -> Bool {
        guard let parsed = parsedHost() else {
            validationMessage = "Enter a valid Tailscale name or address."
            return false
        }
        var sftp: SFTPProfile?
        if enableFiles {
            sftp = SFTPProfile(
                enabled: true,
                username: sshUsername.isEmpty ? macUsername : sshUsername,
                port: UInt16(sshPortText) ?? 22,
                rememberCredential: rememberPassword
            )
        }
        let profile = MacProfile(
            displayName: name.trimmingCharacters(in: .whitespaces),
            host: address.trimmingCharacters(in: .whitespaces),
            vncPort: vncPort(from: parsed),
            vncAuthMode: authMode,
            macUsername: macUsername.isEmpty ? nil : macUsername,
            rememberVNCCredential: rememberPassword,
            sftp: sftp
        )
        do {
            try await repository.save(
                profile,
                vncPassword: password.isEmpty ? nil : password,
                sftpPassword: password.isEmpty ? nil : password
            )
            return true
        } catch {
            validationMessage = "Could not save this Mac."
            return false
        }
    }
}

extension HostParseError {
    var userMessage: String {
        switch self {
        case .empty: "Enter an address."
        case .malformed: "That address does not look valid."
        case .invalidPort: "The port must be between 1 and 65535."
        case .nonASCIIHostname: "Addresses must use plain ASCII letters and digits."
        case .invalidHostname: "That name is not a valid host name."
        }
    }
}
