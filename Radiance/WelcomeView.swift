import SwiftUI

struct WelcomeView: View {
    @AppStorage(DismissedHints.storageKey) private var dismissedHints = DismissedHints.legacyDefault
    @State private var doNotShowAgain = true
    let onDone: () -> Void
    var onOpenSample: ((URL) -> Void)?

    static var embeddedSampleURL: URL? {
        Bundle.main.url(forResource: "tomatoes.v4", withExtension: "spz")
    }

    private let features = [
        ("view.3d", "Explore Gaussian splats in 3D"),
        ("eye", "Preview splat files with Quick Look"),
        ("photo", "Convert photos into Gaussian splats"),
        ("camera", "Export high-quality screenshots")
    ]

    var body: some View {
        VStack {
            Spacer()

            Image(.splatCloud)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 112, height: 112)
                .glimmer(
                    sweepDuration: 1.5,
                    pauseDuration: 5,
                    gradientWidth: 0.3,
                    maxLightness: 0.3,
                    angle: 35
                )
                .accessibilityHidden(true)

            VStack {
                Text("Welcome to Radiance")
                    .font(.largeTitle)
                    .bold()

                Text("View and explore 3D Gaussian splats.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .leading) {
                ForEach(features, id: \.1) { symbol, title in
                    Label {
                        Text(title)
                    } icon: {
                        Image(systemName: symbol)
                            .foregroundStyle(.tint)
                            .frame(width: 24)
                    }
                }
            }

            Spacer()

            VStack {
                Text("Need something to explore?")
                    .foregroundStyle(.secondary)
                SampleAssetsDownloadView()
                if let sampleURL = Self.embeddedSampleURL, let onOpenSample {
                    Button("Open the Tomatoes Sample") {
                        onOpenSample(sampleURL)
                    }
                    Text("Tomatoes scan by Grail (superspl.at), CC BY 4.0")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(spacing: 16) {
                Button {
                    // Persist even when the toggle was left at its default.
                    if doNotShowAgain {
                        dismissedHints.insert(.welcome)
                    } else {
                        dismissedHints.remove(.welcome)
                    }
                    onDone()
                } label: {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .frame(maxWidth: 320)

                Toggle("Don’t show again", isOn: $doNotShowAgain)
                    .fixedSize()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(
                colors: [.accentColor.opacity(0.12), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
    }
}

#Preview {
    WelcomeView { _ = () }
}
