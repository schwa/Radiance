#if os(iOS) || os(macOS)
import CoreImage
import FoundationModels
import GeometryLite3D
import Interaction3D
import MetalSprockets
import MetalSprocketsGaussianSplats
import MetalSprocketsGaussianSplatShaders
import MetalSprocketsSupport
import MetalSprocketsUI
import simd
import Splats
import SwiftUI
import UniformTypeIdentifiers
import Vision

// MARK: - DebugCloudIndexParams Helper

extension DebugCloudIndexParams {
    /// Create params with custom cloud colors
    /// - Parameters:
    ///   - cloudCount: Number of clouds
    ///   - colors: Array of colors for each cloud (up to 16). Remaining slots filled with white.
    static func withColors(cloudCount: UInt32, colors: [SIMD3<Float>]) -> DebugCloudIndexParams {
        // Swift bridges C arrays as tuples, so we need to create it manually
        var params = DebugCloudIndexParams()
        params.cloudCount = cloudCount

        // Fill colors into the tuple (up to 16)
        withUnsafeMutablePointer(to: &params.cloudColors) { ptr in
            let colorPtr = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: SIMD3<Float>.self)
            for i in 0..<16 {
                if i < colors.count {
                    colorPtr[i] = colors[i]
                } else {
                    colorPtr[i] = SIMD3<Float>(1, 1, 1) // Default to white
                }
            }
        }
        return params
    }
}

// MARK: - Document Content View

/// A unified view for displaying both single splat documents and multi-cloud scenes
struct SplatDocumentContentView: View {
    let mode: SplatContentMode

    // Single mode
    var singleDocument: SplatDocument?
    var fileURL: URL?

    // Multi mode
    @Binding var multiDocument: SplatSceneDocument?

    // MARK: - State

    @State private var viewModel: SplatViewModel

    @State private var selectedCloudID: UUID?
    @State private var inspectorTab: InspectorTab = .cloud

    // Inspector visibility (both modes)
    @SceneStorage("showInspector") private var showInspector = true

    // Multi mode: sidebar visibility
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly

    // Single mode specific
    @State private var showScreenshotSheet = false
    @State private var showExportDialog = false
    @State private var classifications: [ImageClassification] = []
    @State private var visionImageAnalysis: VisionImageAnalysis?
    @State private var classificationError: String?
    @State private var imageOrientation: RenderedImageAnalysis.Orientation?
    @State private var imageViewpoint: RenderedImageAnalysis.Viewpoint?
    @State private var imageFraming: RenderedImageAnalysis.Framing?
    @State private var imageDescription: String?
    @State private var isDescribingImage = false
    @State private var subjectMask: CGImage?
    @State private var highlightsSubjects = false
    @State private var classificationTask: Task<Void, Never>?
    @State private var bestViewTask: Task<Void, Never>?
    @State private var bestViewError: String?
    @State private var bestViewResults: [BestViewCandidate] = []
    @State private var bestViewAttempts: [BestViewAttempt] = []
    @State private var recommendedBestView: Int?
    @State private var selectedBestView: Int?
    @State private var bestViewMatrices: [simd_float4x4] = []
    @State private var bestViewAttemptedCount = 0
    @State private var bestViewRejectedCount = 0
    @State private var bestViewTotalCount = 0
    // Multi mode specific
    @State private var showAddCloudPicker = false
    @State private var dragOffsets: [UUID: SIMD3<Float>] = [:]

    @Environment(\.displayScale) private var displayScale

    // MARK: - Initialization

    private init(mode: SplatContentMode, singleDocument: SplatDocument?, fileURL: URL?, multiDocument: Binding<SplatSceneDocument?>) {
        self.mode = mode
        self.singleDocument = singleDocument
        self.fileURL = fileURL
        self._multiDocument = multiDocument
        self._viewModel = State(initialValue: SplatViewModel(mode: mode == .single ? .single : .multi))
    }

    // MARK: - Body

    var body: some View {
        Group {
            switch mode {
            case .single:
                singleModeLayout

            case .multi:
                multiModeLayout
            }
        }
        .toolbar { toolbarContent }
        .onAppear { setupInitialState() }
        .onChange(of: viewModel.loadingState) {
            classifyCurrentRenderingIfNeeded()
        }
        .onChange(of: viewModel.cameraMatrix) {
            subjectMask = nil
            classifyCurrentRenderingIfNeeded()
        }
        .onChange(of: viewModel.viewSize) {
            subjectMask = nil
            classifyCurrentRenderingIfNeeded()
        }
        .onChange(of: viewModel.sceneTransform) {
            subjectMask = nil
            classifyCurrentRenderingIfNeeded()
        }
        .onChange(of: viewModel.analysisModelTransform) {
            subjectMask = nil
            classifyCurrentRenderingIfNeeded()
        }
        .onChange(of: viewModel.analysisCameraTransform) {
            subjectMask = nil
            classifyCurrentRenderingIfNeeded()
        }
        .onChange(of: viewModel.verticalAngleOfView) {
            subjectMask = nil
            classifyCurrentRenderingIfNeeded()
        }
        .onChange(of: highlightsSubjects) {
            subjectMask = nil
            classifyCurrentRenderingIfNeeded()
        }
        .alert("Classification Failed", isPresented: Binding(
            get: { classificationError != nil },
            set: { if !$0 { classificationError = nil } }
        )) {
            Button("OK", role: .cancel) {
                classificationError = nil
            }
        } message: {
            Text(classificationError ?? "Unknown error")
        }
        .sheet(isPresented: Binding(
            get: { bestViewTask != nil || !bestViewResults.isEmpty },
            set: { if !$0 { cancelBestViewSearch() } }
        )) {
            BestViewSheet(
                candidates: bestViewResults,
                attempts: bestViewAttempts,
                isSearching: bestViewTask != nil,
                attemptedCount: bestViewAttemptedCount,
                rejectedCount: bestViewRejectedCount,
                totalCount: bestViewTotalCount,
                recommendedCandidate: recommendedBestView,
                selectedCandidate: $selectedBestView,
                onConfirm: confirmBestView,
                onCancel: cancelBestViewSearch
            )
        }
        .alert("Best View Failed", isPresented: Binding(
            get: { bestViewError != nil },
            set: { if !$0 { bestViewError = nil } }
        )) {
            Button("OK", role: .cancel) {
                bestViewError = nil
            }
        } message: {
            Text(bestViewError ?? "Unknown error")
        }
    }

    private func setupInitialState() {
        inspectorTab = mode == .multi ? .scene : .cloud
    }

    private var renderCameraMatrix: Binding<simd_float4x4> {
        Binding(
            get: { viewModel.renderCameraMatrix },
            set: { viewModel.cameraMatrix = viewModel.analysisCameraTransform.inverse * $0 }
        )
    }

    private func classifyCurrentRenderingIfNeeded() {
        guard mode == .single, viewModel.loadingState == .ready, classificationTask == nil else {
            return
        }

        let data = screenshotData
        guard !data.cloudInfos.isEmpty else {
            return
        }

        let cameraMatrix = viewModel.renderCameraMatrix
        let sceneTransform = data.sceneTransform
        let viewSize = viewModel.viewSize
        let aspectRatio = max(viewSize.height, 1) / max(viewSize.width, 1)
        let width = aspectRatio < 1 ? max(Int(512 / aspectRatio), 1) : 512
        let height = aspectRatio < 1 ? 512 : max(Int(512 * aspectRatio), 1)
        let verticalAngleOfView = viewModel.verticalAngleOfView
        let backgroundColor = viewModel.backgroundColor.resolve(in: .init())
        let shouldGenerateSubjectMask = highlightsSubjects

        classificationTask = Task {
            do {
                let newClassifications = try await Task.detached {
                    let image = try ScreenshotSheet.renderToImage(
                        width: width,
                        height: height,
                        cloudInfos: data.cloudInfos,
                        sceneTransform: sceneTransform,
                        cameraMatrix: cameraMatrix,
                        verticalAngleOfView: verticalAngleOfView,
                        backgroundColor: backgroundColor
                    )
                    async let observations = ClassifyImageRequest().perform(on: image)
                    async let horizon = DetectHorizonRequest().perform(on: image)
                    async let aesthetics = CalculateImageAestheticsScoresRequest().perform(on: image)
                    let (classificationObservations, horizonObservation, aestheticsObservation) = try await (observations, horizon, aesthetics)
                    let classifications = classificationObservations.prefix(5).map {
                        ImageClassification(label: $0.identifier, confidence: $0.confidence)
                    }
                    let visionAnalysis = VisionImageAnalysis(
                        horizonAngleDegrees: horizonObservation?.angle.converted(to: .degrees).value,
                        horizonConfidence: horizonObservation?.confidence,
                        aestheticsScore: aestheticsObservation.overallScore,
                        isUtility: aestheticsObservation.isUtility
                    )
                    let subjectMask: CGImage?
                    if shouldGenerateSubjectMask {
                        subjectMask = try await Self.generateSubjectMask(for: image)
                    } else {
                        subjectMask = nil
                    }
                    return (classifications, subjectMask, visionAnalysis)
                }.value
                try Task.checkCancellation()
                let renderingChanged = viewModel.renderCameraMatrix != cameraMatrix || viewModel.renderSceneTransform != sceneTransform || viewModel.viewSize != viewSize || viewModel.verticalAngleOfView != verticalAngleOfView || highlightsSubjects != shouldGenerateSubjectMask
                if !renderingChanged {
                    classifications = newClassifications.0
                    subjectMask = newClassifications.1
                    visionImageAnalysis = newClassifications.2
                }
            } catch {
                if !Task.isCancelled {
                    classificationError = error.localizedDescription
                }
            }

            classificationTask = nil
            if viewModel.renderCameraMatrix != cameraMatrix || viewModel.renderSceneTransform != sceneTransform || viewModel.viewSize != viewSize || viewModel.verticalAngleOfView != verticalAngleOfView || highlightsSubjects != shouldGenerateSubjectMask {
                classifyCurrentRenderingIfNeeded()
            }
        }
    }
    private func flipImage() {
        viewModel.analysisModelTransform = simd_float4x4(zRotation: .radians(.pi)) * viewModel.analysisModelTransform
        clearImageAnalysis()
    }

    private func snapToHorizon() {
        guard let analysis = visionImageAnalysis, let horizonAngleDegrees = analysis.horizonAngleDegrees, let confidence = analysis.horizonConfidence, confidence > 0.8 else {
            return
        }
        viewModel.zoomToFit = false
        let correction = simd_float4x4(zRotation: .degrees(-Float(horizonAngleDegrees)))
        viewModel.analysisModelTransform = correction * viewModel.analysisModelTransform
        clearImageAnalysis()
        visionImageAnalysis = nil
    }

    private func resetAnalysis() {
        viewModel.resetAnalysisTransforms()
        clearImageAnalysis()
        visionImageAnalysis = nil
    }

    private func moveCameraInside() {
        let center = (viewModel.renderSceneTransform * SIMD4<Float>(viewModel.boundsCenter, 1)).xyz
        let desiredCamera = simd_float4x4(translation: center)
        viewModel.analysisCameraTransform = desiredCamera * viewModel.cameraMatrix.inverse
        clearImageAnalysis()
    }

    private func findBestView() {
        guard #available(iOS 27, macOS 27, *) else {
            bestViewError = "Best View requires iOS or macOS 27."
            return
        }
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            bestViewError = "The Foundation Model is unavailable on this device."
            return
        }

        let data = screenshotData
        guard !data.cloudInfos.isEmpty else {
            return
        }
        let matrices = bestViewCandidateMatrices
        bestViewAttemptedCount = 0
        bestViewRejectedCount = 0
        bestViewTotalCount = matrices.count
        let verticalAngleOfView = viewModel.verticalAngleOfView
        let backgroundColor = viewModel.backgroundColor.resolve(in: .init())

        bestViewTask = Task {
            defer { bestViewTask = nil }
            do {
                var acceptedImages: [CGImage] = []
                var pendingMatrices = matrices.map { (matrix: $0, allowsCorrection: true) }
                var attemptID = 0
                while attemptID < pendingMatrices.count {
                    let pending = pendingMatrices[attemptID]
                    let matrix = pending.matrix
                    let currentAttemptID = attemptID
                    attemptID += 1
                    try Task.checkCancellation()
                    let image = try await Task.detached {
                        try ScreenshotSheet.renderToImage(
                            width: 512,
                            height: 512,
                            cloudInfos: data.cloudInfos,
                            sceneTransform: data.sceneTransform,
                            cameraMatrix: matrix,
                            verticalAngleOfView: verticalAngleOfView,
                            backgroundColor: backgroundColor
                        )
                    }.value
                    try Task.checkCancellation()
                    bestViewAttempts.append(BestViewAttempt(id: currentAttemptID, image: image, cameraMatrix: matrix, status: .pending))
                    if Self.lacksVisualContent(image, backgroundColor: backgroundColor) {
                        updateBestViewAttempt(id: currentAttemptID, status: .rejected(.empty))
                        bestViewAttemptedCount += 1
                        bestViewRejectedCount += 1
                        continue
                    }
                    let assessment = try await LanguageModelSession(model: model).respond(generating: BestViewAssessment.self) {
                        """
                        Analyze this Gaussian-splat rendering strictly.
                        Set content to recognizable only when the image clearly depicts a coherent room, place, or subject. Set it to unrecognizable for blank images, giant blobs, abstract colors, close-up splats, or images where no real content can be identified.
                        Classify sceneKind as indoor for views within buildings or enclosed spaces, outdoor for landscapes, streets, gardens, or open environments, object for an isolated subject viewed from outside, and uncertain only when evidence is insufficient. Geometry surrounding the camera does not by itself prove indoor or outdoor.
                        Set splatArtifacts to high only when many unmistakable floating, oversized, disconnected, or blurry splats dominate or substantially block recognizable content. Ordinary Gaussian-splat softness, small edge artifacts, a few stray splats, holes, or reconstruction noise are moderate and must not be marked high. Use low when artifacts are negligible.
                        Classify orientation as image-plane rotation, not camera direction. Use architectural cues: floors belong below ceilings, walls and cabinets should be vertical, and counters should be horizontal. A recognizable room rotated 90 degrees is sideways even when its contents remain clear. Use uncertain only when there are no reliable gravity cues.
                        """
                        Attachment(image)
                    }.content
                    try Task.checkCancellation()
                    bestViewAttemptedCount += 1
                    let isScene = [BestViewAssessment.SceneKind.indoor, .outdoor].contains(assessment.sceneKind)
                    let isGoodScene = assessment.content == .recognizable && isScene && assessment.splatArtifacts != .high
                    let orientation: RenderedImageAnalysis.Orientation
                    if isGoodScene {
                        orientation = try await LanguageModelSession(model: model).respond(generating: BestViewOrientationAssessment.self) {
                            """
                            Determine only the image-plane orientation by first inferring the direction of gravity from multiple independent cues.
                            For indoor scenes, ceiling fixtures belong in the upper part of an upright image; furniture rests toward the lower part; wall cabinets sit above counters; base cabinets and appliances stand on the floor.
                            For outdoor scenes, sky is generally above ground, vegetation grows upward, and people, vehicles, buildings, and street furniture rest on the ground.
                            A large visible ceiling, wide-angle distortion, tilted camera, sloped surface, or strong perspective does not make an image upside down. Do not rely on any single light, line, reflection, or isolated object.
                            Return upsideDown only when the overall scene is inverted, such as overhead fixtures predominantly appearing below the room while furniture or floor-supported objects appear above them.
                            Return upright when ceiling features are generally above counters, furniture, and floor-supported objects. Use sidewaysLeft or sidewaysRight only when the inferred gravity direction points sideways.
                            """
                            Attachment(image)
                        }.content.orientation
                    } else {
                        orientation = assessment.orientation
                    }
                    try Task.checkCancellation()
                    if isGoodScene, orientation == .upright {
                        updateBestViewAttempt(id: currentAttemptID, status: .accepted)
                        let id = bestViewResults.count
                        bestViewMatrices.append(matrix)
                        bestViewResults.append(BestViewCandidate(
                            id: id,
                            image: image,
                            cameraMatrix: matrix,
                            orientation: orientation,
                            sceneKind: assessment.sceneKind,
                            splatArtifacts: assessment.splatArtifacts
                        ))
                        acceptedImages.append(image)
                    } else {
                        updateBestViewAttempt(id: currentAttemptID, status: .rejected(rejectionReason(for: assessment, orientation: orientation)))
                        bestViewRejectedCount += 1
                        if isGoodScene, pending.allowsCorrection {
                            let corrections = correctedCameraMatrices(matrix, for: orientation).map {
                                (matrix: $0, allowsCorrection: false)
                            }
                            pendingMatrices.insert(contentsOf: corrections, at: attemptID)
                            bestViewTotalCount = pendingMatrices.count
                        }
                    }
                    if acceptedImages.count == 6 {
                        break
                    }
                }

                guard acceptedImages.count == 6 else {
                    if bestViewResults.isEmpty {
                        throw BestViewError.noUsableViews
                    }
                    recommendedBestView = bestViewResults.indices.first
                    selectedBestView = recommendedBestView
                    return
                }
                let response = try await LanguageModelSession(model: model).respond(generating: BestViewSelection.self) {
                    """
                    Choose the best of these six indoor or outdoor Gaussian-splat scene views.
                    Prefer an upright, coherent scene with useful framing and the fewest visible floating-splat artifacts.
                    Return its zero-based candidate number in attachment order.
                    """
                    Attachment(acceptedImages[0])
                    Attachment(acceptedImages[1])
                    Attachment(acceptedImages[2])
                    Attachment(acceptedImages[3])
                    Attachment(acceptedImages[4])
                    Attachment(acceptedImages[5])
                }
                guard bestViewResults.indices.contains(response.content.candidate) else {
                    throw BestViewError.invalidSelection
                }
                recommendedBestView = response.content.candidate
                selectedBestView = response.content.candidate
            } catch is CancellationError {
                return
            } catch {
                bestViewError = error.localizedDescription
            }
        }
    }

    private func updateBestViewAttempt(id: Int, status: BestViewAttemptStatus) {
        guard let index = bestViewAttempts.firstIndex(where: { $0.id == id }) else {
            return
        }
        bestViewAttempts[index].status = status
    }

    private func rejectionReason(for assessment: BestViewAssessment, orientation: RenderedImageAnalysis.Orientation) -> BestViewRejectionReason {
        if assessment.content != .recognizable {
            return .noContent
        }
        if assessment.sceneKind == .object {
            return .object
        }
        if assessment.sceneKind == .uncertain {
            return .noContent
        }
        if assessment.splatArtifacts == .high {
            return .tooSplatty
        }
        switch orientation {
        case .sidewaysLeft, .sidewaysRight:
            return .sideways

        case .upsideDown:
            return .upsideDown

        case .uncertain:
            return .uncertainOrientation

        case .upright:
            return .noContent
        }
    }

    private func correctedCameraMatrices(_ matrix: simd_float4x4, for orientation: RenderedImageAnalysis.Orientation) -> [simd_float4x4] {
        let angles: [Float]
        switch orientation {
        case .upsideDown:
            angles = [.pi]

        case .sidewaysLeft:
            angles = [-.pi / 2, .pi / 2]

        case .sidewaysRight:
            angles = [.pi / 2, -.pi / 2]

        case .upright, .uncertain:
            angles = []
        }
        return angles.map { matrix * simd_float4x4(zRotation: .radians($0)) }
    }

    nonisolated private static func lacksVisualContent(_ image: CGImage, backgroundColor: Color.Resolved) -> Bool {
        let sampleSize = 32
        let scale = CGAffineTransform(scaleX: CGFloat(sampleSize) / CGFloat(image.width), y: CGFloat(sampleSize) / CGFloat(image.height))
        let image = CIImage(cgImage: image).transformed(by: scale)
        var pixels = [UInt8](repeating: 0, count: sampleSize * sampleSize * 4)
        CIContext().render(
            image,
            toBitmap: &pixels,
            rowBytes: sampleSize * 4,
            bounds: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        let background = [backgroundColor.red, backgroundColor.green, backgroundColor.blue].map { UInt8(clamping: Int($0 * 255)) }
        var matchingBackgroundPixels = 0
        var luminanceHistogram = [Int](repeating: 0, count: 32)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Int(pixels[index])
            let green = Int(pixels[index + 1])
            let blue = Int(pixels[index + 2])
            if abs(red - Int(background[0])) < 8, abs(green - Int(background[1])) < 8, abs(blue - Int(background[2])) < 8 {
                matchingBackgroundPixels += 1
            }
            let luminance = (red * 54 + green * 183 + blue * 19) / 256
            luminanceHistogram[min(luminance / 8, 31)] += 1
        }
        let pixelCount = sampleSize * sampleSize
        let entropy = luminanceHistogram.reduce(0.0) { result, count in
            guard count > 0 else {
                return result
            }
            let probability = Double(count) / Double(pixelCount)
            return result - probability * log2(probability)
        }
        let occupiedBins = luminanceHistogram.count { $0 > pixelCount / 100 }
        return matchingBackgroundPixels * 100 >= pixelCount * 98 || entropy < 0.75 || occupiedBins < 2
    }

    private var bestViewCandidateMatrices: [simd_float4x4] {
        let center = viewModel.boundsCenter
        let offset = viewModel.boundsSize * SIMD3<Float>(0.25, 0.1, 0.25)
        let localPositions = [
            center,
            center + [-offset.x, 0, -offset.z],
            center + [offset.x, 0, -offset.z],
            center + [-offset.x, 0, offset.z],
            center + [offset.x, 0, offset.z],
            center + [-offset.x, offset.y, 0],
            center + [offset.x, offset.y, 0],
            center + [0, -offset.y, -offset.z],
            center + [0, -offset.y, offset.z]
        ]
        let localDirections: [SIMD3<Float>] = [
            [0, 0, -1],
            [1, 0, 0],
            [0, 0, 1],
            [-1, 0, 0]
        ]
        let worldUp = (viewModel.renderSceneTransform * SIMD4<Float>(0, 1, 0, 0)).xyz
        let transformedPositions = localPositions.map { (viewModel.renderSceneTransform * SIMD4<Float>($0, 1)).xyz }
        let worldPositions = [SIMD3<Float>.zero, viewModel.boundsCenter] + transformedPositions
        return worldPositions.flatMap { position in
            localDirections.map { localDirection in
                let direction = (viewModel.renderSceneTransform * SIMD4<Float>(localDirection, 0)).xyz
                return LookAt(position: position, target: position + direction, up: worldUp).cameraMatrix
            }
        }
    }

    private func confirmBestView() {
        guard let selectedBestView, bestViewMatrices.indices.contains(selectedBestView) else {
            return
        }
        viewModel.zoomToFit = false
        viewModel.cameraMode = .object
        let desiredCamera = bestViewMatrices[selectedBestView]
        viewModel.analysisCameraTransform = desiredCamera * viewModel.cameraMatrix.inverse
        clearImageAnalysis()
        clearBestViewSearch()
    }

    private func cancelBestViewSearch() {
        bestViewTask?.cancel()
        clearBestViewSearch()
    }

    private func clearBestViewSearch() {
        bestViewTask = nil
        bestViewResults = []
        bestViewAttempts = []
        bestViewMatrices = []
        recommendedBestView = nil
        selectedBestView = nil
        bestViewAttemptedCount = 0
        bestViewRejectedCount = 0
        bestViewTotalCount = 0
    }

    private enum BestViewError: LocalizedError {
        case invalidSelection
        case noUsableViews

        var errorDescription: String? {
            switch self {
            case .invalidSelection:
                "The model did not select a valid view."

            case .noUsableViews:
                "No recognizable interior views were found."
            }
        }
    }

    private func clearImageAnalysis() {
        imageOrientation = nil
        imageViewpoint = nil
        imageFraming = nil
        imageDescription = nil
    }

    private func describeCurrentRendering() {
        guard #available(iOS 27, macOS 27, *) else {
            classificationError = "Image descriptions require iOS or macOS 27."
            return
        }
        guard mode == .single, viewModel.loadingState == .ready else {
            return
        }

        let data = screenshotData
        guard !data.cloudInfos.isEmpty else {
            return
        }

        let viewSize = viewModel.viewSize
        let aspectRatio = max(viewSize.height, 1) / max(viewSize.width, 1)
        let width = aspectRatio < 1 ? max(Int(512 / aspectRatio), 1) : 512
        let height = aspectRatio < 1 ? 512 : max(Int(512 * aspectRatio), 1)
        let cameraMatrix = viewModel.renderCameraMatrix
        let verticalAngleOfView = viewModel.verticalAngleOfView
        let backgroundColor = viewModel.backgroundColor.resolve(in: .init())
        isDescribingImage = true

        Task {
            defer { isDescribingImage = false }
            do {
                let image = try await Task.detached {
                    try ScreenshotSheet.renderToImage(
                        width: width,
                        height: height,
                        cloudInfos: data.cloudInfos,
                        sceneTransform: data.sceneTransform,
                        cameraMatrix: cameraMatrix,
                        verticalAngleOfView: verticalAngleOfView,
                        backgroundColor: backgroundColor
                    )
                }.value
                let model = SystemLanguageModel.default
                guard model.isAvailable else {
                    throw ImageDescriptionError.modelUnavailable
                }
                let response = try await LanguageModelSession(model: model).respond(
                    generating: RenderedImageAnalysis.self
                ) {
                    """
                    Analyze this rendered Gaussian-splat image. Set orientation to its visible orientation.
                    Classify viewpoint as insideScene when the reconstruction surrounds the camera like a room,
                    landscape, or navigable environment. Classify it as outsideLookingAtSubject when viewing the
                    reconstruction externally, including when it appears as disconnected, oversized, blurry, or
                    overlapping splats against empty space. Rendering artifacts do not make the viewpoint uncertain.
                    Use uncertain only when there is not enough visible evidence to distinguish the two.
                    Set framing to the most important framing assessment for the main subject.
                    In the description, briefly state:
                    - whether the main subject is an object, person, place, room, landscape, or something else
                    - what the image depicts and any obvious rendering problems
                    Do not invent details that are not visible.
                    """
                    Attachment(image)
                }
                imageOrientation = response.content.orientation
                imageViewpoint = response.content.viewpoint
                imageFraming = response.content.framing
                imageDescription = response.content.description
            } catch {
                classificationError = error.localizedDescription
            }
        }
    }

    private enum ImageDescriptionError: LocalizedError {
        case modelUnavailable

        var errorDescription: String? {
            "The Foundation Model is unavailable on this Mac."
        }
    }

    nonisolated private static func generateSubjectMask(for image: CGImage) async throws -> CGImage? {
        let requestHandler = ImageRequestHandler(image)
        guard let observation = try await requestHandler.perform(GenerateForegroundInstanceMaskRequest()), !observation.allInstances.isEmpty else {
            return nil
        }

        let pixelBuffer = try observation.generateScaledMask(for: observation.allInstances, scaledToImageFrom: requestHandler)
        let mask = CIImage(cvPixelBuffer: pixelBuffer).applyingFilter("CIMaskToAlpha")
        return CIContext().createCGImage(mask, from: mask.extent)
    }

    // MARK: - Prepared Data for Screenshot

    /// Returns the cloud infos (descriptors + transforms) and scene transform for screenshot rendering
    private var screenshotData: (cloudInfos: [(descriptor: SplatCloudDescriptor, modelTransform: simd_float4x4)], sceneTransform: simd_float4x4) {
        switch mode {
        case .single:
            let infos = viewModel.loadedClouds.map { loadedCloud in
                (descriptor: loadedCloud.descriptor, modelTransform: simd_float4x4.identity)
            }
            return (infos, viewModel.renderSceneTransform)

        case .multi:
            guard let doc = multiDocument else {
                return ([], .identity)
            }
            let enabledCloudIDs = Set(doc.scene.clouds.filter(\.enabled).map(\.id))
            let infos: [(descriptor: SplatCloudDescriptor, modelTransform: simd_float4x4)] = viewModel.loadedClouds
                .filter { enabledCloudIDs.contains($0.id) }
                .compactMap { loadedCloud in
                    guard let docCloud = doc.scene.clouds.first(where: { $0.id == loadedCloud.id }) else {
                        return nil
                    }
                    var transform = docCloud.transform
                    if let dragOffset = dragOffsets[loadedCloud.id] {
                        transform.translation += dragOffset
                    }
                    return (descriptor: loadedCloud.descriptor, modelTransform: transform.matrix)
                }
            return (infos, doc.scene.sceneTransform.matrix)
        }
    }

    // MARK: - Single Mode Layout

    @ViewBuilder
    private var singleModeLayout: some View {
        mainContent
            .inspector(isPresented: $showInspector) {
                LazyView {
                    inspectorContent
                }
                #if !os(visionOS)
                .inspectorColumnWidth(min: 200, ideal: 300, max: 400)
                #endif
            }
            .focusedSceneValue(\.inspectorVisibility, $showInspector)
            .sheet(isPresented: $showScreenshotSheet) {
                let data = screenshotData
                ScreenshotSheet(
                    cloudInfos: data.cloudInfos,
                    sceneTransform: data.sceneTransform,
                    defaultWidth: Int(viewModel.viewSize.width * displayScale),
                    defaultHeight: Int(viewModel.viewSize.height * displayScale)
                )
                .environment(viewModel)
            }
            .fileExporter(
                isPresented: $showExportDialog,
                document: viewModel.convertedURL.map { PLYFileDocument(url: $0) },
                contentType: .ply,
                defaultFilename: viewModel.convertedURL?.deletingPathExtension().lastPathComponent
            ) { _ in
                // Export completion handled by system
            }
            .task(id: fileURL) {
                classificationTask?.cancel()
                classificationTask = nil
                classifications = []
                subjectMask = nil
                classificationError = nil
                await viewModel.load(url: fileURL, contentType: singleDocument?.contentType)
            }
            .environment(viewModel)
    }

    // MARK: - Multi Mode Layout

    @ViewBuilder
    private var multiModeLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            LazyView {
                cloudListSidebar
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 300)
        } detail: {
            mainContent
                .inspector(isPresented: $showInspector) {
                    LazyView {
                        inspectorContent
                    }
                    #if !os(visionOS)
                    .inspectorColumnWidth(min: 200, ideal: 300, max: 400)
                    #endif
                }
        }
        .focusedSceneValue(\.inspectorVisibility, $showInspector)
        .environment(viewModel)
        .sheet(isPresented: $showScreenshotSheet) {
            let data = screenshotData
            ScreenshotSheet(
                cloudInfos: data.cloudInfos,
                sceneTransform: data.sceneTransform,
                defaultWidth: Int(viewModel.viewSize.width * displayScale),
                defaultHeight: Int(viewModel.viewSize.height * displayScale)
            )
            .environment(viewModel)
        }
        .fileImporter(
            isPresented: $showAddCloudPicker,
            allowedContentTypes: [.ply, .spz, .antimatter15Splat, .sog],
            allowsMultipleSelection: true,
            onCompletion: handleAddClouds
        )
        .onChange(of: multiDocument?.scene.clouds, initial: true) {
            guard let doc = multiDocument else {
                return
            }
            Task {
                viewModel.loadClouds(from: doc.scene)
                viewModel.updateCombinedBounds(for: doc.scene)
            }
            // Ensure there's always a selection if clouds exist
            ensureSelection()
        }
        .onChange(of: multiDocument?.scene.sceneTransform) {
            guard let doc = multiDocument else {
                return
            }
            viewModel.updateCombinedBounds(for: doc.scene)
        }
        .onChange(of: viewModel.loadingState) {
            guard let doc = multiDocument, viewModel.loadingState == .ready else {
                return
            }
            viewModel.updateCombinedBounds(for: doc.scene)
        }
        .onChange(of: viewModel.boundsUpdateCount) {
            guard let doc = multiDocument else {
                return
            }
            viewModel.updateCombinedBounds(for: doc.scene)
        }
        // Sync camera state back to document
        .onChange(of: viewModel.cameraMatrix) {
            guard mode == .multi else {
                return
            }
            multiDocument?.scene.camera = SplatScene.CameraState(
                matrix: viewModel.cameraMatrix,
                verticalAngleOfView: viewModel.verticalAngleOfView,
                mode: viewModel.cameraMode.rawValue.lowercased()
            )
        }
        .onChange(of: viewModel.verticalAngleOfView) {
            guard mode == .multi else {
                return
            }
            multiDocument?.scene.camera = SplatScene.CameraState(
                matrix: viewModel.cameraMatrix,
                verticalAngleOfView: viewModel.verticalAngleOfView,
                mode: viewModel.cameraMode.rawValue.lowercased()
            )
        }
        .onChange(of: viewModel.cameraMode) {
            guard mode == .multi else {
                return
            }
            multiDocument?.scene.camera = SplatScene.CameraState(
                matrix: viewModel.cameraMatrix,
                verticalAngleOfView: viewModel.verticalAngleOfView,
                mode: viewModel.cameraMode.rawValue.lowercased()
            )
        }
    }

    // MARK: - Cloud List Sidebar (Multi Mode)

    @ViewBuilder
    private var cloudListSidebar: some View {
        List(selection: $selectedCloudID) {
            if let clouds = Binding($multiDocument)?.scene.clouds {
                ForEach(clouds) { $cloud in
                    CloudListRow(cloud: $cloud) {
                        multiDocument?.scene.clouds.removeAll { $0.id == cloud.id }
                    }
                    .tag(cloud.id)
                    .onTapGesture(count: 2) {
                        // Double-click to teleport to cloud center
                        if let loadedCloud = viewModel.loadedClouds.first(where: { $0.id == cloud.id }),
                            let bounds = loadedCloud.bounds {
                            let localCenter = bounds.center
                            let worldCenter = (cloud.transform.matrix * SIMD4<Float>(localCenter, 1)).xyz
                            viewModel.cameraMatrix = simd_float4x4(translation: worldCenter)
                        }
                    }
                    .contextMenu {
                        Button("Exclusive") {
                            // Disable all other clouds, enable this one
                            for i in multiDocument!.scene.clouds.indices {
                                multiDocument!.scene.clouds[i].enabled = (multiDocument!.scene.clouds[i].id == cloud.id)
                            }
                        }
                        Button("Enable All") {
                            for i in multiDocument!.scene.clouds.indices {
                                multiDocument!.scene.clouds[i].enabled = true
                            }
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            multiDocument?.scene.clouds.removeAll { $0.id == cloud.id }
                        }
                    }
                }
                .onDelete { indexSet in
                    multiDocument?.scene.clouds.remove(atOffsets: indexSet)
                }
                .onMove { source, destination in
                    multiDocument?.scene.clouds.move(fromOffsets: source, toOffset: destination)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Clouds")
        .safeAreaInset(edge: .bottom) {
            Button {
                showAddCloudPicker = true
            } label: {
                Label("Add Cloud", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding()
        }
        .overlay {
            if multiDocument?.scene.clouds.isEmpty ?? true {
                ContentUnavailableView {
                    Label("No Clouds", systemImage: "cube.transparent")
                } description: {
                    Text("Add splat clouds to your scene")
                }
            }
        }
    }

    // MARK: - Main Content (Shared)

    @ViewBuilder
    private var mainContent: some View {
        switch mode {
        case .single:
            singleModeMainContent

        case .multi:
            multiModeMainContent
        }
    }

    @ViewBuilder
    private var singleModeMainContent: some View {
        switch viewModel.loadingState {
        case .idle, .loading:
            ContentUnavailableView("Loading…", systemImage: "circle.dotted")

        case .converting(let status):
            conversionContent(status: status)

        case .error(let message):
            errorContent(message: message)

        case .ready:
            if let splatCloud = viewModel.splatCloud {
                singleRenderView(cloud: splatCloud)
            } else {
                ContentUnavailableView("No file to render", systemImage: "questionmark")
            }
        }
    }

    @ViewBuilder
    private var multiModeMainContent: some View {
        switch viewModel.loadingState {
        case .idle:
            if multiDocument?.scene.clouds.isEmpty ?? true {
                ContentUnavailableView {
                    Label("Empty Scene", systemImage: "cube.transparent")
                } description: {
                    Text("Add splat clouds to start")
                }
            } else {
                multiRenderView
            }

        case .loading:
            ProgressView("Loading clouds...")

        case .ready:
            multiRenderView

        case .converting:
            ProgressView("Converting...")

        case .error(let message):
            errorContent(message: message)
        }
    }

    // MARK: - Render Views (Shared)

    @ViewBuilder
    private func singleRenderView(cloud: GPUSplatCloud<SparkSplat>) -> some View {
        SplatRenderView(
            mode: .single,
            clouds: [cloud],
            sceneTransform: viewModel.renderSceneTransform,
            useSphericalHarmonics: viewModel.effectiveUseSphericalHarmonics,
            backgroundColor: viewModel.backgroundColorArray,
            cameraMatrix: renderCameraMatrix,
            verticalAngleOfView: $viewModel.verticalAngleOfView,
            cullBoundingBox: viewModel.cullBoundingBox,
            showBoundingBoxes: viewModel.showBoundingBoxes,
            boundingBoxInfos: singleModeBoundingBoxInfos,
            debugParams: viewModel.debugModeEnabled ? computeDebugParams(
                mode: viewModel.debugMode,
                boundsCenter: viewModel.boundsCenter,
                boundsSize: viewModel.boundsSize
            ) : nil,
            sortManager: nil,
            cameraMode: viewModel.cameraMode
        )
        .overlay {
            if highlightsSubjects, let subjectMask {
                Image(decorative: subjectMask, scale: 1)
                    .resizable()
                    .colorMultiply(.accentColor)
                    .opacity(0.45)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }

    /// Compute debug shader parameters based on mode and bounds
    private func computeDebugParams(mode: SplatDebugMode, boundsCenter: SIMD3<Float>, boundsSize: SIMD3<Float>, cloudCount: UInt32 = 1, cloudColors: [SIMD3<Float>] = []) -> DebugParams {
        let maxExtent = max(boundsSize.x, max(boundsSize.y, boundsSize.z))
        switch mode {
        case .distanceFromCenter:
            return .distance(DebugDistanceParams(center: boundsCenter, maxDistance: maxExtent / 2))

        case .splatSize:
            return .size(DebugSizeParams(minSize: 0, maxSize: maxExtent / 50))

        case .depth:
            return .depth(DebugDepthParams(minDepth: 0, maxDepth: maxExtent * 2))

        case .opacity:
            return .opacity

        case .normal:
            return .normal

        case .aspectRatio:
            return .aspectRatio(DebugAspectRatioParams(minRatio: 1.0, maxRatio: 10.0))

        case .cloudIndex:
            return .cloudIndex(DebugCloudIndexParams.withColors(cloudCount: cloudCount, colors: cloudColors))
        }
    }

    private var singleModeBoundingBoxInfos: [BoundingBoxInfo] {
        guard viewModel.showBoundingBoxes, viewModel.boundsSize != .zero else {
            return []
        }
        let bounds = BoundingBox(
            min: viewModel.boundsCenter - viewModel.boundsSize / 2,
            max: viewModel.boundsCenter + viewModel.boundsSize / 2
        )
        return [
            BoundingBoxInfo(
                id: UUID(),
                bounds: bounds,
                modelMatrix: viewModel.renderSceneTransform,
                color: .white
            )
        ]
    }

    @ViewBuilder
    private var multiRenderView: some View {
        if let doc = multiDocument, let sortManager = viewModel.sortManager {
            let enabledCloudIDs = Set(doc.scene.clouds.filter(\.enabled).map(\.id))

            // Build enabled clouds and collect their debug colors in the same order
            let preparedData: [(cloud: GPUSplatCloud<SparkSplat>, color: SIMD3<Float>)] = viewModel.loadedClouds
                .filter { enabledCloudIDs.contains($0.id) }
                .compactMap { loadedCloud in
                    guard let cloud = loadedCloud.cloud, let docCloud = doc.scene.clouds.first(where: { $0.id == loadedCloud.id }) else {
                        return nil
                    }
                    var transform = docCloud.transform
                    if let dragOffset = dragOffsets[loadedCloud.id] {
                        transform.translation += dragOffset
                    }
                    cloud.modelTransform = transform.matrix
                    cloud.opacity = docCloud.opacity
                    return (cloud: cloud, color: docCloud.debugColor)
                }

            let enabledClouds = preparedData.map(\.cloud)
            let enabledCloudColors = preparedData.map(\.color)

            let useSH = doc.scene.renderSettings.useSphericalHarmonics && viewModel.hasSphericalHarmonicsData

            SplatRenderView(
                mode: .multi,
                clouds: enabledClouds,
                sceneTransform: doc.scene.sceneTransform.matrix,
                useSphericalHarmonics: useSH,
                backgroundColor: doc.scene.renderSettings.backgroundColor,
                cameraMatrix: $viewModel.cameraMatrix,
                verticalAngleOfView: $viewModel.verticalAngleOfView,
                cullBoundingBox: viewModel.cullBoundingBox,
                showBoundingBoxes: viewModel.showBoundingBoxes,
                boundingBoxInfos: buildBoundingBoxInfos(),
                debugParams: viewModel.debugModeEnabled ? computeDebugParams(
                    mode: viewModel.debugMode,
                    boundsCenter: viewModel.boundsCenter,
                    boundsSize: viewModel.boundsSize,
                    cloudCount: UInt32(enabledClouds.count),
                    cloudColors: enabledCloudColors
                ) : nil,
                sortManager: sortManager,
                cameraMode: viewModel.cameraMode,
                onDragChange: handleAxisDrag,
                onDragEnd: commitDrag
            )
        } else if multiDocument != nil {
            ProgressView("Initializing...")
        }
    }

    // MARK: - Inspector (Shared)

    @ViewBuilder
    private var inspectorContent: some View {
        switch mode {
        case .single:
            InspectorView(
                singleViewModel: viewModel,
                tab: $inspectorTab,
                classifications: classifications,
                visionImageAnalysis: visionImageAnalysis,
                highlightsSubjects: $highlightsSubjects,
                imageOrientation: imageOrientation,
                imageViewpoint: imageViewpoint,
                imageFraming: imageFraming,
                imageDescription: imageDescription,
                isDescribingImage: isDescribingImage,
                describeImage: describeCurrentRendering,
                flipImage: flipImage,
                moveCameraInside: moveCameraInside,
                snapToHorizon: snapToHorizon,
                resetAnalysis: resetAnalysis,
                findBestView: findBestView
            ) {
                showScreenshotSheet = true
            }

        case .multi:
            let selectedCloud: Binding<SplatScene.CloudReference?> = Binding(
                get: {
                    guard let selectedID = selectedCloudID, let index = multiDocument?.scene.clouds.firstIndex(where: { $0.id == selectedID }) else {
                        return nil
                    }
                    return multiDocument?.scene.clouds[index]
                },
                set: { newValue in
                    guard let newValue, let selectedID = selectedCloudID, let index = multiDocument?.scene.clouds.firstIndex(where: { $0.id == selectedID }) else {
                        return
                    }
                    multiDocument?.scene.clouds[index] = newValue
                }
            )

            InspectorView(
                multiViewModel: viewModel,
                document: $multiDocument,
                selectedCloud: selectedCloud,
                tab: $inspectorTab,
                onDeleteCloud: {
                    if let id = selectedCloudID {
                        multiDocument?.scene.clouds.removeAll { $0.id == id }
                        selectedCloudID = nil
                    }
                },
                onScreenshot: { showScreenshotSheet = true }
            )
        }
    }

    // MARK: - Toolbar (Shared)

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Export PLY (single mode, image conversion only - specific workflow)
        if mode == .single, viewModel.isImageConversion, viewModel.convertedURL != nil {
            ToolbarItem(placement: .primaryAction) {
                Button("Export PLY", systemImage: "square.and.arrow.down") {
                    showExportDialog = true
                }
            }
        }

        // Inspector toggle (both modes)
        ToolbarItem(placement: .primaryAction) {
            Button(showInspector ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.right") {
                withAnimation {
                    showInspector.toggle()
                }
            }
        }
    }

    // MARK: - Helper Content Views

    @ViewBuilder
    private func conversionContent(status: String) -> some View {
        if let sourceImage = viewModel.sourceImage {
            ImageConversionView(sourceImage: sourceImage, statusMessage: status)
        } else {
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(2)
                Text(status)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func errorContent(message: String) -> some View {
        ContentUnavailableView {
            Label("Error", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        }
    }

    // MARK: - Multi Mode Helpers

    private func buildBoundingBoxInfos() -> [BoundingBoxInfo] {
        guard let doc = multiDocument else {
            return []
        }
        return viewModel.loadedClouds
            .filter { loadedCloud in
                doc.scene.clouds.first { $0.id == loadedCloud.id }?.enabled ?? false
            }
            .compactMap { loadedCloud in
                guard let bounds = loadedCloud.bounds else {
                    return nil
                }
                guard var transform = doc.scene.clouds.first(where: { $0.id == loadedCloud.id })?.transform else {
                    return nil
                }
                if let dragOffset = dragOffsets[loadedCloud.id] {
                    transform.translation += dragOffset
                }
                let modelMatrix = doc.scene.sceneTransform.matrix * transform.matrix
                return BoundingBoxInfo(id: loadedCloud.id, bounds: bounds, modelMatrix: modelMatrix, color: .white)
            }
    }

    private func handleAxisDrag(cloudID: UUID, axis: Int, screenDelta: CGSize, viewMatrix: simd_float4x4, projectionMatrix: simd_float4x4) {
        guard let doc = multiDocument, let cloudIndex = doc.scene.clouds.firstIndex(where: { $0.id == cloudID }), let loadedCloud = viewModel.loadedClouds.first(where: { $0.id == cloudID }) else {
            return
        }
        let bounds = loadedCloud.bounds ?? BoundingBox(min: .zero, max: .one)
        let modelMatrix = doc.scene.sceneTransform.matrix * doc.scene.clouds[cloudIndex].transform.matrix
        let worldCenter = modelMatrix * SIMD4<Float>(bounds.center, 1)

        let axisVectors: [SIMD3<Float>] = [SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)]
        let axisWorld = (modelMatrix * SIMD4<Float>(axisVectors[axis], 0)).xyz
        let axisNorm = normalize(axisWorld)

        let mvp = projectionMatrix * viewMatrix
        let viewportSize = viewModel.viewSize

        func toScreen(_ point: SIMD4<Float>) -> CGPoint? {
            let clip = mvp * point
            guard clip.w > 0 else {
                return nil
            }
            let ndc = SIMD3<Float>(clip.x, clip.y, clip.z) / clip.w
            return CGPoint(
                x: CGFloat((ndc.x + 1) * 0.5 * Float(viewportSize.width)),
                y: CGFloat((1 - ndc.y) * 0.5 * Float(viewportSize.height))
            )
        }

        guard let p0 = toScreen(worldCenter), let p1 = toScreen(worldCenter + SIMD4<Float>(axisNorm, 0)) else {
            return
        }

        let screenDist = hypot(p1.x - p0.x, p1.y - p0.y)
        guard screenDist > 0.001 else {
            return
        }

        let pixelsPerUnit = screenDist
        let screenMag = hypot(screenDelta.width, screenDelta.height)
        let sign: Float = (screenDelta.width * (p1.x - p0.x) + screenDelta.height * (p1.y - p0.y)) > 0 ? 1 : -1
        let worldDelta = Float(screenMag) / Float(pixelsPerUnit) * sign

        let localAxis = axisVectors[axis]
        let offset = dragOffsets[cloudID] ?? .zero
        dragOffsets[cloudID] = offset + localAxis * worldDelta

        if let cloud = loadedCloud.cloud {
            let docTransform = doc.scene.clouds[cloudIndex].transform
            var newTransform = docTransform
            newTransform.translation += dragOffsets[cloudID]!
            cloud.modelTransform = doc.scene.sceneTransform.matrix * newTransform.matrix
        }
    }

    private func commitDrag(cloudID: UUID) {
        guard let offset = dragOffsets[cloudID], offset != .zero, let cloudIndex = multiDocument?.scene.clouds.firstIndex(where: { $0.id == cloudID }) else {
            return
        }
        multiDocument?.scene.clouds[cloudIndex].transform.translation += offset
        dragOffsets[cloudID] = nil
    }

    /// Ensure there's always a cloud selected if clouds exist
    private func ensureSelection() {
        guard let doc = multiDocument else {
            return
        }
        // If current selection is invalid or nil, select the first cloud
        if selectedCloudID == nil || !doc.scene.clouds.contains(where: { $0.id == selectedCloudID }) {
            selectedCloudID = doc.scene.clouds.first?.id
        }
    }

    private func handleAddClouds(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else {
            return
        }

        var cloudRefs: [(ref: SplatScene.CloudReference, didAccess: Bool)] = []

        for url in urls {
            let didStartAccess = url.startAccessingSecurityScopedResource()
            do {
                let cloudRef = try SplatScene.CloudReference(url: url)
                cloudRefs.append((cloudRef, didStartAccess))
            } catch {
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
        }

        for (ref, _) in cloudRefs {
            multiDocument?.scene.clouds.append(ref)
        }

        for (index, url) in urls.enumerated() {
            if index < cloudRefs.count, cloudRefs[index].didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }
}

// MARK: - Convenience Initializers

extension SplatDocumentContentView {
    /// Create view for single splat document
    init(document: SplatDocument, fileURL: URL?) {
        self.init(
            mode: .single,
            singleDocument: document,
            fileURL: fileURL,
            multiDocument: .constant(nil)
        )
    }

    /// Create view for multi-cloud scene document
    init(document: Binding<SplatSceneDocument>) {
        self.init(
            mode: .multi,
            singleDocument: nil,
            fileURL: nil,
            multiDocument: Binding(
                get: { document.wrappedValue },
                set: { document.wrappedValue = $0! }
            )
        )
    }
}

// MARK: - Cloud List Row

struct CloudListRow: View {
    @Binding var cloud: SplatScene.CloudReference
    var onDelete: () -> Void

    private var debugColorBinding: Binding<Color> {
        Binding(
            get: {
                // Convert linear to sRGB for display
                let linear = cloud.debugColor
                let srgb = SIMD3<Float>(
                    linearToSRGB(linear.x),
                    linearToSRGB(linear.y),
                    linearToSRGB(linear.z)
                )
                return Color(
                    red: Double(srgb.x),
                    green: Double(srgb.y),
                    blue: Double(srgb.z)
                )
            },
            set: { newColor in
                // Convert sRGB from picker to linear for storage
                if let components = newColor.cgColor?.components, components.count >= 3 {
                    cloud.debugColor = SIMD3<Float>(
                        srgbToLinear(Float(components[0])),
                        srgbToLinear(Float(components[1])),
                        srgbToLinear(Float(components[2]))
                    )
                }
            }
        )
    }

    private func srgbToLinear(_ value: Float) -> Float {
        if value <= 0.04045 {
            return value / 12.92
        }
        return pow((value + 0.055) / 1.055, 2.4)
    }

    private func linearToSRGB(_ value: Float) -> Float {
        if value <= 0.0031308 {
            return value * 12.92
        }
        return 1.055 * pow(value, 1.0 / 2.4) - 0.055
    }

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $cloud.enabled)
                .labelsHidden()
                #if os(macOS)
                .toggleStyle(.checkbox)
            #endif

            Text(cloud.displayName ?? "Unknown")
                .lineLimit(1)
                .foregroundStyle(cloud.enabled ? .primary : .secondary)

            Spacer()

            ColorPicker("", selection: debugColorBinding, supportsOpacity: false)
                .labelsHidden()
        }
        .contextMenu {
            Toggle("Enabled", isOn: $cloud.enabled)
            Divider()
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
#endif
