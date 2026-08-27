import CoreGraphics
import Testing
@testable import Screenway

@Suite("Framebuffer fit mapping")
struct FramebufferFitMapperTests {
    @Test("A wide framebuffer letterboxes vertically")
    func letterboxesVertically() throws {
        let fitted = try #require(FramebufferFitMapper.fittedRect(
            framebufferSize: CGSize(width: 200, height: 100),
            in: CGSize(width: 100, height: 100)
        ))
        #expect(fitted == CGRect(x: 0, y: 25, width: 100, height: 50))
    }

    @Test("A tall framebuffer letterboxes horizontally")
    func letterboxesHorizontally() throws {
        let fitted = try #require(FramebufferFitMapper.fittedRect(
            framebufferSize: CGSize(width: 100, height: 200),
            in: CGSize(width: 100, height: 100)
        ))
        #expect(fitted == CGRect(x: 25, y: 0, width: 50, height: 100))
    }

    @Test("Degenerate sizes return nil")
    func degenerateSizes() {
        #expect(FramebufferFitMapper.fittedRect(framebufferSize: .zero, in: CGSize(width: 10, height: 10)) == nil)
        #expect(FramebufferFitMapper.fittedRect(framebufferSize: CGSize(width: 10, height: 10), in: .zero) == nil)
    }

    @Test("A centered tap maps to the framebuffer center")
    func centerTap() throws {
        let mapped = try #require(FramebufferFitMapper.framebufferPoint(
            fromViewPoint: CGPoint(x: 50, y: 50),
            framebufferSize: CGSize(width: 2000, height: 1000),
            viewBounds: CGSize(width: 100, height: 100)
        ))
        #expect(mapped.x == 1000)
        #expect(mapped.y == 500)
    }

    @Test("Taps in the letterbox bars are ignored")
    func letterboxTapIgnored() {
        // 2:1 framebuffer in a square view: bars above y<25 and below y>75.
        let mapped = FramebufferFitMapper.framebufferPoint(
            fromViewPoint: CGPoint(x: 50, y: 10),
            framebufferSize: CGSize(width: 2000, height: 1000),
            viewBounds: CGSize(width: 100, height: 100)
        )
        #expect(mapped == nil)
    }

    @Test("Edge taps clamp inside the framebuffer")
    func edgeTapClamps() throws {
        let mapped = try #require(FramebufferFitMapper.framebufferPoint(
            fromViewPoint: CGPoint(x: 99.999, y: 74.999),
            framebufferSize: CGSize(width: 2000, height: 1000),
            viewBounds: CGSize(width: 100, height: 100)
        ))
        #expect(mapped.x <= 1999)
        #expect(mapped.y <= 999)
    }
}
