import Foundation
import Testing
@testable import Screenway

@Suite("Framebuffer safety limits")
struct FramebufferLimitsTests {
    @Test("Ordinary Mac screen sizes are valid")
    func acceptsNormalSurfaces() {
        #expect(FramebufferLimits.isValidSurface(width: 1920, height: 1080, bytesPerPixel: 4))
        #expect(FramebufferLimits.isValidSurface(width: 6016, height: 3384, bytesPerPixel: 4)) // Pro Display XDR
        #expect(FramebufferLimits.isValidSurface(width: 1, height: 1, bytesPerPixel: 4))
    }

    @Test("Surfaces over 16384 px per side are rejected before allocation")
    func rejectsOversidedSurfaces() {
        #expect(!FramebufferLimits.isValidSurface(width: 16_385, height: 100, bytesPerPixel: 4))
        #expect(!FramebufferLimits.isValidSurface(width: 100, height: 16_385, bytesPerPixel: 4))
        #expect(FramebufferLimits.isValidSurface(width: 16_384, height: 4096, bytesPerPixel: 4))
    }

    @Test("Surfaces over 512 MiB decoded are rejected before allocation")
    func rejectsOversizedBytes() {
        // 16384 * 16384 * 4 = 1 GiB > 512 MiB cap.
        #expect(!FramebufferLimits.isValidSurface(width: 16_384, height: 16_384, bytesPerPixel: 4))
        // 16384 * 8192 * 4 = exactly 512 MiB.
        #expect(FramebufferLimits.isValidSurface(width: 16_384, height: 8_192, bytesPerPixel: 4))
    }

    @Test("Zero, negative, and absurd inputs are rejected")
    func rejectsDegenerateSurfaces() {
        #expect(!FramebufferLimits.isValidSurface(width: 0, height: 100, bytesPerPixel: 4))
        #expect(!FramebufferLimits.isValidSurface(width: -1, height: 100, bytesPerPixel: 4))
        #expect(!FramebufferLimits.isValidSurface(width: 100, height: 100, bytesPerPixel: 0))
        #expect(!FramebufferLimits.isValidSurface(width: Int.max, height: Int.max, bytesPerPixel: 8))
    }

    @Test("Dirty rects must lie fully inside the surface")
    func rectBounds() {
        #expect(FramebufferLimits.isValidRect(x: 0, y: 0, width: 100, height: 100, surfaceWidth: 100, surfaceHeight: 100))
        #expect(FramebufferLimits.isValidRect(x: 99, y: 99, width: 1, height: 1, surfaceWidth: 100, surfaceHeight: 100))
        #expect(!FramebufferLimits.isValidRect(x: 1, y: 0, width: 100, height: 100, surfaceWidth: 100, surfaceHeight: 100))
        #expect(!FramebufferLimits.isValidRect(x: -1, y: 0, width: 10, height: 10, surfaceWidth: 100, surfaceHeight: 100))
        #expect(!FramebufferLimits.isValidRect(x: 0, y: 0, width: 0, height: 10, surfaceWidth: 100, surfaceHeight: 100))
    }

    @Test("Pixel payloads must match their declared geometry")
    func payloadConsistency() {
        let good = FramebufferPixels(format: .bgra8888, bytesPerRow: 40, data: Data(count: 40 * 10))
        #expect(FramebufferLimits.isValidPayload(good, width: 10, height: 10))

        let short = FramebufferPixels(format: .bgra8888, bytesPerRow: 40, data: Data(count: 39 * 10))
        #expect(!FramebufferLimits.isValidPayload(short, width: 10, height: 10))

        let strideTooSmall = FramebufferPixels(format: .bgra8888, bytesPerRow: 39, data: Data(count: 39 * 10))
        #expect(!FramebufferLimits.isValidPayload(strideTooSmall, width: 10, height: 10))
    }
}
