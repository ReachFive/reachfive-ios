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
    private static let actionsKey = "captchaActions"

    /// The action names the SDK web UI uses. A starting point, not a rule: the actions a client
    /// accepts are whatever its console configuration lists, and nothing forces them to be these.
    static let defaultActions = ["login", "signup", "update_email", "passwordless_email", "passwordless_phone", "account_recovery", "password_reset_requested"]

    /// The actions offered when minting a token, in the order the picker shows them. Editable in
    /// Settings, because a token is refused when its action is not one the client declares — and no
    /// error says so.
    static var actions: [String] {
        get {
            guard let stored = UserDefaults.standard.stringArray(forKey: actionsKey), !stored.isEmpty else {
                return defaultActions
            }
            return stored
        }
        set {
            let cleaned = newValue.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if cleaned.isEmpty {
                UserDefaults.standard.removeObject(forKey: actionsKey)
            } else {
                UserDefaults.standard.set(cleaned, forKey: actionsKey)
            }
        }
    }

    /// Back to ``defaultActions``.
    static func resetActions() {
        UserDefaults.standard.removeObject(forKey: actionsKey)
    }

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
