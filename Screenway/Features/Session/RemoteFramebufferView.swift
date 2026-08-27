import SwiftUI
import MetalKit

/// SwiftUI wrapper around the Metal framebuffer view. Owns no state — the
/// session model owns the renderer and feeds it framebuffer events.
struct RemoteFramebufferView: UIViewRepresentable {
    let renderer: FramebufferRenderer

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.isUserInteractionEnabled = false // Gestures live on the SwiftUI layer.
        renderer.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}
