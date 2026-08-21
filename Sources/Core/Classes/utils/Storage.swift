import Foundation

public protocol Storage {
    func save(key: String, value: some Codable)
    func get<D: Codable>(key: String) -> D?
    func take<D: Codable>(key: String) -> D?
    func clear(key: String)
}

public class UserDefaultsStorage: Storage {
    public init() {}

    public func save(key: String, value: some Codable) {
        let data = try? JSONEncoder().encode(value)
        UserDefaults.standard.set(data, forKey: key)
    }

    public func get<T: Codable>(key: String) -> T? {
        guard let data = UserDefaults.standard.value(forKey: key) as? Data else {
            return nil
        }

        return try? JSONDecoder().decode(T.self, from: data)
    }

    public func take<D: Decodable & Encodable>(key: String) -> D? {
        defer {
            clear(key: key)
        }

        return get(key: key)
    }

    public func clear(key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
