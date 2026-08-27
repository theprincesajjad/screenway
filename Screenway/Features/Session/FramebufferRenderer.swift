import Foundation
import MetalKit

/// Renders the remote framebuffer: one BGRA texture updated with dirty-rect
/// uploads, drawn as an aspect-fitted quad. Drawing is demand-driven — the
/// MTKView is paused and only redrawn after a texture change (nothing is
/// drawn, and no CPU/GPU work happens, while the remote screen is idle).
///
/// Frames live in the texture and the adapter-owned surface only; nothing is
/// ever persisted to disk.
@MainActor
final class FramebufferRenderer: NSObject {
    private let device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private(set) var texture: MTLTexture?
    private weak var view: MTKView?

    var framebufferSize: CGSize? {
        guard let texture else { return nil }
        return CGSize(width: texture.width, height: texture.height)
    }

    var isAvailable: Bool { device != nil }

    override init() {
        self.device = MTLCreateSystemDefaultDevice()
        super.init()
    }

    func attach(to view: MTKView) {
        self.view = view
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        // Demand-driven drawing: paused until a framebuffer change arrives.
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.delegate = self
        preparePipelineIfNeeded()
    }

    /// (Re)creates the framebuffer texture. Rejects out-of-cap geometry
    /// before any allocation.
    func resize(width: Int, height: Int) {
        guard let device,
              FramebufferLimits.isValidSurface(width: width, height: height, bytesPerPixel: 4)
        else {
            texture = nil
            return
        }
        if let texture, texture.width == width, texture.height == height { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        #if targetEnvironment(simulator)
        descriptor.storageMode = .shared
        #endif
        texture = device.makeTexture(descriptor: descriptor)
        requestRedraw()
    }

    /// Uploads one dirty rectangle. All geometry is validated against the
    /// texture before `replaceRegion`.
    func apply(_ update: FramebufferUpdate) {
        guard let texture, let pixels = update.pixels else { return }
        guard pixels.format == .bgra8888,
              FramebufferLimits.isValidRect(
                x: update.x, y: update.y, width: update.width, height: update.height,
                surfaceWidth: texture.width, surfaceHeight: texture.height
              ),
              FramebufferLimits.isValidPayload(pixels, width: update.width, height: update.height)
        else { return }

        let region = MTLRegionMake2D(update.x, update.y, update.width, update.height)
        pixels.data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            texture.replace(region: region, mipmapLevel: 0, withBytes: baseAddress, bytesPerRow: pixels.bytesPerRow)
        }
        requestRedraw()
    }

    private func requestRedraw() {
        view?.setNeedsDisplay()
    }

    private func preparePipelineIfNeeded() {
        guard pipelineState == nil, let device else { return }
        commandQueue = device.makeCommandQueue()
        // Compiled at runtime so the repo needs no .metal build phase; this
        // is a one-time cost per session screen.
        guard let library = try? device.makeLibrary(source: Self.shaderSource, options: nil),
              let vertexFunction = library.makeFunction(name: "screenway_framebuffer_vertex"),
              let fragmentFunction = library.makeFunction(name: "screenway_framebuffer_fragment")
        else { return }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct FramebufferVertexOut {
        float4 position [[position]];
        float2 texCoord;
    };

    vertex FramebufferVertexOut screenway_framebuffer_vertex(
        uint vertexID [[vertex_id]],
        constant float2 &fitScale [[buffer(0)]]
    ) {
        float2 positions[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
        float2 texCoords[4] = { float2(0, 1), float2(1, 1), float2(0, 0), float2(1, 0) };
        FramebufferVertexOut out;
        out.position = float4(positions[vertexID] * fitScale, 0, 1);
        out.texCoord = texCoords[vertexID];
        return out;
    }

    fragment float4 screenway_framebuffer_fragment(
        FramebufferVertexOut in [[stage_in]],
        texture2d<float> framebuffer [[texture(0)]]
    ) {
        constexpr sampler linearSampler(mag_filter::linear, min_filter::linear);
        return float4(framebuffer.sample(linearSampler, in.texCoord).rgb, 1.0);
    }
    """
}

extension FramebufferRenderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        view.setNeedsDisplay()
    }

    func draw(in view: MTKView) {
        guard let commandQueue,
              let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        if let pipelineState, let texture {
            let bounds = view.drawableSize
            let fitted = FramebufferFitMapper.fittedRect(
                framebufferSize: CGSize(width: texture.width, height: texture.height),
                in: bounds
            )
            if let fitted {
                var fitScale = SIMD2<Float>(
                    Float(fitted.width / bounds.width),
                    Float(fitted.height / bounds.height)
                )
                encoder.setRenderPipelineState(pipelineState)
                encoder.setVertexBytes(&fitScale, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
                encoder.setFragmentTexture(texture, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
        }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
