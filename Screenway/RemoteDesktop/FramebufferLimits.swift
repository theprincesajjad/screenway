import Foundation

/// Hard safety caps for remote framebuffers. Everything is validated
/// *before* any allocation happens: the adapter installs an allocator that
/// refuses oversized surfaces, and the renderer re-checks dimensions and
/// rectangle bounds before creating or writing a texture.
public enum FramebufferLimits {
    /// Maximum framebuffer edge in pixels.
    public static let maxSidePixels = 16_384
    /// Maximum decoded framebuffer size in bytes (512 MiB).
    public static let maxDecodedBytes = 512 * 1024 * 1024

    /// True when a full framebuffer of the given geometry may be allocated.
    public static func isValidSurface(width: Int, height: Int, bytesPerPixel: Int) -> Bool {
        guard width > 0, height > 0,
              width <= maxSidePixels, height <= maxSidePixels,
              bytesPerPixel > 0, bytesPerPixel <= 8
        else { return false }
        // Multiplication cannot overflow after the caps above (fits in Int64),
        // but stay explicit anyway.
        let (rowBytes, rowOverflow) = width.multipliedReportingOverflow(by: bytesPerPixel)
        guard !rowOverflow else { return false }
        let (total, totalOverflow) = rowBytes.multipliedReportingOverflow(by: height)
        guard !totalOverflow else { return false }
        return total <= maxDecodedBytes
    }

    /// True when a dirty rectangle lies fully inside a surface of
    /// `surfaceWidth` x `surfaceHeight` and its payload is consistent.
    public static func isValidRect(
        x: Int, y: Int, width: Int, height: Int,
        surfaceWidth: Int, surfaceHeight: Int
    ) -> Bool {
        guard x >= 0, y >= 0, width > 0, height > 0 else { return false }
        guard x <= surfaceWidth - width, y <= surfaceHeight - height else { return false }
        return true
    }

    /// True when a pixel payload matches its declared rectangle geometry.
    public static func isValidPayload(_ pixels: FramebufferPixels, width: Int, height: Int) -> Bool {
        let bytesPerPixel = pixels.format.bytesPerPixel
        guard width > 0, height > 0,
              pixels.bytesPerRow >= width * bytesPerPixel,
              pixels.bytesPerRow <= maxSidePixels * bytesPerPixel
        else { return false }
        return pixels.data.count == pixels.bytesPerRow * height
    }
}
