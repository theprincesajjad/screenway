import Testing
@testable import Screenway

@Suite("Error codes")
struct ErrorCodeTests {
    /// The contract table from the PRD. Raw value -> (title, action).
    static let contract: [(code: String, title: String, action: String)] = [
        ("NET-001", "Mac name not found", "Edit Address"),
        ("NET-002", "Tailscale route unavailable", "Check Tailscale"),
        ("NET-003", "Mac did not respond", "Try Again"),
        ("VNC-001", "Screen Sharing is off", "View Setup Steps"),
        ("VNC-002", "Sign-in failed", "Edit Sign-In"),
        ("VNC-003", "Screen format unsupported", "Retry in Compatibility Mode"),
        ("VNC-004", "Session ended", "Reconnect"),
        ("SSH-001", "Remote Login is off", "View File Setup"),
        ("SSH-002", "SSH sign-in failed", "Edit File Sign-In"),
        ("SSH-003", "Mac identity changed", "Review Mac Identity"),
        ("FILE-001", "Not enough space", "Manage Storage"),
        ("FILE-002", "Permission denied", "Choose Another Folder"),
        ("FILE-003", "File changed", "Restart Transfer"),
        ("CLIP-001", "Clipboard has no text", "Dismiss"),
        ("CLIP-002", "Mac rejected paste", "Type Instead"),
    ]

    @Test("Every contract row maps to the expected title and action",
          arguments: contract)
    func mapping(row: (code: String, title: String, action: String)) throws {
        let code = try #require(ScreenwayErrorCode(rawValue: row.code))
        #expect(code.title == row.title)
        #expect(code.action == row.action)
        #expect(!code.reason.isEmpty)
    }

    @Test("The code set is exactly the contract set")
    func completeness() {
        #expect(ScreenwayErrorCode.allCases.count == Self.contract.count)
        let contractCodes = Set(Self.contract.map(\.code))
        let actualCodes = Set(ScreenwayErrorCode.allCases.map(\.rawValue))
        #expect(contractCodes == actualCodes)
    }

    @Test("ScreenwayError carries the code through LocalizedError")
    func localizedError() {
        let error = ScreenwayError(.vncSignInFailed, detail: "mock detail")
        #expect(error.errorDescription == "Sign-in failed")
        #expect(error.recoverySuggestion == "Edit Sign-In")
        #expect(error.failureReason == ScreenwayErrorCode.vncSignInFailed.reason)
    }
}
