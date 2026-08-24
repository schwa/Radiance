#if os(iOS) || os(macOS)
import SwiftUI

struct ImageClassification: Identifiable, Equatable, Sendable {
    let label: String
    let confidence: Float

    var id: String { label }
}

struct AnalysisInspectorView: View {
    let classifications: [ImageClassification]
    @Binding var highlightsSubjects: Bool

    var body: some View {
        Section("Subjects") {
            Toggle("Highlight Subjects", isOn: $highlightsSubjects)
        }

        Section("Classification") {
            ForEach(classifications) { classification in
                LabeledContent(classification.label) {
                    Text(classification.confidence, format: .percent.precision(.fractionLength(1)))
                }
            }
        }
    }
}

#Preview {
    Form {
        AnalysisInspectorView(classifications: [
            ImageClassification(label: "train", confidence: 0.82),
            ImageClassification(label: "railroad", confidence: 0.11)
        ], highlightsSubjects: .constant(true))
    }
}
#endif
