#if os(iOS) || os(macOS)
import GeometryLite3D
import Interaction3D
import simd
import SwiftUI

struct CameraInspector: View {
    @Binding var cameraMode: CameraMode
    @Binding var zoomToFit: Bool
    @Binding var verticalAngleOfView: Double
    @Binding var nearClip: Double
    @Binding var farClip: Double
    @Binding var cameraMatrix: simd_float4x4
    var viewSize: CGSize
    var zoomToFitDisabled = false
    var boundsCenter: SIMD3<Float> = .zero
    var teleportDisabled = false

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Section("Control") {
            Picker("Mode", selection: $cameraMode) {
                ForEach(CameraMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(controlDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section {
            CameraPositionEditor(matrix: $cameraMatrix)
                .disabled(teleportDisabled)
            Text("Metres from cloud origin. Drag a label to scrub.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            sectionHeader("Position", actionTitle: "Reset", action: resetPosition)
        }

        Section {
            CameraOrientationEditor(matrix: $cameraMatrix)
        } header: {
            sectionHeader("Orientation", actionTitle: "Level", action: levelCamera)
        }

        Section("Lens") {
            AngleOfViewControl(verticalDegrees: $verticalAngleOfView, aspectRatio: aspectRatio)
            ClippingRangeControl(near: $nearClip, far: $farClip)
            Text("Vertical \(verticalAngleOfView.formatted(.number.precision(.fractionLength(0))))° at \(aspectRatio.formatted(.number.precision(.fractionLength(2)))):1.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Framing") {
            Toggle("Keep cloud in frame", isOn: $zoomToFit)
                .disabled(cameraMode != .object || zoomToFitDisabled)
            LabeledContent("Orbit target", value: "cloud centre")
                .foregroundStyle(.secondary)
        }

        Section {
            DisclosureGroup("Viewport readout") {
                LabeledContent("Size", value: "\(formattedDimension(viewSize.width)) × \(formattedDimension(viewSize.height))")
                LabeledContent("Aspect ratio", value: aspectRatio.formatted(.number.precision(.fractionLength(2))) + ":1")
                LabeledContent("Megapixels", value: megapixels.formatted(.number.precision(.fractionLength(2))) + " MP")
                if displayScale != 1 {
                    LabeledContent("Scale", value: "\(Int(displayScale))x")
                }
            }
        }
    }

    private var controlDescription: LocalizedStringKey {
        switch cameraMode {
        case .object:
            "Orbit and zoom around the cloud centre."

        case .room:
            "Move through the scene at a fixed height."

        case .spatialScene:
            "Move and rotate freely through the spatial scene."
        }
    }

    private var aspectRatio: Double {
        guard viewSize.height > 0 else {
            return 1
        }
        return Double(viewSize.width / viewSize.height)
    }

    private var megapixels: Double {
        guard viewSize.width > 0, viewSize.height > 0 else {
            return 0
        }
        return Double(viewSize.width * displayScale * viewSize.height * displayScale / 1_000_000)
    }

    private func sectionHeader(_ title: LocalizedStringKey, actionTitle: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button(actionTitle, action: action)
                .textCase(nil)
        }
    }

    private func resetPosition() {
        var pose = CameraPose(matrix: cameraMatrix)
        pose.position = boundsCenter
        cameraMatrix = pose.matrix
    }

    private func levelCamera() {
        var pose = CameraPose(matrix: cameraMatrix)
        pose.rotationDegrees.x = 0
        pose.rotationDegrees.z = 0
        cameraMatrix = pose.matrix
    }

    private func formattedDimension(_ value: CGFloat) -> String {
        let points = Int(value)
        guard displayScale != 1 else {
            return "\(points)"
        }
        return "\(points) (\(Int(value * displayScale)))"
    }
}
#endif
