#if os(iOS) || os(macOS)
import SwiftUI

/// View for editing and rendering a splat scene with multiple clouds
/// Delegates to SplatDocumentContentView for consistent UI across document types
struct SplatSceneView: View {
    @Binding var document: SplatSceneDocument

    @State private var viewModel = SplatViewModel(mode: .multi)

    var body: some View {
        SplatDocumentContentView(document: $document, viewModel: viewModel)
    }
}
#endif
