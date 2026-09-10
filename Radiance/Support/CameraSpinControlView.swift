import simd
import SwiftUI

struct CameraSpinControlView: View {
    @Binding var rotation: simd_quatf
    @State private var startedAt: Date?
    @State private var initialRotation = simd_quatf(angle: 0, axis: [0, 1, 0])

    var body: some View {
        Button(startedAt == nil ? "Spin" : "Stop", systemImage: startedAt == nil ? "arrow.trianglehead.2.clockwise.rotate.90" : "stop.fill") {
            if startedAt == nil {
                initialRotation = rotation
                startedAt = .now
            } else {
                startedAt = nil
            }
        }
        .buttonStyle(.bordered)
        .background {
            TimelineView(.animation(paused: startedAt == nil)) { context in
                Color.clear
                    .onChange(of: context.date) { _, date in
                        guard let startedAt else {
                            return
                        }
                        let angle = Float(date.timeIntervalSince(startedAt)) * .pi / 2
                        rotation = simd_quatf(angle: angle, axis: [0, 1, 0]) * initialRotation
                    }
            }
        }
        .onDisappear { startedAt = nil }
    }
}

#Preview {
    @Previewable @State var rotation = simd_quatf(angle: 0, axis: [0, 1, 0])
    CameraSpinControlView(rotation: $rotation)
}
