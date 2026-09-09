#if os(iOS) || os(visionOS)
import SwiftUI

struct MobileLaunchView: View {
    @State private var openImport = false
    @State private var isShowingWelcome = !UserDefaults.standard.bool(forKey: "doNotShowWelcomeAgain")
    #if os(iOS)
    @State private var restoredDocumentURL: URL?
    #endif

    var body: some View {
        if isShowingWelcome {
            WelcomeView {
                isShowingWelcome = false
            }
        } else {
            #if os(iOS)
            if let url = restoredDocumentURL {
                NavigationStack {
                    SplatDocumentView(
                        document: SplatDocument(),
                        fileURL: url
                    )
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Back", systemImage: "chevron.left") {
                                url.stopAccessingSecurityScopedResource()
                                restoredDocumentURL = nil
                            }
                        }
                    }
                }
            } else {
                documentLaunchView
                    .onAppear {
                        restoredDocumentURL = LastDocumentStore.restoreOnce()
                    }
            }
            #else
            documentLaunchView
            #endif
        }
    }

    @ViewBuilder
    var documentLaunchView: some View {
        #if !os(visionOS)
        DocumentLaunchView(
            "Radiance",
            for: SplatDocument.readableContentTypes
        ) {
            // no launch actions
        } onDocumentOpen: { url in
            SplatDocumentView(
                document: SplatDocument(),
                fileURL: url
            )
        }
        #else
        VStack(spacing: 24) {
            Spacer()

            Image(.splatCloud)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 180, height: 180)
                .glimmer(sweepDuration: 1.5, pauseDuration: 5, gradientWidth: 0.3, maxLightness: 0.3, angle: 35)
                .accessibilityHidden(true)

            Text("Radiance")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Open a splat file to view it in mixed reality")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                openImport = true
            } label: {
                Label("Open Document", systemImage: "doc.badge.plus")
                    .font(.title3)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .padding(40)
        .fileImporter(isPresented: $openImport, allowedContentTypes: SplatDocument.readableContentTypes) { _ in
            // Document opening is handled by the system
        }
        #endif
    }
}

#Preview {
    MobileLaunchView()
}
#endif
