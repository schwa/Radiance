#if os(iOS) || os(macOS)
import GeometryLite3D
import Interaction3D
import MetalSprockets
import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import MetalSprocketsGaussianSplats
import MetalSprocketsGaussianSplatsDebug
import MetalSprocketsGaussianSplatShaders
import MetalSprocketsSupport
import MetalSprocketsUI
import simd
import Splats
import SwiftUI

// MARK: - Splat Render View

/// A unified content view for rendering splat clouds, used by both single-document and multi-cloud scene views
struct SplatRenderView: View {
    let mode: SplatContentMode
    let clouds: [GPUSplatCloud<SparkSplat>]
    let sceneTransform: simd_float4x4
    let useSphericalHarmonics: Bool
    let backgroundColor: [Float]

    @Binding var cameraMatrix: simd_float4x4
    @Binding var verticalAngleOfView: Double
    let nearClip: Double
    let farClip: Double

    var cullBoundingBox: BoundingBox3D?
    var showBoundingBoxes: Bool = false
    var showReferenceGrid: Bool = false
    var showAxisLines: Bool = false
    var gridColor: Color = .white
    var boundingBoxInfos: [BoundingBoxInfo] = []

    // Debug rendering (nil = normal rendering, non-nil = debug mode)
    var debugParams: DebugParams?

    var sortManager: AsyncSortManager<SparkSplat>?

    // Camera mode for selecting the appropriate controller
    var cameraMode: CameraMode = .object

    // Drag handling for multi-cloud mode
    var onDragChange: ((UUID, Int, CGSize, simd_float4x4, simd_float4x4) -> Void)?
    var onDragEnd: ((UUID) -> Void)?

    var body: some View {
        ZStack {
            SplatRenderingView(
                mode: mode,
                clouds: clouds,
                sceneTransform: sceneTransform,
                useSphericalHarmonics: useSphericalHarmonics,
                backgroundColor: backgroundColor,
                cameraMatrix: $cameraMatrix,
                verticalAngleOfView: $verticalAngleOfView,
                nearClip: nearClip,
                farClip: farClip,
                cullBoundingBox: cullBoundingBox,
                showReferenceGrid: showReferenceGrid,
                showAxisLines: showAxisLines,
                showBoundingBoxes: showBoundingBoxes,
                gridColor: gridColor,
                boundingBoxInfos: boundingBoxInfos,
                debugParams: debugParams,
                sortManager: sortManager,
                cameraMode: cameraMode
            )
            if showBoundingBoxes {
                SplatBoundingBoxOverlayView(
                    boundingBoxInfos: boundingBoxInfos,
                    cameraMatrix: cameraMatrix,
                    verticalAngleOfView: verticalAngleOfView,
                    nearClip: nearClip,
                    farClip: farClip,
                    onDragChange: onDragChange,
                    onDragEnd: onDragEnd
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay {
            if clouds.isEmpty {
                switch mode {
                case .single:
                    ContentUnavailableView("No splat cloud loaded", systemImage: "cube.transparent")
                        .background(.ultraThinMaterial)

                case .multi:
                    ContentUnavailableView {
                        Label("All Clouds Hidden", systemImage: "eye.slash")
                    } description: {
                        Text("Enable clouds in the sidebar to view")
                    }
                    .background(.ultraThinMaterial)
                }
            }
        }
    }
}

private struct SplatRenderingView: View {
    let mode: SplatContentMode
    let clouds: [GPUSplatCloud<SparkSplat>]
    let sceneTransform: simd_float4x4
    let useSphericalHarmonics: Bool
    let backgroundColor: [Float]
    @Binding var cameraMatrix: simd_float4x4
    @Binding var verticalAngleOfView: Double
    let nearClip: Double
    let farClip: Double
    var cullBoundingBox: BoundingBox3D?
    let showReferenceGrid: Bool
    let showAxisLines: Bool
    let showBoundingBoxes: Bool
    let gridColor: Color
    let boundingBoxInfos: [BoundingBoxInfo]
    var debugParams: DebugParams?
    var sortManager: AsyncSortManager<SparkSplat>?
    let cameraMode: CameraMode
    @Environment(SplatViewModel.self) private var viewModel

    private var clearColor: MTLClearColor {
        guard backgroundColor.count == 4 else {
            return MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        }
        return MTLClearColor(
            red: Double(backgroundColor[0]),
            green: Double(backgroundColor[1]),
            blue: Double(backgroundColor[2]),
            alpha: Double(backgroundColor[3])
        )
    }
    @ViewBuilder
    var body: some View {
        if mode == .single, let cloud = clouds.first, let debugParams {
            cameraController(for: SingleCloudDebugRenderView(
                splatCloud: cloud,
                cameraMatrix: cameraMatrix,
                modelMatrix: sceneTransform,
                verticalAngleOfView: verticalAngleOfView,
                nearClip: nearClip,
                farClip: farClip,
                debugParams: debugParams
            )
            .metalColorPixelFormat(.bgra8Unorm_srgb)
            .metalClearColor(clearColor))
        } else if mode == .single, let cloud = clouds.first {
            cameraController(for: SingleCloudGuidedRenderView(
                splatCloud: cloud,
                cameraMatrix: cameraMatrix,
                modelMatrix: sceneTransform,
                verticalAngleOfView: verticalAngleOfView,
                nearClip: nearClip,
                farClip: farClip,
                useSphericalHarmonics: useSphericalHarmonics,
                renderer: viewModel.renderer,
                gridColor: gridColor,
                showGrid: showReferenceGrid,
                showAxes: showAxisLines,
                boundingBoxes: [],
                onFrame: viewModel.recordFrame,
            )
            .metalColorPixelFormat(.bgra8Unorm_srgb)
            .metalClearColor(clearColor)
            .metalDepthStencilPixelFormat(.depth32Float))
        } else if let sortManager {
            cameraController(for: MultiCloudRenderView(
                clouds: clouds,
                cameraMatrix: cameraMatrix,
                sceneTransform: sceneTransform,
                verticalAngleOfView: verticalAngleOfView,
                nearClip: nearClip,
                farClip: farClip,
                useSphericalHarmonics: useSphericalHarmonics,
                gridColor: gridColor,
                showGrid: showReferenceGrid,
                showAxes: showAxisLines,
                backgroundColor: backgroundColor,
                cullBoundingBox: cullBoundingBox,
                sortManager: sortManager,
                debugParams: debugParams,
                onFrame: viewModel.recordFrame,
                onDrawableSizeChange: { size in
                    if viewModel.viewSize != size {
                        viewModel.viewSize = size
                    }
                },
                sortingEnabled: viewModel.sortingEnabled
            ))
        }
    }

    @ViewBuilder
    private func cameraController<Content: View>(for content: Content) -> some View {
        switch cameraMode {
        case .object:
            content.interactiveCamera(cameraMatrix: $cameraMatrix, mode: .turntable())

        case .room:
            content.roomCameraController(cameraMatrix: $cameraMatrix, cameraHeight: 0)

        case .spatialScene:
            content.modifier(SpatialSceneCameraController(transform: $cameraMatrix))
        }
    }
}

private struct SingleCloudGuidedRenderView: View {
    let splatCloud: GPUSplatCloud<SparkSplat>
    let cameraMatrix: simd_float4x4
    let modelMatrix: simd_float4x4
    let verticalAngleOfView: Double
    let nearClip: Double
    let farClip: Double
    let useSphericalHarmonics: Bool
    let renderer: SplatRenderer
    let gridColor: Color
    let showGrid: Bool
    let showAxes: Bool
    let boundingBoxes: [BoundingBoxInfo]
    let onFrame: () -> Void

    @State private var sortedIndices: SplatIndices?
    @State private var sortManager: AsyncSortManager<SparkSplat>
    @State private var stochasticSeed: UInt32 = 0
    @State private var pointSplatStatistics = PointSplatStatistics()
    @State private var resources: GPUSortResources

    init(splatCloud: GPUSplatCloud<SparkSplat>, cameraMatrix: simd_float4x4, modelMatrix: simd_float4x4, verticalAngleOfView: Double, nearClip: Double, farClip: Double, useSphericalHarmonics: Bool, renderer: SplatRenderer, gridColor: Color, showGrid: Bool, showAxes: Bool, boundingBoxes: [BoundingBoxInfo], onFrame: @escaping () -> Void) {
        self.splatCloud = splatCloud
        self.cameraMatrix = cameraMatrix
        self.modelMatrix = modelMatrix
        self.verticalAngleOfView = verticalAngleOfView
        self.nearClip = nearClip
        self.farClip = farClip
        self.useSphericalHarmonics = useSphericalHarmonics
        self.renderer = renderer
        self.gridColor = gridColor
        self.showGrid = showGrid
        self.showAxes = showAxes
        self.boundingBoxes = boundingBoxes
        self.onFrame = onFrame

        do {
            let device = splatCloud.splats.unsafeMTLBuffer.device
            _sortManager = State(initialValue: try AsyncSortManager(device: device, splatCloud: splatCloud, capacity: splatCloud.count, preallocatedBufferCount: 6))
            _resources = State(initialValue: try GPUSortResources(device: device, capacity: splatCloud.count))
        } catch {
            fatalError("Failed to create GPU sort resources: \(error)")
        }
    }

    var body: some View {
        let resolvedColor = gridColor.resolve(in: .init())
        let color = SIMD4<Float>(Float(resolvedColor.red), Float(resolvedColor.green), Float(resolvedColor.blue), Float(resolvedColor.opacity))

        RenderView { _, drawableSize in
            let projection = PerspectiveProjection(verticalAngleOfView: .degrees(Float(verticalAngleOfView)), depthMode: .standard(zClip: Float(nearClip) ... Float(farClip)))
            let projectionMatrix = projection.projectionMatrix(for: drawableSize)
            let drawableSize = SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height))

            switch renderer {
            case .sparkCPU:
                if let sortedIndices {
                    try RenderPass {
                        if showGrid {
                            GridShader(projectionMatrix: projectionMatrix, cameraMatrix: cameraMatrix, gridColor: color, backgroundColor: .zero, backfaceColor: .zero)
                        }
                        try SparkSplatRenderPipeline(splatCloud: splatCloud, projectionMatrix: projectionMatrix, modelMatrix: modelMatrix, cameraMatrix: cameraMatrix, drawableSize: drawableSize, configuration: .init(useSphericalHarmonics: useSphericalHarmonics), sortedIndices: sortedIndices)
                        if showAxes {
                            try AxisLinesRenderPipeline(mvpMatrix: projectionMatrix * cameraMatrix.inverse, viewMatrix: cameraMatrix.inverse, projectionMatrix: projectionMatrix, viewportSize: drawableSize)
                        }
                    }
                }

            case .sparkGPU:
                try GuidedSplatRenderPass(splatCloud: splatCloud, projectionMatrix: projectionMatrix, modelMatrix: modelMatrix, cameraMatrix: cameraMatrix, drawableSize: drawableSize, useSphericalHarmonics: useSphericalHarmonics, gridColor: showGrid ? color : nil, showAxes: showAxes, boxes: boxInstances, resources: resources)

            case .tileBased:
                try TileBasedSplatPass(splatCloud: splatCloud, projection: projection, drawableSize: drawableSize, cameraMatrix: cameraMatrix, modelMatrix: modelMatrix)
                SceneGuidesRenderPass(projectionMatrix: projectionMatrix, cameraMatrix: cameraMatrix, drawableSize: drawableSize, gridColor: showGrid ? color : nil, showAxes: showAxes)

            case .stochastic:
                try RenderPass {
                    if showGrid {
                        GridShader(projectionMatrix: projectionMatrix, cameraMatrix: cameraMatrix, gridColor: color, backgroundColor: .zero, backfaceColor: .zero)
                    }
                    try StochasticSplatRenderPipeline(splatCloud: splatCloud, projectionMatrix: projectionMatrix, modelMatrix: modelMatrix, cameraMatrix: cameraMatrix, drawableSize: drawableSize, frameTime: stochasticSeed, useSphericalHarmonics: useSphericalHarmonics)
                        .depthCompare(function: .less, enabled: true)
                    if showAxes {
                        try AxisLinesRenderPipeline(mvpMatrix: projectionMatrix * cameraMatrix.inverse, viewMatrix: cameraMatrix.inverse, projectionMatrix: projectionMatrix, viewportSize: drawableSize)
                    }
                }

            case .pointSplat:
                try PointSplatRenderPipeline(splatCloud: splatCloud, projectionMatrix: projectionMatrix, modelMatrix: modelMatrix, cameraMatrix: cameraMatrix, drawableSize: drawableSize, frameIndex: 0, configuration: .init(depthRange: Float(nearClip) ... Float(farClip), statistics: pointSplatStatistics))
                SceneGuidesRenderPass(projectionMatrix: projectionMatrix, cameraMatrix: cameraMatrix, drawableSize: drawableSize, gridColor: showGrid ? color : nil, showAxes: showAxes)
            }
        }
        .onFrameTimingChange { _ in
            onFrame()
        }
        .task {
            if renderer == .sparkCPU {
                sortManager.requestSort(SortParameters(camera: cameraMatrix, model: modelMatrix))
            }
            for await indices in sortManager.managedSortedIndicesStream(pendingReleaseDepth: 3) {
                sortedIndices = indices
            }
        }
        .onChange(of: cameraMatrix) {
            stochasticSeed &+= 1
            if renderer == .sparkCPU {
                sortManager.requestSort(SortParameters(camera: cameraMatrix, model: modelMatrix))
            }
        }
        .onChange(of: modelMatrix) {
            stochasticSeed &+= 1
            if renderer == .sparkCPU {
                sortManager.requestSort(SortParameters(camera: cameraMatrix, model: modelMatrix))
            }
        }
        .onChange(of: renderer) {
            if renderer == .sparkCPU {
                sortManager.requestSort(SortParameters(camera: cameraMatrix, model: modelMatrix))
            }
        }
    }

    private var boxInstances: [BoxInstance] {
        boundingBoxes.map { info in
            let corners = info.bounds.corners.map { (info.modelMatrix * SIMD4<Float>($0, 1)).xyz }
            let minimum = corners.reduce(SIMD3<Float>(repeating: .greatestFiniteMagnitude), min)
            let maximum = corners.reduce(SIMD3<Float>(repeating: -.greatestFiniteMagnitude), max)
            let resolvedColor = info.color.resolve(in: .init())
            return BoxInstance(min: minimum, max: maximum, color: SIMD4<Float>(Float(resolvedColor.red), Float(resolvedColor.green), Float(resolvedColor.blue), Float(resolvedColor.opacity)))
        }
    }
}

private struct GuidedSplatRenderPass: Element {
    let splatCloud: GPUSplatCloud<SparkSplat>
    let projectionMatrix: simd_float4x4
    let modelMatrix: simd_float4x4
    let cameraMatrix: simd_float4x4
    let drawableSize: SIMD2<Float>
    let useSphericalHarmonics: Bool
    let gridColor: SIMD4<Float>?
    let showAxes: Bool
    let boxes: [BoxInstance]
    let resources: GPUSortResources
    let slotIndex: Int
    let sortedIndices: SplatIndices

    init(splatCloud: GPUSplatCloud<SparkSplat>, projectionMatrix: simd_float4x4, modelMatrix: simd_float4x4, cameraMatrix: simd_float4x4, drawableSize: SIMD2<Float>, useSphericalHarmonics: Bool, gridColor: SIMD4<Float>?, showAxes: Bool, boxes: [BoxInstance], resources: GPUSortResources) throws {
        self.splatCloud = splatCloud
        self.projectionMatrix = projectionMatrix
        self.modelMatrix = modelMatrix
        self.cameraMatrix = cameraMatrix
        self.drawableSize = drawableSize
        self.useSphericalHarmonics = useSphericalHarmonics
        self.gridColor = gridColor
        self.showAxes = showAxes
        self.boxes = boxes
        self.resources = resources
        try resources.ensure(capacity: splatCloud.count)
        slotIndex = resources.advance()
        sortedIndices = resources.makeIndices(slot: slotIndex, count: splatCloud.count, parameters: SortParameters(camera: cameraMatrix, model: modelMatrix))
    }

    var body: some Element {
        get throws {
            try GPUSplatSortComputePass(splatCloud: splatCloud, projectionMatrix: projectionMatrix, modelMatrix: modelMatrix, cameraMatrix: cameraMatrix, resources: resources, slotIndex: slotIndex)
            try RenderPass {
                if let gridColor {
                    GridShader(projectionMatrix: projectionMatrix, cameraMatrix: cameraMatrix, gridColor: gridColor, backgroundColor: .zero, backfaceColor: .zero)
                }
                try SparkSplatRenderPipeline(
                    splatCloud: splatCloud,
                    projectionMatrix: projectionMatrix,
                    modelMatrix: modelMatrix,
                    cameraMatrix: cameraMatrix,
                    drawableSize: drawableSize,
                    configuration: .init(useSphericalHarmonics: useSphericalHarmonics),
                    sortedIndices: sortedIndices
                )
                if showAxes {
                    try AxisLinesRenderPipeline(mvpMatrix: projectionMatrix * cameraMatrix.inverse, viewMatrix: cameraMatrix.inverse, projectionMatrix: projectionMatrix, viewportSize: drawableSize)
                }
                if !boxes.isEmpty {
                    AxisAlignedWireframeBoxesRenderPipeline(mvpMatrix: projectionMatrix * cameraMatrix.inverse, boxes: boxes)
                }
            }
        }
    }
}

private struct SceneGuidesRenderPass: Element {
    let projectionMatrix: simd_float4x4
    let cameraMatrix: simd_float4x4
    let drawableSize: SIMD2<Float>
    let gridColor: SIMD4<Float>?
    let showAxes: Bool

    var body: some Element {
        get throws {
            try RenderPass {
                if let gridColor {
                    GridShader(projectionMatrix: projectionMatrix, cameraMatrix: cameraMatrix, gridColor: gridColor, backgroundColor: .zero, backfaceColor: .zero)
                }
                if showAxes {
                    try AxisLinesRenderPipeline(mvpMatrix: projectionMatrix * cameraMatrix.inverse, viewMatrix: cameraMatrix.inverse, projectionMatrix: projectionMatrix, viewportSize: drawableSize)
                }
            }
        }
    }
}

private struct SplatBoundingBoxOverlayView: View {
    let boundingBoxInfos: [BoundingBoxInfo]
    let cameraMatrix: simd_float4x4
    let verticalAngleOfView: Double
    let nearClip: Double
    let farClip: Double
    var onDragChange: ((UUID, Int, CGSize, simd_float4x4, simd_float4x4) -> Void)?
    var onDragEnd: ((UUID) -> Void)?

    var body: some View {
        GeometryReader { proxy in
            let viewportSize = proxy.size
            let projection = PerspectiveProjection(
                verticalAngleOfView: .degrees(Float(verticalAngleOfView)),
                depthMode: .standard(zClip: Float(nearClip) ... Float(farClip))
            )
            let projectionMatrix = projection.projectionMatrix(for: viewportSize)
            let viewMatrix = cameraMatrix.inverse

            ZStack {
                if let onDragChange, let onDragEnd {
                    BoundingBoxFaceInteraction(
                        boundingBoxes: boundingBoxInfos,
                        viewMatrix: viewMatrix,
                        projectionMatrix: projectionMatrix,
                        viewportSize: viewportSize,
                        onDragChange: { cloudID, axis, screenDelta in
                            onDragChange(cloudID, axis, screenDelta, viewMatrix, projectionMatrix)
                        },
                        onDragEnd: onDragEnd
                    )
                }

                BoundingBoxWireframe(
                    boundingBoxes: boundingBoxInfos,
                    viewMatrix: viewMatrix,
                    projectionMatrix: projectionMatrix,
                    viewportSize: viewportSize
                )
            }
        }
    }
}

private struct SingleCloudDebugRenderView: View {
    let splatCloud: GPUSplatCloud<SparkSplat>
    let cameraMatrix: simd_float4x4
    let modelMatrix: simd_float4x4
    let verticalAngleOfView: Double
    let nearClip: Double
    let farClip: Double
    let debugParams: DebugParams

    @State private var resources: GPUSortResources

    init(splatCloud: GPUSplatCloud<SparkSplat>, cameraMatrix: simd_float4x4, modelMatrix: simd_float4x4, verticalAngleOfView: Double, nearClip: Double, farClip: Double, debugParams: DebugParams) {
        self.splatCloud = splatCloud
        self.cameraMatrix = cameraMatrix
        self.modelMatrix = modelMatrix
        self.verticalAngleOfView = verticalAngleOfView
        self.nearClip = nearClip
        self.farClip = farClip
        self.debugParams = debugParams

        do {
            let device = splatCloud.splats.unsafeMTLBuffer.device
            _resources = State(initialValue: try GPUSortResources(device: device, capacity: splatCloud.count))
        } catch {
            fatalError("Failed to create GPU debug sort resources: \(error)")
        }
    }

    var body: some View {
        RenderView { _, drawableSize in
            let projection = PerspectiveProjection(
                verticalAngleOfView: .degrees(Float(verticalAngleOfView)),
                depthMode: .standard(zClip: Float(nearClip) ... Float(farClip))
            )
            return try GPUSortedSplatDebugRenderPipeline(
                splatCloud: splatCloud,
                projectionMatrix: projection.projectionMatrix(for: drawableSize),
                modelMatrix: modelMatrix,
                cameraMatrix: cameraMatrix,
                drawableSize: SIMD2(Float(drawableSize.width), Float(drawableSize.height)),
                debugParams: debugParams,
                resources: resources
            )
        }
    }
}

// MARK: - Inspector Tab

enum InspectorTab: String, CaseIterable {
    case cloud = "Cloud"
    case scene = "Scene"    // Multi-cloud mode only
    case camera = "Camera"
    case render = "Render"
    case analysis = "Analysis"

    static func tabs(for mode: SplatContentMode) -> [Self] {
        switch mode {
        case .single:
            return [.cloud, .camera, .render, .analysis]

        case .multi:
            return [.scene, .cloud, .camera, .render]
        }
    }
}

// MARK: - Inspector View

struct InspectorView: View {
    let mode: SplatContentMode
    @Bindable var viewModel: SplatViewModel
    @Binding var tab: InspectorTab
    let classifications: [ImageClassification]
    let visionImageAnalysis: VisionImageAnalysis?
    @Binding var highlightsSubjects: Bool
    let imageOrientation: RenderedImageAnalysis.Orientation?
    let imageViewpoint: RenderedImageAnalysis.Viewpoint?
    let imageFraming: RenderedImageAnalysis.Framing?
    let imageDescription: String?
    let isDescribingImage: Bool
    let describeImage: () -> Void
    let flipImage: () -> Void
    let moveCameraInside: () -> Void
    let snapToHorizon: () -> Void
    let resetAnalysis: () -> Void
    let findBestView: (() -> Void)?
    // Multi-mode only: document and selection
    @Binding var document: SplatSceneDocument?
    @Binding var selectedCloud: SplatScene.CloudReference?
    var onDeleteCloud: (() -> Void)?
    var onScreenshot: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker - disable animations to prevent flicker during camera updates
            Picker("Tab", selection: $tab) {
                ForEach(InspectorTab.tabs(for: mode), id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()
            .transaction { $0.animation = nil }

            Divider()

            // Content based on tab
            Form {
                switch tab {
                case .cloud:
                    cloudContent

                case .scene:
                    if var doc = document {
                        SceneInspector(document: Binding(
                            get: { doc },
                            set: { doc = $0; document = $0 }
                        ))
                        .environment(viewModel)
                    }

                case .camera:
                    cameraContent

                case .render:
                    renderContent

                case .analysis:
                    AnalysisInspectorView(
                        classifications: classifications,
                        visionImageAnalysis: visionImageAnalysis,
                        highlightsSubjects: $highlightsSubjects,
                        imageOrientation: imageOrientation,
                        imageViewpoint: imageViewpoint,
                        imageFraming: imageFraming,
                        imageDescription: imageDescription,
                        isDescribingImage: isDescribingImage,
                        describeImage: describeImage,
                        flipCamera: flipImage,
                        moveCameraInside: moveCameraInside,
                        snapToHorizon: snapToHorizon,
                        findBestView: findBestView ?? { _ = () },
                        resetAnalysis: resetAnalysis
                    )
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transaction { $0.animation = nil }
        }
    }

    // MARK: - Cloud Content

    @ViewBuilder
    private var cloudContent: some View {
        if mode == .multi, selectedCloud == nil {
            ContentUnavailableView("No Selection", systemImage: "cube.transparent", description: Text("Select a cloud to view its details"))
        } else {
            CloudInspector(
                descriptor: cloudDescriptor,
                rotationX: cloudRotationXBinding,
                rotationY: cloudRotationYBinding,
                rotationZ: cloudRotationZBinding,
                rotationSectionTitle: mode == .single ? "Model Orientation" : "Rotation",
                centerModel: $viewModel.centerModel,
                showCenterModel: mode == .single,
                displayName: cloudDisplayNameBinding,
                enabled: cloudEnabledBinding,
                opacity: cloudOpacityBinding,
                showCloudProperties: mode == .multi,
                transform: cloudTransformBinding,
                showTranslation: mode == .multi,
                onDelete: mode == .multi ? onDeleteCloud : nil
            )
        }
    }

    private var cloudDescriptor: SplatCloudDescriptor? {
        if mode == .single {
            return viewModel.descriptor
        }
        if let cloud = selectedCloud {
            return viewModel.loadedClouds.first { $0.id == cloud.id }?.descriptor
        }
        return nil
    }

    // Cloud bindings - single mode uses viewModel, multi mode uses selectedCloud
    private var cloudRotationXBinding: Binding<Float> {
        if mode == .single {
            return $viewModel.modelRotationX
        }
        return Binding(
            get: { selectedCloud?.transform.rotation.x ?? 0 },
            set: { selectedCloud?.transform.rotation.x = $0 }
        )
    }

    private var cloudRotationYBinding: Binding<Float> {
        if mode == .single {
            return $viewModel.modelRotationY
        }
        return Binding(
            get: { selectedCloud?.transform.rotation.y ?? 0 },
            set: { selectedCloud?.transform.rotation.y = $0 }
        )
    }

    private var cloudRotationZBinding: Binding<Float> {
        if mode == .single {
            return $viewModel.modelRotationZ
        }
        return Binding(
            get: { selectedCloud?.transform.rotation.z ?? 0 },
            set: { selectedCloud?.transform.rotation.z = $0 }
        )
    }

    private var cloudDisplayNameBinding: Binding<String?> {
        Binding(
            get: { selectedCloud?.displayName },
            set: { selectedCloud?.displayName = $0 }
        )
    }

    private var cloudEnabledBinding: Binding<Bool> {
        if mode == .single {
            return .constant(true)
        }
        return Binding(
            get: { selectedCloud?.enabled ?? true },
            set: { selectedCloud?.enabled = $0 }
        )
    }

    private var cloudOpacityBinding: Binding<Float> {
        if mode == .single {
            return .constant(1)
        }
        return Binding(
            get: { selectedCloud?.opacity ?? 1 },
            set: { selectedCloud?.opacity = $0 }
        )
    }

    private var cloudTransformBinding: Binding<Transform> {
        Binding(
            get: { selectedCloud?.transform ?? .identity },
            set: { selectedCloud?.transform = $0 }
        )
    }

    // MARK: - Camera Content

    /// Get the bounds center for the selected cloud (multi mode) or the overall bounds (single mode)
    private var selectedCloudBoundsCenter: SIMD3<Float> {
        guard mode == .multi, let cloud = selectedCloud, let loadedCloud = viewModel.loadedClouds.first(where: { $0.id == cloud.id }), let bounds = loadedCloud.bounds
        else {
            return viewModel.boundsCenter
        }
        // Transform the bounds center by the cloud's transform
        return (cloud.transform.matrix * SIMD4<Float>(bounds.center, 1)).xyz
    }

    /// Check if we have valid bounds for teleporting
    private var hasTeleportTarget: Bool {
        if mode == .multi {
            // In multi mode, need a selected cloud with bounds
            guard let cloud = selectedCloud,
                let loadedCloud = viewModel.loadedClouds.first(where: { $0.id == cloud.id }),
                loadedCloud.bounds != nil
            else {
                return false
            }
            return true
        }
        return viewModel.boundsSize != .zero
    }

    @ViewBuilder
    private var cameraContent: some View {
        CameraInspector(
            cameraMode: $viewModel.cameraMode,
            zoomToFit: $viewModel.zoomToFit,
            verticalAngleOfView: $viewModel.verticalAngleOfView,
            nearClip: $viewModel.nearClip,
            farClip: $viewModel.farClip,
            cameraMatrix: $viewModel.cameraMatrix,
            viewSize: viewModel.viewSize,
            zoomToFitDisabled: viewModel.boundsSize == .zero,
            boundsCenter: selectedCloudBoundsCenter,
            teleportDisabled: !hasTeleportTarget
        )
        .cameraControlStyle(.compact)
    }

    // MARK: - Render Content

    private var backgroundColorBinding: Binding<Color> {
        guard mode == .multi else {
            return $viewModel.backgroundColor
        }
        return Binding(
            get: {
                guard let color = document?.scene.renderSettings.backgroundColor, color.count == 4 else {
                    return .black
                }
                return Color(red: Double(color[0]), green: Double(color[1]), blue: Double(color[2]), opacity: Double(color[3]))
            },
            set: { color in
                let resolved = color.resolve(in: EnvironmentValues())
                document?.scene.renderSettings.backgroundColor = [Float(resolved.red), Float(resolved.green), Float(resolved.blue), Float(resolved.opacity)]
            }
        )
    }

    private var useSphericalHarmonicsBinding: Binding<Bool> {
        guard mode == .multi else {
            return $viewModel.useSphericalHarmonics
        }
        return Binding(
            get: { document?.scene.renderSettings.useSphericalHarmonics ?? true },
            set: { document?.scene.renderSettings.useSphericalHarmonics = $0 }
        )
    }
    @ViewBuilder
    private var renderContent: some View {
        RenderInspector(
            backgroundColor: backgroundColorBinding,
            gridColor: $viewModel.gridColor,
            useSphericalHarmonics: useSphericalHarmonicsBinding,
            rendererSelectionDisabled: mode == .multi,
            supportsBoundsCulling: mode == .multi,
            sphericalHarmonicsDisabled: !viewModel.hasSphericalHarmonicsData,
            sphericalHarmonicsWarning: sphericalHarmonicsWarning,
            showBoundingBoxes: $viewModel.showBoundingBoxes,
            showReferenceGrid: $viewModel.showReferenceGrid,
            showAxisLines: $viewModel.showAxisLines,
            debugModeEnabled: $viewModel.debugModeEnabled,
            debugMode: $viewModel.debugMode,
            lastSortEvent: viewModel.lastSortEvent,
            onScreenshot: onScreenshot
        ) {
            cullingSection
        }
    }

    private var sphericalHarmonicsWarning: String? {
        if mode == .single {
            return nil
        }
        if !viewModel.hasSphericalHarmonicsData {
            return "Not all clouds have SH data"
        }
        return nil
    }

    @ViewBuilder
    private var cullingSection: some View {
        NormalizedCullingSection(
            enabled: $viewModel.cullBoundingBoxEnabled,
            minBounds: $viewModel.cullMinNormalized,
            maxBounds: $viewModel.cullMaxNormalized,
            disabled: viewModel.boundsSize == .zero
        )
    }
}

// MARK: - Convenience Initializers

extension InspectorView {
    /// Create inspector for single splat mode
    init(
        singleViewModel: SplatViewModel,
        tab: Binding<InspectorTab>,
        classifications: [ImageClassification],
        visionImageAnalysis: VisionImageAnalysis?,
        highlightsSubjects: Binding<Bool>,
        imageOrientation: RenderedImageAnalysis.Orientation?,
        imageViewpoint: RenderedImageAnalysis.Viewpoint?,
        imageFraming: RenderedImageAnalysis.Framing?,
        imageDescription: String?,
        isDescribingImage: Bool,
        describeImage: @escaping () -> Void,
        flipImage: @escaping () -> Void,
        moveCameraInside: @escaping () -> Void,
        snapToHorizon: @escaping () -> Void,
        resetAnalysis: @escaping () -> Void,
        findBestView: @escaping () -> Void,
        onScreenshot: (() -> Void)? = nil
    ) {
        self.mode = .single
        self.viewModel = singleViewModel
        self._tab = tab
        self.classifications = classifications
        self.visionImageAnalysis = visionImageAnalysis
        self._highlightsSubjects = highlightsSubjects
        self.imageOrientation = imageOrientation
        self.imageViewpoint = imageViewpoint
        self.imageFraming = imageFraming
        self.imageDescription = imageDescription
        self.isDescribingImage = isDescribingImage
        self.describeImage = describeImage
        self.flipImage = flipImage
        self.moveCameraInside = moveCameraInside
        self.snapToHorizon = snapToHorizon
        self.resetAnalysis = resetAnalysis
        self.findBestView = findBestView
        self._document = .constant(nil)
        self._selectedCloud = .constant(nil)
        self.onDeleteCloud = nil
        self.onScreenshot = onScreenshot
    }

    /// Create inspector for multi-cloud mode
    init(
        multiViewModel: SplatViewModel,
        document: Binding<SplatSceneDocument?>,
        selectedCloud: Binding<SplatScene.CloudReference?>,
        tab: Binding<InspectorTab>,
        onDeleteCloud: (() -> Void)? = nil,
        onScreenshot: (() -> Void)? = nil
    ) {
        self.mode = .multi
        self.viewModel = multiViewModel
        self._tab = tab
        self.classifications = []
        self.visionImageAnalysis = nil
        self._highlightsSubjects = .constant(false)
        self.imageOrientation = nil
        self.imageViewpoint = nil
        self.imageFraming = nil
        self.imageDescription = nil
        self.isDescribingImage = false
        self.describeImage = { _ = () }
        self.flipImage = { _ = () }
        self.moveCameraInside = { _ = () }
        self.snapToHorizon = { _ = () }
        self.resetAnalysis = { _ = () }
        self.findBestView = nil
        self._document = document
        self._selectedCloud = selectedCloud
        self.onDeleteCloud = onDeleteCloud
        self.onScreenshot = onScreenshot
    }
}
#endif
