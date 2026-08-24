#if !arch(x86_64)
import Cocoa
import GeometryLite3D
import MetalSprocketsGaussianSplats
import MetalSprocketsGaussianSplatShaders
import MetalSprocketsSupport
import QuickLookUI
import simd
import Splats
import SwiftUI
import UniformTypeIdentifiers

class PreviewViewController: NSViewController, QLPreviewingController {
    // swiftlint:disable:next async_without_await
    func preparePreviewOfFile(at url: URL) async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw NSError(domain: "PreviewViewController", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Metal device available"])
        }

        let modelMatrix = simd_float4x4(xRotation: .radians(.pi))
        let result = try SplatLoader.read(device: device, url: url)
        let splatCloud = GPUSplatCloud(result, modelTransform: modelMatrix)
        // Create and host the SwiftUI view
        let previewView = try SplatPreviewView(splatCloud: splatCloud)
        let hostingView = NSHostingView(rootView: previewView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
#endif
