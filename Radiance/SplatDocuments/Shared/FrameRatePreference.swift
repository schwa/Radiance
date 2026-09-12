import MetalSprocketsUI
import SwiftUI

/// User preference for the render loop's frame rate. `.display` follows the screen's maximum refresh rate.
enum FrameRatePreference: Int, CaseIterable, Identifiable {
    case display = 0
    case fps30 = 30
    case fps60 = 60
    case fps120 = 120

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .display:
            "Display (\(Self.displayMaximumFramesPerSecond) FPS)"

        default:
            "\(rawValue) FPS"
        }
    }

    var preferredFramesPerSecond: Int {
        self == .display ? Self.displayMaximumFramesPerSecond : rawValue
    }

    static var displayMaximumFramesPerSecond: Int {
        #if os(macOS)
        NSScreen.main?.maximumFramesPerSecond ?? 60
        #elseif os(iOS)
        UIScreen.main.maximumFramesPerSecond
        #else
        90
        #endif
    }
}

extension View {
    /// Applies the user's frame rate preference to the underlying `MTKView`.
    func frameRatePreference() -> some View {
        modifier(FrameRatePreferenceModifier())
    }
}

private struct FrameRatePreferenceModifier: ViewModifier {
    @AppStorage("frameRatePreference") private var preference = FrameRatePreference.display

    func body(content: Content) -> some View {
        content
            .metalPreferredFramesPerSecond(preference.preferredFramesPerSecond)
    }
}
