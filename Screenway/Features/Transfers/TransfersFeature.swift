import Foundation

/// Gate 2+: resumable uploads/downloads driven by `TransferCheckpoint`.
/// Error surface: FILE-001 (space), FILE-003 (source changed).
enum TransfersFeature {
    static let plannedGate = 2
}
