# Setup (high level)

## What you need

- A Mac (macOS Sequoia or later recommended) you own or administer.
- An iPhone or iPad on iOS/iPadOS 18 or later.
- A [Tailscale](https://tailscale.com) account with both devices signed in to
  the same tailnet. Screenway does not replace Tailscale and is not
  affiliated with Tailscale Inc.

## On the Mac

1. Install Tailscale and sign in; confirm the Mac appears in your tailnet.
2. Turn on **Screen Sharing**: System Settings > General > Sharing >
   Screen Sharing.
3. Optional, for file access: turn on **Remote Login** (same Sharing pane).
4. Note the Mac's Tailscale machine name (like `my-mac.tailnet-name.ts.net`)
   or its `100.x.y.z` address from the Tailscale menu.

## On the iPhone/iPad

1. Install the Tailscale app and sign in to the same tailnet.
2. Build and run Screenway (see README — Gate 1 is not on the App Store).
3. Tap **Add a Mac**, enter a name and the Tailscale address, choose how you
   sign in, and save.

## Gate 1 reality check

In the current Gate 1 build, "Test Connection" and "Connect" exercise a mock
client — no real Screen Sharing or SFTP connection is made yet. The full
connect path arrives in Gate 2.
