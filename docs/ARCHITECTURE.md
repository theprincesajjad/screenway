# Screenway Architecture

High-level notes for Gate 1. This is a living document; sections marked
"Gate 2" describe intent, not shipped behavior.

## Shape of the app

Screenway is a native SwiftUI iOS/iPadOS 18+ app, Swift 6 strict concurrency,
built with an `.xcodeproj` (scheme `Screenway`) and SPM dependencies only.

```
Screenway/
  App/            ScreenwayApp, AppEnvironment (DI container), SceneLifecycleCoordinator
  Features/       Macs, AddMac, Session, Clipboard, Files, Transfers, Settings, SetupGuide
  Core/           Models, Persistence, Keychain, Networking, Security, Diagnostics
  RemoteDesktop/  RFBClientProtocol, RoyalVNCAdapter, MockRFBClient, SessionStateMachine
  FileTransfer/   SFTPClientProtocol, CitadelSFTPAdapter, MockSFTPClient, SSHHostKeyStore
Tests/            Unit tests + protocol fixtures
UITests/          Minimal UI-test target
```

## The adapter rule

Feature and UI code never imports RoyalVNCKit or Citadel. Everything goes
through two Screenway-owned protocols:

- `RFBClientProtocol` (actor): connect / authenticate / disconnect, an
  `AsyncStream` of events (state changes, framebuffer updates, desktop name,
  clipboard text, session end), pointer/key/clipboard sends.
- `SFTPClientProtocol` (actor): connect (with mandatory host-key verification
  through `SSHHostKeyStore`), directory listing, file read/write.

`AppEnvironment` is the composition root. In Gate 1 it wires
`MockRFBClient` / `MockSFTPClient` only; a unit test
(`AppEnvironmentTests`) enforces that the default environment uses mocks and
never the live adapters.

### Dependency pinning notes

- **Citadel 0.12.1** is pinned with an exact-version requirement.
- **RoyalVNCKit 1.1.0** is pinned to the commit its `1.1.0` tag points to
  (`92d4427c73817d8f849bb289ff190aa4b40c44ea`) rather than an exact-version
  requirement. Reason: the 1.1.0 manifest depends on a *branch* of
  `royalapplications/CryptoSwift` (`foundationessentials`), and SwiftPM
  refuses to resolve a version-pinned package that has branch dependencies
  ("required using a stable-version but depends on an unstable-version
  package"). A revision pin sidesteps that rule while remaining exactly
  reproducible. If upstream moves back to a released CryptoSwift, switch the
  requirement to `exactVersion 1.1.x`.
- RoyalVNCKit's `RoyalVNCKit` product is declared **dynamic** upstream. Xcode
  embeds dynamic SPM library products into the app bundle automatically, so
  no fork or patch is needed. The adapter guards its import with
  `#if canImport(RoyalVNCKit)` so the target still compiles if the product is
  ever unavailable on a platform.
- RoyalVNCKit's image-codec dependencies (`swift-jpeg`, `swift-png`, `h`) are
  platform-conditioned to Linux/Windows/Android and are not linked on iOS.

## Domain model

`MacProfile` (non-secret) is the saved-Mac record: display name, host, VNC
port/auth mode, input/scale/quality modes, view-only, `allowLocalNetwork`
flag, optional `SFTPProfile`, and last-connection metadata. Secrets are
referenced by opaque credential IDs (`vncCredentialID`,
`SFTPProfile.credentialID`) that point into the keychain-backed
`CredentialStore`. `MacProfileRepository` enforces the lifecycle rule:
deleting a profile deletes its credentials (unit-tested). Passwords are never
stored in SwiftData (Gate 1 uses an in-memory store; a SwiftData store can
replace it behind the same `MacProfileStore` protocol).

`TransferCheckpoint` (Gate 2+) records resumable transfer state including a
source fingerprint so changed files restart instead of resuming (FILE-003).

## Destination policy

`HostParser` accepts machine names, FQDNs, IPv4, bare IPv6, `host:port`, and
`[ipv6]:port`; it rejects malformed input and any non-ASCII hostname
(Unicode-lookalike defense). `TailscaleDestinationPolicy` then allows only:

- IPv4 in `100.64.0.0/10` (CGNAT range used by Tailscale),
- IPv6 in `fd7a:115c:a1e0::/48` (Tailscale ULA),
- names, only once **every** resolved address is inside those ranges.

Loopback, link-local, public internet, and ordinary private LAN are rejected.
`allowLocalNetwork` is a per-profile flag that the policy function honors for
direct RFC1918/ULA addresses, but Gate 1 implements no LAN connection path —
the flag exists so the policy is complete and tested.

## Session state machine

States: `disconnected, resolving, connecting, authenticating, negotiating,
connected, reconnecting, suspending, failed`. The transition table is pure
and unit-tested. Illegal transitions `assertionFailure` in debug builds and
collapse to a safe `disconnected` in release builds.

## Error codes

User-facing errors are a stable contract (`ScreenwayErrorCode`):
NET-001..003, VNC-001..004, SSH-001..003, FILE-001..003, CLIP-001..002, each
with title / reason / action copy. The table is contract-tested; treat
changes as breaking.

## Gate 1 UI

Deliberately unpolished system UI: welcome screen → Macs list (empty state +
rows with Connect) → Add Mac form (mock Test Connection) → Session screen that
walks the mock connection phases ("Finding Mac…", "Reaching Mac…",
"Signing in…", "Preparing screen…", "Waiting for screen…") and then shows a
plain "Remote screen (mock)" placeholder. No Metal, no gestures, no custom
design system.

## Gate 2 (not in this repo yet)

Real RFB via `RoyalVNCAdapter`, real SFTP via `CitadelSFTPAdapter`
(host-key verification through `SSHHostKeyStore`; `acceptAnything`-style
validators are forbidden in release paths), real Keychain-backed
`CredentialStore`, Metal framebuffer rendering, clipboard and file features.
