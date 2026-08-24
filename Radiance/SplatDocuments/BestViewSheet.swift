#if os(iOS) || os(macOS)
import CoreGraphics
import SwiftUI

struct BestViewCandidate: Identifiable {
    let id: Int
    let image: CGImage
    let orientation: RenderedImageAnalysis.Orientation
    let viewpoint: RenderedImageAnalysis.Viewpoint
    let splatArtifacts: BestViewAssessment.SplatArtifacts
}

enum BestViewAttemptStatus {
    case pending
    case accepted
    case rejected
}

struct BestViewAttempt: Identifiable {
    let id: Int
    let image: CGImage
    var status: BestViewAttemptStatus
}

struct BestViewSheet: View {
    let candidates: [BestViewCandidate]
    let attempts: [BestViewAttempt]
    let isSearching: Bool
    let attemptedCount: Int
    let rejectedCount: Int
    let totalCount: Int
    let recommendedCandidate: Int?
    @Binding var selectedCandidate: Int?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @ViewBuilder
    private var attemptRibbon: some View {
        if !attempts.isEmpty {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack {
                        ForEach(attempts) { attempt in
                            Image(decorative: attempt.image, scale: 1)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 72, height: 72)
                                .clipShape(.rect(cornerRadius: 8))
                                .overlay {
                                    if attempt.status == .rejected {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title)
                                            .foregroundStyle(.white, .red)
                                            .accessibilityHidden(true)
                                    }
                                }
                        }
                    }
                    .padding(.horizontal)
                }
                .scrollIndicators(.hidden)
                .onChange(of: attempts.count) {
                    if let id = attempts.last?.id {
                        withAnimation {
                            proxy.scrollTo(id, anchor: .trailing)
                        }
                    }
                }
            }
        }
    }

    private var statusText: String {
        "\(candidates.count) accepted · \(rejectedCount) rejected · \(attemptedCount) of \(totalCount) checked"
    }

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    VStack {
                        ProgressView("Finding Best View…")
                            .padding()
                        Text(statusText)
                            .foregroundStyle(.secondary)
                        attemptRibbon
                    }
                } else {
                    VStack {
                        if isSearching {
                            VStack {
                                ProgressView("Trying more interior views…")
                                    .padding()
                                Text(statusText)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        attemptRibbon
                        ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))]) {
                            ForEach(candidates) { candidate in
                                Button {
                                    selectedCandidate = candidate.id
                                } label: {
                                    Image(decorative: candidate.image, scale: 1)
                                        .resizable()
                                        .scaledToFit()
                                        .overlay(alignment: .bottomLeading) {
                                            VStack(alignment: .leading) {
                                                Text(candidate.viewpoint.bestViewTitle)
                                                Text(candidate.orientation.title)
                                                Text(candidate.splatArtifacts.title)
                                            }
                                            .bold()
                                            .foregroundStyle(.white)
                                            .padding()
                                            .background(.black.opacity(0.65), in: .rect(cornerRadius: 8))
                                            .padding()
                                        }
                                        .overlay(alignment: .topTrailing) {
                                            if candidate.id == recommendedCandidate {
                                                Label("Best", systemImage: "sparkles")
                                                    .labelStyle(.iconOnly)
                                                    .padding()
                                                    .background(.tint, in: .circle)
                                                    .foregroundStyle(.white)
                                                    .padding()
                                            }
                                        }
                                        .overlay {
                                            if candidate.id == selectedCandidate {
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(.tint, lineWidth: 4)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("View \(candidate.id + 1), \(candidate.viewpoint.bestViewTitle), \(candidate.orientation.title)")
                                .accessibilityAddTraits(candidate.id == selectedCandidate ? .isSelected : [])
                            }
                        }
                        .padding()
                        }
                    }
                }
            }
            .navigationTitle("Best View")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK", action: onConfirm)
                        .disabled(selectedCandidate == nil)
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

private extension RenderedImageAnalysis.Viewpoint {
    var bestViewTitle: String {
        switch self {
        case .insideScene:
            "Scene"

        case .outsideLookingAtSubject:
            "Object"

        case .uncertain:
            "Uncertain"
        }
    }
}

private extension BestViewAssessment.SplatArtifacts {
    var title: String {
        switch self {
        case .low:
            "Clean"

        case .moderate:
            "Some Floating Splats"

        case .high:
            "Too Splatty"
        }
    }
}

#Preview("Loading") {
    BestViewSheet(
        candidates: [],
        attempts: [],
        isSearching: true,
        attemptedCount: 8,
        rejectedCount: 8,
        totalCount: 36,
        recommendedCandidate: nil,
        selectedCandidate: .constant(nil),
        onConfirm: { _ = () },
        onCancel: { _ = () }
    )
}
#endif
