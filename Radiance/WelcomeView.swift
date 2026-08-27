import SwiftUI

struct WelcomeView: View {
    @AppStorage("doNotShowWelcomeAgain") private var doNotShowAgain = false
    let onDone: () -> Void

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
            }

            Spacer()

            HStack {
                Toggle("Don’t show again", isOn: $doNotShowAgain)

                Spacer()

                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
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
