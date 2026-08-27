import CoreGraphics

/// Pure aspect-fit math shared by the Metal renderer (quad scaling) and the
/// tap-to-pointer mapping. Kit-free and unit-tested.
enum FramebufferFitMapper {
    /// The rect the framebuffer occupies inside `bounds` under Fit scaling.
    static func fittedRect(framebufferSize: CGSize, in bounds: CGSize) -> CGRect? {
        guard framebufferSize.width > 0, framebufferSize.height > 0,
              bounds.width > 0, bounds.height > 0
        else { return nil }
        let scale = min(bounds.width / framebufferSize.width, bounds.height / framebufferSize.height)
        let fittedSize = CGSize(width: framebufferSize.width * scale, height: framebufferSize.height * scale)
        let origin = CGPoint(
            x: (bounds.width - fittedSize.width) / 2,
            y: (bounds.height - fittedSize.height) / 2
        )
        return CGRect(origin: origin, size: fittedSize)
    }

    /// Maps a tap in view coordinates to framebuffer pixel coordinates.
    /// Returns nil for taps outside the fitted framebuffer (letterbox bars).
    static func framebufferPoint(
        fromViewPoint point: CGPoint,
        framebufferSize: CGSize,
        viewBounds: CGSize
    ) -> (x: Int, y: Int)? {
        guard let fitted = fittedRect(framebufferSize: framebufferSize, in: viewBounds),
              fitted.contains(point)
        else { return nil }
        let normalizedX = (point.x - fitted.minX) / fitted.width
        let normalizedY = (point.y - fitted.minY) / fitted.height
        let x = min(Int(normalizedX * framebufferSize.width), Int(framebufferSize.width) - 1)
        let y = min(Int(normalizedY * framebufferSize.height), Int(framebufferSize.height) - 1)
        return (max(0, x), max(0, y))
    }
}
