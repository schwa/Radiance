import SwiftUI

struct WelcomeView: View {
    @AppStorage("doNotShowWelcomeAgain") private var doNotShowAgain = false
    let onDone: () -> Void

    var body: some View {
        VStack {
            HStack {
                Label("Welcome to Gaussian Splats", systemImage: "sparkles")
                    .font(.title)
                Spacer()
                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
            }

            Form {
                Section {
                    Text("View and explore 3D Gaussian splats, or download sample files from the Spark project to get started.")
                }

                Section("Sample Splats") {
                    Link("sparkjs.dev", destination: URL(string: "https://sparkjs.dev")!)
                    SampleAssetsDownloadView()
                }

                Section {
                    Toggle("Don’t show again", isOn: $doNotShowAgain)
                }
            }
            .formStyle(.grouped)
        }
        .padding()
    }
}

#Preview {
    WelcomeView { _ = () }
}
