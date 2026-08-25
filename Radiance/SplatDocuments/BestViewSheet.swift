#if os(iOS) || os(macOS)
import CoreGraphics
import Foundation
import ImageIO
import simd
import SwiftUI
import UniformTypeIdentifiers

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct BestViewCandidate: Identifiable {
    let id: Int
    let image: CGImage
    let cameraMatrix: simd_float4x4
    let orientation: RenderedImageAnalysis.Orientation
    let sceneKind: BestViewAssessment.SceneKind
    let splatArtifacts: BestViewAssessment.SplatArtifacts
}

enum BestViewRejectionReason {
    case empty
    case noContent
    case object
    case tooSplatty
    case sideways
    case upsideDown
    case uncertainOrientation

    var title: String {
        switch self {
        case .empty:
            "Empty"

        case .noContent:
            "No Content"

        case .object:
            "Object"

        case .tooSplatty:
            "Too Splatty"

        case .sideways:
            "Sideways"

        case .upsideDown:
            "Upside Down"

        case .uncertainOrientation:
            "Orientation?"
        }
    }
}

enum BestViewAttemptStatus {
    case pending
    case accepted
    case rejected(BestViewRejectionReason)
}

struct BestViewAttempt: Identifiable {
    let id: Int
    let image: CGImage
    let cameraMatrix: simd_float4x4
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
    @State private var copyError: String?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @ViewBuilder
    private func copyContextMenu(image: CGImage, cameraMatrix: simd_float4x4) -> some View {
        Button("Copy Camera Transform", systemImage: "camera") {
            copyCameraTransform(cameraMatrix)
        }
        Button("Copy Image File", systemImage: "photo") {
            copyImageFile(image)
        }
    }

    private func copyCameraTransform(_ matrix: simd_float4x4) {
        let columns = [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3]
        let string = columns
            .map { column in
                "[\(column.x), \(column.y), \(column.z), \(column.w)]"
            }
            .joined(separator: ",\n")
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("[\n\(string)\n]", forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = "[\n\(string)\n]"
        #endif
    }

    private func copyImageFile(_ image: CGImage) {
        do {
            let directory = URL.cachesDirectory.appending(path: "BestView", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: "best-view-\(UUID()).png")
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                throw CopyImageError.cannotCreateFile
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw CopyImageError.cannotWriteFile
            }
            #if canImport(AppKit)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(url.absoluteString, forType: .fileURL)
            #elseif canImport(UIKit)
            UIPasteboard.general.url = url
            #endif
        } catch {
            copyError = error.localizedDescription
        }
    }

    private enum CopyImageError: LocalizedError {
        case cannotCreateFile
        case cannotWriteFile

        var errorDescription: String? {
            switch self {
            case .cannotCreateFile:
                "Could not create the cached image file."

            case .cannotWriteFile:
                "Could not write the cached image file."
            }
        }
    }

    private var statusText: String {
        "\(candidates.count) accepted · \(rejectedCount) rejected · \(attemptedCount) of \(totalCount) checked"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack {
                    Text(statusText)
                        .foregroundStyle(.secondary)
                    BestViewAttemptRibbonView(
                        attempts: attempts,
                        onCopyCamera: copyCameraTransform,
                        onCopyImage: copyImageFile
                    )
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                        ForEach(candidates) { candidate in
                            Button {
                                selectedCandidate = candidate.id
                            } label: {
                                Image(decorative: candidate.image, scale: 1)
                                    .resizable()
                                    .scaledToFit()
                                    .overlay(alignment: .bottomLeading) {
                                        VStack(alignment: .leading) {
                                            Text(candidate.sceneKind.title)
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
                                    .contextMenu {
                                        copyContextMenu(image: candidate.image, cameraMatrix: candidate.cameraMatrix)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("View \(candidate.id + 1), \(candidate.sceneKind.title), \(candidate.orientation.title)")
                            .accessibilityAddTraits(candidate.id == selectedCandidate ? .isSelected : [])
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Best View")
            .toolbar {
                if isSearching {
                    ToolbarItem {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Finding Best View")
                    }
                }
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
        .alert("Copy Failed", isPresented: Binding(
            get: { copyError != nil },
            set: { if !$0 { copyError = nil } }
        )) {
            Button("OK", role: .cancel) {
                copyError = nil
            }
        } message: {
            Text(copyError ?? "Unknown error")
        }
    }
}

private struct BestViewAttemptRibbonView: View {
    let attempts: [BestViewAttempt]
    let onCopyCamera: (simd_float4x4) -> Void
    let onCopyImage: (CGImage) -> Void

    var body: some View {
        if !attempts.isEmpty {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack {
                        ForEach(attempts) { attempt in
                            Image(decorative: attempt.image, scale: 1)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 96, height: 72)
                                .clipShape(.rect(cornerRadius: 8))
                                .overlay(alignment: .bottom) {
                                    if case .rejected(let reason) = attempt.status {
                                        Label(reason.title, systemImage: "xmark")
                                            .font(.caption)
                                            .bold()
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 4)
                                            .background(.red, in: .capsule)
                                    }
                                }
                                .contextMenu {
                                    Button("Copy Camera Transform", systemImage: "camera") {
                                        onCopyCamera(attempt.cameraMatrix)
                                    }
                                    Button("Copy Image File", systemImage: "photo") {
                                        onCopyImage(attempt.image)
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
}

private extension BestViewAssessment.SceneKind {
    var title: String {
        switch self {
        case .indoor:
            "Indoor Scene"

        case .outdoor:
            "Outdoor Scene"

        case .object:
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

#Preview("Empty Attempt Ribbon") {
    BestViewAttemptRibbonView(
        attempts: [],
        onCopyCamera: { _ = $0 },
        onCopyImage: { _ = $0 }
    )
}
#endif
