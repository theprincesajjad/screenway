# Third-Party Notices

Recorded 2026-08-26. Screenway is MIT-licensed; the dependencies below are
pinned in `Screenway.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
No analytics SDKs, no vendor network SDKs, no nonpermissive licenses.

## Direct dependencies

| Package | Version pinned | Source | License |
| --- | --- | --- | --- |
| RoyalVNCKit | 1.1.0 (tag commit `92d4427c73817d8f849bb289ff190aa4b40c44ea`) | https://github.com/royalapplications/royalvnc | MIT |
| Citadel | 0.12.1 (exact) | https://github.com/orlandos-nl/Citadel | MIT |

Note on the RoyalVNCKit pin: the 1.1.0 release manifest depends on a branch of
a CryptoSwift fork, and Swift Package Manager forbids exact-*version*
requirements on packages with branch dependencies. RoyalVNCKit is therefore
pinned to the exact commit that tag `1.1.0` points to, which is equivalent to
an exact 1.1.0 pin. See docs/ARCHITECTURE.md for details.

## Transitive dependencies (resolved 2026-08-26)

| Package | Version | Source | License |
| --- | --- | --- | --- |
| CryptoSwift (Royal Apps fork) | branch `foundationessentials` @ `a59b4d91` | https://github.com/royalapplications/CryptoSwift | zlib-style (CryptoSwift license) |
| swift-nio-ssh (fork used by Citadel) | 0.3.6 | https://github.com/Wellz26/swift-nio-ssh | Apache-2.0 |
| swift-nio | 2.101.3 | https://github.com/apple/swift-nio | Apache-2.0 |
| swift-crypto | 3.15.1 | https://github.com/apple/swift-crypto | Apache-2.0 |
| swift-asn1 | 1.7.1 | https://github.com/apple/swift-asn1 | Apache-2.0 |
| swift-atomics | 1.3.1 | https://github.com/apple/swift-atomics | Apache-2.0 |
| swift-collections | 1.6.0 | https://github.com/apple/swift-collections | Apache-2.0 |
| swift-log | 1.15.0 | https://github.com/apple/swift-log | Apache-2.0 |
| swift-system | 1.8.1 | https://github.com/apple/swift-system | Apache-2.0 |
| BigInt | 5.7.0 | https://github.com/attaswift/BigInt | MIT |
| swift-jpeg | 2.1.0 | https://github.com/tayloraswift/swift-jpeg | Apache-2.0 |
| swift-png | 4.5.1 | https://github.com/tayloraswift/swift-png | Apache-2.0 |
| h | 1.0.1 | https://github.com/rarestype/h | Apache-2.0 |

`swift-jpeg`, `swift-png`, and `h` are conditional dependencies of RoyalVNCKit
that are only linked on Linux/Windows/Android; they are resolved but not
linked into the iOS app.

## Trademarks

Tailscale is a trademark of Tailscale Inc. Screenway is not affiliated with or
endorsed by Tailscale Inc. Screenway does not embed the Tailscale SDK, does not
use the Tailscale API, and does not use Tailscale marks in its bundle
identifier or icon.
