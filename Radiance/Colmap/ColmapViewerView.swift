import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsSupport
import MetalSprocketsUI
import simd
import SwiftUI
import UniformTypeIdentifiers

struct ColmapViewerView: View {
    @State private var scene: ColmapScene?
    @State private var pointBuffer: MTLBuffer?
    @State private var pointCount: Int = 0
    @State private var frustumBuffer: MTLBuffer?
    @State private var frustumCount: Int = 0
    @State private var sceneCenter: SIMD3<Float> = .zero
    @State private var sceneRadius: Float = 10.0
    @State private var pointSize: Float = 4.0
    @State private var loadError: String?

    // Orbit camera state
    @State private var orbitYaw: Float = .pi / 4
    @State private var orbitPitch: Float = 0.3
    @State private var orbitDistance: Float = 15.0
    @State private var dragStart: CGPoint?
    @State private var yawAtDragStart: Float = 0
    @State private var pitchAtDragStart: Float = 0

    @State private var showFilePicker = false

    private let device = MTLCreateSystemDefaultDevice()!

    var body: some View {
        Group {
            if scene != nil {
                sceneView
            } else {
                emptyStateView
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    loadScene(from: url)
                }

            case .failure(let error):
                loadError = error.localizedDescription
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else {
                return false
            }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    Task { @MainActor in
                        loadScene(from: url)
                    }
                }
            }
            return true
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.metering.matrix")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Drop a COLMAP sparse folder here")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Folder should contain points3D.bin, images.bin, cameras.bin")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button("Open Folder…") {
                showFilePicker = true
            }
            .buttonStyle(.borderedProminent)
            if let loadError {
                Text(loadError)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private var sceneView: some View {
        ZStack {
            renderView
                .ignoresSafeArea()
                .metalDepthStencilPixelFormat(.depth32Float)
                .metalSampleCount(4)
                .metalClearColor(.init(red: 0.08, green: 0.08, blue: 0.1, alpha: 1.0))
                .gesture(dragGesture)
                .gesture(magnifyGesture)
        }
        .overlay(alignment: .bottomLeading) {
            if let scene {
                VStack(alignment: .leading) {
                    Text("\(scene.points.count) points, \(scene.images.count) cameras")
                    HStack {
                        Text("Point size:")
                        Slider(value: $pointSize, in: 1...20)
                            .frame(width: 150)
                        Text(pointSize.formatted(.number.precision(.fractionLength(0))))
                    }
                }
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.white)
                .padding()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Open Folder…", systemImage: "folder") {
                    showFilePicker = true
                }
            }
        }
    }

    private var renderView: some View {
        RenderView { _, size in
            let projection = PerspectiveProjection(verticalAngleOfView: .degrees(45), depthMode: .standard(zClip: 0.01 ... 1_000))
            let projectionMatrix = projection.projectionMatrix(for: size)
            let viewMatrix = LookAt(position: orbitCameraPosition, target: sceneCenter, up: [0, 1, 0]).viewMatrix
            let transform = projectionMatrix * viewMatrix

            try RenderPass {
                if let pointBuffer, pointCount > 0 {
                    try PointCloudElement(transform: transform, vertexBuffer: pointBuffer, vertexCount: pointCount, pointSize: pointSize)
                }
                if let frustumBuffer, frustumCount > 0 {
                    try LineElement(transform: transform, vertexBuffer: frustumBuffer, vertexCount: frustumCount)
                }
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStart == nil {
                    dragStart = value.startLocation
                    yawAtDragStart = orbitYaw
                    pitchAtDragStart = orbitPitch
                }
                let dx = Float(value.location.x - value.startLocation.x)
                let dy = Float(value.location.y - value.startLocation.y)
                orbitYaw = yawAtDragStart + dx * 0.005
                orbitPitch = max(-Float.pi / 2 + 0.01, min(Float.pi / 2 - 0.01, pitchAtDragStart + dy * 0.005))
            }
            .onEnded { _ in
                dragStart = nil
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                orbitDistance = max(0.1, orbitDistance / Float(value.magnification))
            }
    }

    private var orbitCameraPosition: SIMD3<Float> {
        let x = orbitDistance * cos(orbitPitch) * sin(orbitYaw)
        let y = orbitDistance * sin(orbitPitch)
        let z = orbitDistance * cos(orbitPitch) * cos(orbitYaw)
        return sceneCenter + SIMD3<Float>(x, y, z)
    }

    private func loadScene(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let loadedScene = try ColmapParser.load(directory: url)
            scene = loadedScene
            loadError = nil

            let bb = loadedScene.boundingBox
            sceneCenter = loadedScene.center
            let extent = bb.max - bb.min
            sceneRadius = simd_length(extent) / 2
            orbitDistance = sceneRadius * 2.5

            // Reset camera
            orbitYaw = .pi / 4
            orbitPitch = 0.3

            // Build Metal buffers
            var pointVerts = buildPointVertices(from: loadedScene)
            pointCount = pointVerts.count
            pointBuffer = device.makeBuffer(bytes: &pointVerts, length: MemoryLayout<PointVertex>.stride * pointVerts.count, options: .storageModeShared)

            let frustumScale = max(sceneRadius * 0.1, 1.0)
            var frustumVerts = buildCameraFrustumVertices(from: loadedScene, frustumScale: frustumScale)
            frustumCount = frustumVerts.count
            if !frustumVerts.isEmpty {
                frustumBuffer = device.makeBuffer(bytes: &frustumVerts, length: MemoryLayout<LineVertex>.stride * frustumVerts.count, options: .storageModeShared)
            }
        } catch {
            loadError = error.localizedDescription
        }
    }
}

#Preview {
    ColmapViewerView()
}
