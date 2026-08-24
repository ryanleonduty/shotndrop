import AppKit
import SwiftUI
import Combine
import CoreText

/// Solo Leveling pixel design system. `Palette`, `Font`, `Motion`, `Geometry`
/// under one namespace so every UI file resolves colors, faces, timings, and
/// slot dimensions from a single source.
public enum PixelDesign {

    // MARK: Palette

    public enum Palette {
        public static let void = Color(hex: 0x050813)
        public static let midnight = Color(hex: 0x0A0F1E)
        public static let rune = Color(hex: 0x1B2542)
        public static let rune2 = Color(hex: 0x2A3560)
        public static let rune3 = Color(hex: 0x3D4A78)
        public static let cyan = Color(hex: 0x66E1FF)
        public static let cyanSoft = Color(hex: 0x4FC3F7)
        public static let cyanDim = Color(hex: 0x2E7A9E)
        public static let violet = Color(hex: 0x7B5CFF)
        public static let violetDim = Color(hex: 0x5F3DC4)
        public static let white = Color(hex: 0xE8F4FF)
        public static let whiteDim = Color(hex: 0x8AA0C8)
        public static let gold = Color(hex: 0xFFB800)
        public static let danger = Color(hex: 0xFF3B4B)
    }

    // MARK: Font

    public enum Font {
        public enum Role: Hashable, Sendable {
            case display    // Press Start 2P
            case body      // VT323
            case caption   // Silkscreen Regular
            case captionBold // Silkscreen Bold
        }

        static let familyMap: [Role: String] = [
            .display: "Press Start 2P",
            .body: "VT323",
            .caption: "Silkscreen",
            .captionBold: "Silkscreen"
        ]

        private static let resourceMap: [Role: String] = [
            .display: "PressStart2P-Regular",
            .body: "VT323-Regular",
            .caption: "Silkscreen-Regular",
            .captionBold: "Silkscreen-Bold"
        ]

        nonisolated(unsafe) private static var registered: Bool = false
        private static let registrationLock = NSLock()

        /// Registers the four bundled `.ttf` files via
        /// `CTFontManagerRegisterFontsForURL`. Subsequent calls in the same
        /// process are treated as success (matches
        /// `kCTFontManagerErrorAlreadyRegistered`).
        @discardableResult
        public static func registerAll(bundle: Bundle = .main) -> Bool {
            registrationLock.lock()
            defer { registrationLock.unlock() }
            if registered { return true }
            var allOK = true
            for (_, resource) in resourceMap {
                guard let url = bundle.url(forResource: resource, withExtension: "ttf") else {
                    NSLog("PixelDesign.Font missing resource: \(resource).ttf")
                    allOK = false
                    continue
                }
                var errorRef: Unmanaged<CFError>?
                let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &errorRef)
                if !ok, let error = errorRef?.takeRetainedValue() {
                    let code = CFErrorGetCode(error)
                    if code == CTFontManagerError.alreadyRegistered.rawValue {
                        continue
                    }
                    NSLog("PixelDesign.Font failed to register \(resource): \(error)")
                    allOK = false
                }
            }
            registered = allOK
            return allOK
        }

        /// SwiftUI face accessor.
        public static func face(_ role: Role, size: CGFloat) -> SwiftUI.Font {
            if let family = familyMap[role] {
                return SwiftUI.Font.custom(family, size: size)
            }
            return SwiftUI.Font.system(size: size, design: .monospaced)
        }

        /// AppKit face accessor (for NSAttributedString use).
        public static func nsFace(_ role: Role, size: CGFloat) -> NSFont {
            if let family = familyMap[role],
               let font = NSFont(name: family, size: size) {
                return font
            }
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }

    // MARK: Motion

    public enum Motion {
        public static let steppedTransitionDuration: TimeInterval = 0.120
        public static let steppedTransitionSteps: Int = 4
        public static let ambientPulsePeriod: TimeInterval = 2.4
        public static let flashDuration: TimeInterval = 0.240
        public static let scanlinePeriod: TimeInterval = 1.6
        public static let steppedShakeAmplitude: CGFloat = 3
        public static let steppedShakeSteps: Int = 4
        public static let steppedShakeDuration: TimeInterval = 0.240

        /// The `[+A, -A, +A, 0]` offset sequence used for rejection shake.
        public static func shakeOffsets(amplitude: CGFloat = steppedShakeAmplitude) -> [CGFloat] {
            [+amplitude, -amplitude, +amplitude, 0]
        }
    }

    // MARK: Reduced motion

    /// Runtime-tracking reduced-motion state. Subscribers get the current
    /// value on subscribe and every subsequent change (via the AppKit
    /// accessibility notification).
    @MainActor
    public final class ReducedMotion: ObservableObject {
        public static let shared = ReducedMotion()

        @Published public private(set) var isReduced: Bool

        private var observer: NSObjectProtocol?

        private init() {
            self.isReduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            observer = NotificationCenter.default.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: NSWorkspace.shared,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.isReduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                }
            }
        }
    }

    // MARK: Geometry

    public enum Geometry {
        public static let slotSize: CGFloat = 96
        public static let slotBorderWidth: CGFloat = 2
        public static let bracketLength: CGFloat = 14
        public static let bracketOffsetIdle: CGFloat = 8
        public static let bracketOffsetHover: CGFloat = 12
        public static let bracketLengthHover: CGFloat = 18
        public static let trayWidth: CGFloat = 240
        public static let trayHeaderHeight: CGFloat = 32
        public static let trayFooterHeight: CGFloat = 28
        public static let trayRowHeight: CGFloat = 60
    }
}

extension Color {
    /// Convenience initializer from a 0xRRGGBB literal.
    public init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
