import Foundation

/// Gate 2+: text clipboard sync between device and Mac over the RFB channel
/// (`sendClipboardText` / `clipboardTextReceived`). Error surface: CLIP-001
/// (clipboard has no text) and CLIP-002 (Mac rejected paste).
enum ClipboardFeature {
    static let plannedGate = 2
}
