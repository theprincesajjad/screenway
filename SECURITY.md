# Security Policy

## Reporting a vulnerability

Please report security issues privately via GitHub's
["Report a vulnerability"](https://github.com/theprincesajjad/screenway/security/advisories/new)
flow rather than opening a public issue. You should receive an acknowledgement
within a week. Please include reproduction steps and the impact you believe
the issue has.

## Scope and security model

Screenway is a client that connects to the user's own Macs over the user's
own Tailscale network. There is no Screenway server component.

Invariants the codebase commits to:

- **Secrets stay in the keychain.** VNC and SSH passwords are stored only via
  the `CredentialStore` abstraction (keychain-backed in release builds) and
  are referenced from profiles by opaque credential IDs. Secrets are never
  written to SwiftData, UserDefaults, logs, or disk. Deleting a profile
  deletes its credentials (unit-tested).
- **Destination policy.** Connections are only permitted to Tailscale
  addresses: IPv4 `100.64.0.0/10`, IPv6 `fd7a:115c:a1e0::/48`, or names that
  resolve exclusively to those ranges. Loopback, link-local, public internet,
  and ordinary private LAN destinations are rejected by default (unit-tested).
- **SSH host keys are trust-on-first-use.** A changed host key is a hard stop
  (error SSH-003) — never a silent reconnect, and never "accept anything"
  validation in release paths.
- **No telemetry.** The app makes no network connections other than the ones
  the user explicitly configures.

## Gate 1 note

The current code ships mock transport clients only; no real VNC/SFTP
connections are made yet. Security-sensitive code paths (real keychain use,
host-key verification against live servers, TLS/RFB security types) arrive in
Gate 2 and will be reviewed against the invariants above.
