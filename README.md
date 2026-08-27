# Screenway

Screenway is a free, MIT-licensed iOS/iPadOS 18+ client for macOS Screen Sharing
(VNC/RFB on TCP 5900) with optional SFTP file access (macOS Remote Login on TCP 22),
connecting over your existing [Tailscale](https://tailscale.com) network.

## What it is

- A native SwiftUI app that talks directly to your own Mac across your own tailnet.
- No Screenway backend, no account, no cloud relay, no Mac-side agent to install.
- No ads, no analytics, no paid tier.

## What it is not

- **Not a Tailscale replacement and not affiliated with Tailscale.** Screenway
  simply connects to addresses that are reachable through the Tailscale app you
  already run. Tailscale is a trademark of Tailscale Inc. Screenway is not
  affiliated with or endorsed by Tailscale Inc.
- Not a general-purpose VNC or SFTP client: destinations outside your tailnet
  (public internet, ordinary LAN, loopback) are rejected by policy.
- Not an App Store product yet. The name "Screenway" and the bundle identifier
  `app.screenway` are working identifiers and need trademark/identifier
  clearance before any App Store submission.

## Status: Gate 1 (mock transport)

This repository currently implements **Gate 1** of the roadmap:

- The full app skeleton compiles: domain models, error codes, host parsing,
  Tailscale destination policy, session state machine, adapter protocols, and
  keychain/profile stores — all unit-tested.
- The UI (welcome screen, Macs list, Add Mac form, Session screen) runs
  entirely on **mock** RFB/SFTP clients. **No real VNC or SFTP connection is
  made in Gate 1.** "Test Connection" and "Connect" drive scripted mocks.
- [RoyalVNCKit](https://github.com/royalapplications/royalvnc) and
  [Citadel](https://github.com/orlandos-nl/Citadel) are pinned in
  `Package.resolved` and their adapters compile, but the default app
  environment never instantiates them (enforced by a unit test).

Real connections (Gate 2) come next. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Building

Requirements: Xcode 26 (or later) on macOS.

```bash
git clone https://github.com/theprincesajjad/screenway.git
cd screenway
open Screenway.xcodeproj   # scheme: Screenway
```

Or from the command line (no signing needed for the simulator):

```bash
xcodebuild test \
  -project Screenway.xcodeproj \
  -scheme Screenway \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

CI builds and tests every pull request unsigned; see
[.github/workflows/ci.yml](.github/workflows/ci.yml).

## Security & privacy

Secrets live only in the keychain-backed credential store, never in profile
storage. SSH host keys are trust-on-first-use with a hard stop on mismatch.
See [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE). Third-party dependency licenses are listed in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
