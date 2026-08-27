import Foundation
import Testing
@testable import Screenway

@Suite("RFB credential preparation")
struct RFBCredentialPreparerTests {
    @Test("Apple Remote Desktop needs username and password")
    func ardCredential() {
        let full = RFBCredentials(mode: .automatic, username: "casey", password: "hunter2")
        #expect(
            RFBCredentialPreparer.prepare(full, for: .ardUsernamePassword)
                == .usernamePassword(username: "casey", password: "hunter2")
        )
        let missingUsername = RFBCredentials(mode: .automatic, username: nil, password: "hunter2")
        #expect(RFBCredentialPreparer.prepare(missingUsername, for: .ardUsernamePassword) == nil)
        let emptyUsername = RFBCredentials(mode: .automatic, username: "", password: "hunter2")
        #expect(RFBCredentialPreparer.prepare(emptyUsername, for: .ardUsernamePassword) == nil)
    }

    @Test("VNC password fallback needs only the password")
    func vncCredential() {
        let passwordOnly = RFBCredentials(mode: .vncPassword, password: "hunter2")
        #expect(RFBCredentialPreparer.prepare(passwordOnly, for: .vncPassword) == .password("hunter2"))
    }

    @Test("Missing or empty passwords never authenticate")
    func missingPassword() {
        let noPassword = RFBCredentials(mode: .automatic, username: "casey")
        #expect(RFBCredentialPreparer.prepare(noPassword, for: .vncPassword) == nil)
        #expect(RFBCredentialPreparer.prepare(noPassword, for: .ardUsernamePassword) == nil)
        let emptyPassword = RFBCredentials(mode: .automatic, username: "casey", password: "")
        #expect(RFBCredentialPreparer.prepare(emptyPassword, for: .vncPassword) == nil)
    }
}

@Suite("RFB failure mapping")
struct RFBFailureMapperTests {
    @Test("Failure classes map to the stable error codes")
    func stableCodes() {
        #expect(RFBFailure.nameResolution.screenwayError.code == .netNameNotFound)          // NET-001
        #expect(RFBFailure.unreachable.screenwayError.code == .netTailscaleRouteUnavailable) // NET-002
        #expect(RFBFailure.timedOut.screenwayError.code == .netNoResponse)                   // NET-003
        #expect(RFBFailure.connectionRefused.screenwayError.code == .vncScreenSharingOff)    // VNC-001
        #expect(RFBFailure.authenticationFailed.screenwayError.code == .vncSignInFailed)     // VNC-002
        #expect(RFBFailure.protocolError.screenwayError.code == .vncFormatUnsupported)       // VNC-003
        #expect(RFBFailure.sessionEnded.screenwayError.code == .vncSessionEnded)             // VNC-004
    }

    @Test("POSIX transport errors classify to the right failures")
    func posixClassification() {
        #expect(RFBFailure.fromPOSIXCode(ECONNREFUSED) == .connectionRefused)
        #expect(RFBFailure.fromPOSIXCode(ETIMEDOUT) == .timedOut)
        #expect(RFBFailure.fromPOSIXCode(EHOSTUNREACH) == .unreachable)
        #expect(RFBFailure.fromPOSIXCode(ENETUNREACH) == .unreachable)
        #expect(RFBFailure.fromPOSIXCode(ECONNRESET) == .sessionEnded)
        #expect(RFBFailure.fromPOSIXCode(EACCES) == nil)
    }
}
