#if os(iOS) || os(macOS)
import FoundationModels
import SwiftUI

struct ImageClassification: Identifiable, Equatable, Sendable {
    let label: String
    let confidence: Float

    var id: String { label }
}

struct VisionImageAnalysis: Equatable, Sendable {
    let horizonAngleDegrees: Double?
    let horizonConfidence: Float?
    let aestheticsScore: Float
    let isUtility: Bool
}

@Generable
struct RenderedImageAnalysis {
    @Generable
    enum Orientation {
        case upright
        case upsideDown
        case sidewaysLeft
        case sidewaysRight
        case uncertain

        var title: String {
            switch self {
            case .upright:
                "Upright"

            case .upsideDown:
                "Upside Down"

            case .sidewaysLeft:
                "Sideways Left"

            case .sidewaysRight:
                "Sideways Right"

            case .uncertain:
                "Uncertain"
            }
        }
    }

    @Generable
    enum Viewpoint {
        case insideScene
        case outsideLookingAtSubject
        case uncertain

        var title: String {
            switch self {
            case .insideScene:
                "Inside Scene"

            case .outsideLookingAtSubject:
                "Outside Looking At Subject"

            case .uncertain:
                "Uncertain"
            }
        }
    }

    @Generable
    enum Framing {
        case wellFramed
        case subjectCropped
        case tooClose
        case tooDistant
        case noClearSubject
        case uncertain

        var title: String {
            switch self {
            case .wellFramed:
                "Well Framed"

            case .subjectCropped:
                "Subject Cropped"

            case .tooClose:
                "Too Close"

            case .tooDistant:
                "Too Distant"

            case .noClearSubject:
                "No Clear Subject"

            case .uncertain:
                "Uncertain"
            }
        }
    }

    let orientation: Orientation
    let viewpoint: Viewpoint
    let framing: Framing
    let description: String
}

@Generable
struct BestViewAssessment {
    @Generable
    enum SplatArtifacts {
        case low
        case moderate
        case high
    }

    @Generable
    enum Content {
        case recognizable
        case unrecognizable
    }

    @Generable
    enum SceneKind {
        case indoor
        case outdoor
        case object
        case uncertain
    }

    let orientation: RenderedImageAnalysis.Orientation
    let sceneKind: SceneKind
    let splatArtifacts: SplatArtifacts
    let content: Content
}

@Generable
struct BestViewOrientationAssessment {
    let orientation: RenderedImageAnalysis.Orientation
}

@Generable
struct BestViewSelection {
    let candidate: Int
}

struct AnalysisInspectorView: View {
    let classifications: [ImageClassification]
    let visionImageAnalysis: VisionImageAnalysis?
    @Binding var highlightsSubjects: Bool
    let imageOrientation: RenderedImageAnalysis.Orientation?
    let imageViewpoint: RenderedImageAnalysis.Viewpoint?
    let imageFraming: RenderedImageAnalysis.Framing?
    let imageDescription: String?
    let isDescribingImage: Bool
    let describeImage: () -> Void
    let flipCamera: () -> Void
    let moveCameraInside: () -> Void
    let snapToHorizon: () -> Void

    var body: some View {
        Section("Subjects") {
            Toggle("Highlight Subjects", isOn: $highlightsSubjects)
        }

        Section("Description") {
            Button(action: describeImage) {
                if isDescribingImage {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Describe Image")
                }
            }
            .disabled(isDescribingImage)

            if let imageOrientation {
                LabeledContent("Orientation") {
                    HStack {
                        Text(imageOrientation.title)
                        if imageOrientation == .upsideDown {
                            Button("Flip", action: flipCamera)
                                .controlSize(.small)
                        }
                    }
                }
            }

            if let imageViewpoint {
                LabeledContent("Viewpoint") {
                    HStack {
                        Text(imageViewpoint.title)
                        if imageViewpoint == .outsideLookingAtSubject {
                            Button("Fix", action: moveCameraInside)
                                .controlSize(.small)
                        }
                    }
                }
            }

            if let imageFraming {
                LabeledContent("Framing", value: imageFraming.title)
            }

            if let imageDescription {
                Text(imageDescription)
                    .textSelection(.enabled)
            }
        }

        if let visionImageAnalysis {
            Section("Vision") {
                if let horizonAngleDegrees = visionImageAnalysis.horizonAngleDegrees {
                    LabeledContent("Horizon Angle") {
                        HStack {
                            Text(horizonAngleDegrees.formatted(.number.precision(.fractionLength(1))) + "°")
                            if let horizonConfidence = visionImageAnalysis.horizonConfidence, horizonConfidence > 0.8 {
                                Button("Snap", action: snapToHorizon)
                                    .controlSize(.small)
                            }
                        }
                    }
                    if let horizonConfidence = visionImageAnalysis.horizonConfidence {
                        LabeledContent("Horizon Confidence") {
                            Text(horizonConfidence, format: .percent.precision(.fractionLength(1)))
                        }
                    }
                } else {
                    LabeledContent("Horizon", value: "Not Detected")
                }
                LabeledContent("Aesthetics Score", value: visionImageAnalysis.aestheticsScore.formatted(.number.precision(.fractionLength(2))))
                LabeledContent("Image Type", value: visionImageAnalysis.isUtility ? "Utility" : "Aesthetic")
            }
        }

        Section("Classification") {
            ForEach(classifications) { classification in
                LabeledContent(classification.label) {
                    Text(classification.confidence, format: .percent.precision(.fractionLength(1)))
                }
            }
        }
    }
}

#Preview {
    Form {
        AnalysisInspectorView(
            classifications: [
                ImageClassification(label: "train", confidence: 0.82),
                ImageClassification(label: "railroad", confidence: 0.11)
            ],
            visionImageAnalysis: VisionImageAnalysis(horizonAngleDegrees: 1.2, horizonConfidence: 0.91, aestheticsScore: 0.72, isUtility: false),
            highlightsSubjects: .constant(true),
            imageOrientation: .upright,
            imageViewpoint: .outsideLookingAtSubject,
            imageFraming: .wellFramed,
            imageDescription: "The image appears upright and shows an object viewed from outside.",
            isDescribingImage: false,
            describeImage: { _ = () },
            flipCamera: { _ = () },
            moveCameraInside: { _ = () },
            snapToHorizon: { _ = () }
        )
    }
}
#endif
