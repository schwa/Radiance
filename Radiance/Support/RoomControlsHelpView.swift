import SwiftUI

struct RoomControlsHelpView: View {
    @AppStorage(DismissedHints.storageKey) private var dismissedHints = DismissedHints.legacyDefault
    @State private var isClosed = false

    var body: some View {
        if !isClosed, !dismissedHints.contains(.roomControls) {
            VStack(alignment: .leading) {
                HStack {
                    Text("Room Controls")
                        .font(.headline)
                    Spacer()
                    Button("Close room controls", systemImage: "xmark") {
                        isClosed = true
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                }
                Text("W / S: move forward and back · A / D: strafe")
                Text("↑ / ↓: move · ← / →: turn · Drag: look around")
                Text("Click the scene to use keyboard controls.")
                    .foregroundStyle(.secondary)
                Toggle("Don’t show again", isOn: Binding {
                    dismissedHints.contains(.roomControls)
                } set: { hidden in
                    if hidden {
                        dismissedHints.insert(.roomControls)
                    } else {
                        dismissedHints.remove(.roomControls)
                    }
                })
            }
            .font(.callout)
            .padding()
            .background(.regularMaterial, in: .rect(cornerRadius: 12))
            .fixedSize()
            .padding()
        }
    }
}

#Preview {
    RoomControlsHelpView()
}
