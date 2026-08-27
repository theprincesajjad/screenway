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

## Status: Gate 2 (live VNC slice)

This repository currently implements **Gate 2** of the roadmap — a
physical-device-ready vertical slice of the live Screen Sharing path:

- The default app environment now wires the **live**
  [RoyalVNCKit](https://github.com/royalapplications/royalvnc)-backed
  `RoyalVNCAdapter` (enforced by a unit test). Connecting to a saved Mac
  opens a real RFB session over your tailnet.
- Authentication uses Apple Remote Desktop (username/password) when the Mac
  offers it, with classic VNC password as the fallback. Unauthenticated
  sessions (servers offering security type None) are rejected.
- The first framebuffer renders through Metal (`MTKView`), with dirty-rect
  texture uploads. A tap sends one primary click at the mapped coordinate and
  a debug control sends one key — the full input/keyboard experience is a
  later gate.
- The Tailscale destination policy is enforced before any socket opens, and
  name-based destinations are pinned to a validated resolved address.
- SFTP file access is **still mocked**: [Citadel](https://github.com/orlandos-nl/Citadel)
  stays pinned but unused in the live path until the file gate.

**The ship gate for Gate 2 is a physical device, not the simulator or CI.**
CI proves the build, the unit tests, and the adapter contract against a
loopback RFB fixture; verifying against a real Mac over Tailscale requires
running the app on hardware (which needs a personal signing team locally —
the repo itself stays unsigned). See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

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
