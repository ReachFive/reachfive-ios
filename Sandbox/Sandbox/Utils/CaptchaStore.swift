import Foundation
import Reach5

/// A test instrument, not an integration pattern: a real application obtains its captcha token right
/// before the call that needs it, it never keeps one around in `UserDefaults`.
enum CaptchaStore {
    struct Entry: Codable {
        let token: String
        let provider: String
        let action: String?
        let obtainedAt: Date
    }

    private static let entryKey = "captchaEntry"
    private static let consumesOnUseKey = "captchaConsumesOnUse"

    static var entry: Entry? {
        get {
            guard let data = UserDefaults.standard.data(forKey: entryKey) else { return nil }
            return try? JSONDecoder().decode(Entry.self, from: data)
        }
        set {
            guard let newValue else {
                UserDefaults.standard.removeObject(forKey: entryKey)
                return
            }
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: entryKey)
        }
    }

    static var consumesOnUse: Bool {
        get {
            UserDefaults.standard.object(forKey: consumesOnUseKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: consumesOnUseKey)
        }
    }

    static func take() -> Captcha? {
        guard let entry else { return nil }
        if consumesOnUse {
            clear()
        }
        return Captcha(token: entry.token, provider: CaptchaProvider(rawValue: entry.provider))
    }

    static func peek() -> Entry? {
        entry
    }

    static func clear() {
        entry = nil
    }
}
