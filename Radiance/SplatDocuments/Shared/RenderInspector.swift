#if os(iOS) || os(macOS)
import MetalSprocketsGaussianSplats
import MetalSprocketsGaussianSplatsDebug
import SwiftUI

struct RenderInspector<CullingContent: View>: View {
    @Binding var backgroundColor: Color
    @Binding var gridColor: Color
    @Binding var useSphericalHarmonics: Bool
    var rendererSelectionDisabled = false
    var supportsBoundsCulling = false
    var sphericalHarmonicsDisabled: Bool = false
    var sphericalHarmonicsWarning: String?
    @Binding var showBoundingBoxes: Bool
    @Binding var showReferenceGrid: Bool
    @Binding var showAxisLines: Bool
    @Binding var debugModeEnabled: Bool
    @Binding var debugMode: SplatDebugMode
    var onScreenshot: (() -> Void)?
    @ViewBuilder var cullingContent: () -> CullingContent

    @Environment(SplatViewModel.self) private var viewModel
    @AppStorage("showFPSOverlay") private var showFPSOverlay = false

    var body: some View {
        @Bindable var viewModel = viewModel
        Section("Renderer") {
            if !rendererSelectionDisabled {
                Picker("Type", selection: $viewModel.renderer) {
                    ForEach(SplatRenderer.allCases.filter { $0 != .sparkCPU }, id: \.self) { renderer in
                        Text(renderer == .sparkGPU ? "Spark (GPU Sort)" : renderer.rawValue.capitalized).tag(renderer)
                    }
                }
            }
            Toggle("Show FPS", isOn: $showFPSOverlay)
            ColorPicker("Background", selection: $backgroundColor)
            Toggle("Spherical Harmonics", isOn: $useSphericalHarmonics)
                .disabled(sphericalHarmonicsDisabled || debugModeEnabled)

            if let warning = sphericalHarmonicsWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Toggle("Show Bounding Boxes", isOn: $showBoundingBoxes)
            Toggle("Show Reference Grid", isOn: $showReferenceGrid)
            if showReferenceGrid {
                ColorPicker("Grid Color", selection: $gridColor)
            }
            Toggle("Show Axis Lines", isOn: $showAxisLines)
        }

        Section("Debug Visualization") {
            Toggle("Enable Debug Mode", isOn: $debugModeEnabled)

            if debugModeEnabled {
                Picker("Mode", selection: $debugMode) {
                    ForEach(SplatDebugMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Text(debugMode.colorDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if supportsBoundsCulling {
            cullingContent()
        }

        if let onScreenshot {
            Section("Export") {
                Button("Take Screenshot", systemImage: "camera") {
                    onScreenshot()
                }
            }
        }
    }
}
#endif
