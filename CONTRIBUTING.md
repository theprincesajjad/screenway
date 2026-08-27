# Contributing to Screenway

Thanks for your interest! Screenway is an MIT-licensed iOS/iPadOS client for
macOS Screen Sharing over Tailscale.

## Ground rules

- **Swift 6, strict concurrency.** New code must compile in the Swift 6
  language mode without concurrency warnings.
- **UI never imports the transport kits.** Feature code depends on
  `RFBClientProtocol` / `SFTPClientProtocol` only. RoyalVNCKit and Citadel are
  referenced solely inside their adapters.
- **Secrets never leave the keychain layer.** Do not add code that writes
  passwords to SwiftData, UserDefaults, files, or logs.
- **Error codes are a contract.** The `NET-*`/`VNC-*`/`SSH-*`/`FILE-*`/`CLIP-*`
  codes, titles, and actions are contract-tested. Changing them requires
  updating the tests and the docs deliberately.
- **No analytics, no vendor network SDKs, no nonpermissive licenses.**
- SPM only. If you change dependencies, commit the updated `Package.resolved`
  and update `THIRD_PARTY_NOTICES.md`.

## Workflow

1. Fork and create a topic branch.
2. Make your change, with unit tests for any logic change.
3. Run the test suite: open `Screenway.xcodeproj`, scheme `Screenway`,
   Product > Test — or:

   ```bash
   xcodebuild test -project Screenway.xcodeproj -scheme Screenway \
     -destination 'platform=iOS Simulator,name=iPhone 16' \
     CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
   ```

4. Open a pull request. CI must pass (build + unit tests, unsigned).

## Roadmap gates

Work lands in gates. Gate 1 (current) is the mock-driven skeleton. Gate 2
wires real RFB/SFTP connections behind the existing protocols. Please do not
open PRs that jump ahead of the current gate without discussing in an issue
first.
