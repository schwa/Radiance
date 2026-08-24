#if os(iOS) || os(macOS)
import SwiftUI

struct ImageClassification: Identifiable, Equatable, Sendable {
    let label: String
    let confidence: Float

    var id: String { label }
}

struct ImageClassificationBarView: View {
    let classifications: [ImageClassification]
    @Binding var highlightsSubjects: Bool

    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                Label("Classification", systemImage: "sparkles")
                    .bold()

                Toggle("Highlight Subjects", isOn: $highlightsSubjects)
                    .toggleStyle(.switch)

                ForEach(classifications) { classification in
                    Text("\(classification.label) \(classification.confidence, format: .percent.precision(.fractionLength(1)))")
                }
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .background(.bar)
    }
}

#Preview {
    ImageClassificationBarView(classifications: [
        ImageClassification(label: "train", confidence: 0.82),
        ImageClassification(label: "railroad", confidence: 0.11)
    ], highlightsSubjects: .constant(true))
}
#endif
