# Screenway Architecture

High-level notes as of Gate 2 (the live VNC slice). This is a living
document.

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

`AppEnvironment` is the composition root. As of Gate 2 the default
environment wires the **live** `RoyalVNCAdapter` for remote desktop and the
mock SFTP client (Citadel stays pinned but unused until the file gate). A
unit test (`AppEnvironmentTests`) enforces both. Tests construct explicit
mock environments; UI tests and previews launch the app with the
`-screenway-mock-adapters` argument (`AppEnvironment.forCurrentProcess`).

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

## Gate 2: the live VNC slice

Gate 2 wires the real Screen Sharing path end to end. **The ship gate is a
physical device connecting to a real Mac over Tailscale — CI and the
simulator prove the build and the adapter contract, not the gate itself.**

### RoyalVNCAdapter bridging

RoyalVNCKit 1.1.0's `VNCConnection` runs the entire RFB handshake itself
(TCP via `NWConnection`, protocol version, security negotiation, ServerInit)
and asks for credentials through a delegate callback mid-handshake. The
adapter maps that onto Screenway's two-step `RFBClientProtocol` contract:

- `connect(to:)` first enforces `TailscaleDestinationPolicy` (names are
  resolved with `getaddrinfo` and pinned to a validated Tailscale address —
  no socket opens to a rejected destination), then starts the kit connection
  and suspends until the server asks for a credential. At that point the
  session is in `.authenticating` and `connect` returns.
- `authenticate(_:)` converts `RFBCredentials` into the mechanism the server
  picked (`VNCUsernamePasswordCredential` for Apple Remote Desktop /
  Diffie-Hellman, `VNCPasswordCredential` for classic VNC auth) and resumes
  the kit's pending credential callback, then suspends until the handshake
  finishes.
- **Unauthenticated sessions are rejected**: RoyalVNCKit prefers security
  type None when a server offers it, and None never triggers the credential
  callback. If the kit reports "connected" while `connect(to:)` is still
  waiting for a credential request, the adapter disconnects and fails with
  VNC-002.
- `disconnect()` releases any held pointer buttons and keys (with a short
  flush delay for the kit's async send queue), then closes the connection.
- Kit errors map to the stable codes: DNS → NET-001, unreachable → NET-002,
  timeout → NET-003, TCP refused → VNC-001, authentication → VNC-002,
  protocol/pixel-format (and framebuffer-cap refusals) → VNC-003, closed
  sessions → VNC-004 (`RFBFailure` + the bridge's `mapKitError`).
- Clipboard: RoyalVNCKit exposes no direct client-cut-text API (its
  clipboard support monitors the system pasteboard), so `sendClipboardText`
  is not offered in the Gate 2 UI and the feature lands in a later gate.

### Framebuffer path and rendering

The kit maintains one BGRA8 surface per session (IOSurface-backed by
default). The adapter installs a custom `VNCFramebufferAllocator` that
**refuses any surface allocation above 512 MiB before allocating**, and the
bridge validates dimensions (16384 px/side cap) and dirty-rect bounds before
copying. Each `didUpdateFramebuffer` callback copies just the dirty rect out
of the kit surface (under the allocator's read lock, synchronously, so rects
apply in wire order) into a Screenway-owned `FramebufferUpdate` with
`FramebufferPixels` (BGRA8888 + stride). Feature code never sees a
RoyalVNCKit type.

`FramebufferRenderer` (Metal, `MTKView` via `UIViewRepresentable`) keeps one
`bgra8Unorm` texture, uploads dirty rects with `replaceRegion`, and draws an
aspect-fitted quad with a runtime-compiled shader. The view is paused with
`enableSetNeedsDisplay`, so nothing draws while the remote screen is idle.
Frames are never persisted to disk.

### Session UI (functional, not polished)

System navigation retained. Once the first framebuffer arrives the Metal
view replaces the progress placeholder; a tap sends one primary click at the
Fit-mapped coordinate (`FramebufferFitMapper`), and a bottom-bar
"Send key (a)" debug control proves the key path. A minimal alert prompts
for a password when none is stored. The full trackpad/keyboard experience is
a later gate.

### Adapter-contract tests

`MiniRFBServer` (test fixture) is a ~250-line RFB 3.8 server on 127.0.0.1
that offers either VNC auth or security type None, answers the first
framebuffer request with one raw rect, and records pointer/key messages.
Contract tests drive the production adapter against it: refused port →
VNC-001, None → rejected with VNC-002, VNC-auth happy path → pixels +
pointer + key on the wire + clean disconnect (held inputs released). The
loopback destination is only reachable through an internal, test-only
constructor seam; the production policy is untouched. No CI test needs a
live Mac.

### Still pending after Gate 2

Real SFTP via `CitadelSFTPAdapter` (host-key verification through
`SSHHostKeyStore`; `acceptAnything`-style validators are forbidden in
release paths), a real Keychain-backed `CredentialStore` (Gate 2 still uses
the in-memory store), clipboard, file transfer, and the full input/keyboard
experience.
