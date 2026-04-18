import AppKit

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let userDefaultsKey = "app.appearance"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }

    /// Reads the current preference from UserDefaults.
    static var current: AppearancePreference {
        let raw = UserDefaults.standard.string(forKey: userDefaultsKey) ?? ""
        return AppearancePreference(rawValue: raw) ?? .system
    }

    /// Applies the current preference to `NSApp.appearance`. Safe to call anytime.
    static func apply() {
        NSApp?.appearance = current.nsAppearance
    }
}
