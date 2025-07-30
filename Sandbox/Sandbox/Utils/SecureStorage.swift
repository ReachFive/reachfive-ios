import Reach5

public class SecureStorage: Storage {
    private static let authKey = "AUTH_TOKEN"
    private static let refKey = "SHARED_REFS"

    private let serviceName: String
    private let group: String
    private let bundleId: String

    private let sendNotif: Bool

    public init(group: String? = nil, sendNotif: Bool? = nil) {
        bundleId = Bundle.main.bundleIdentifier!
        serviceName = group ?? bundleId
        self.sendNotif = sendNotif ?? true

        self.group = group ?? (Bundle.main.infoDictionary!["AppIdentifierPrefix"] as! String) + bundleId
        print("SecureStorage.init(group: \(group ?? "")) serviceName:\(serviceName) accessGroup: \(self.group)")
    }

    //TODO: mettre tous les accès à la keychain dans une queue à part et renvoyer des Futures?
    public func getToken() -> AuthToken? {
        let refs: Set<String>? = get(key: SecureStorage.refKey)
        print("getToken.refs \(refs)")

        return get(key: SecureStorage.authKey)
    }

    //TODO: utiliser un couple appareil/app au lieu de juste app pour gérer correctement les cas où la même app est utilisées sur plusieurs appareils connectés au même compte iCloud
    public func setToken(_ token: AuthToken) -> ()? {
        set(token, forKey: SecureStorage.authKey).flatMap { _ in
                let refs: Set<String>? = get(key: SecureStorage.refKey)
                print("setToken.refs \(refs)")
                if var refs {
                    if refs.insert(bundleId).inserted {
                        print("setToken.refs.inserted \(refs)")
                        return set(refs, forKey: SecureStorage.refKey)
                    } else {
                        print("setToken.refs.notInserted \(refs)")
                        return ()
                    }
                } else {
                    let ref: Set = [bundleId]
                    print("setToken.refs.added \(ref)")
                    return set(ref, forKey: SecureStorage.refKey)
                }
            }
            .flatMap { r in
                if sendNotif {
                    print("setToken.send .DidSetAuthToken")
                    NotificationCenter.default.post(name: .DidSetAuthToken, object: nil, userInfo: ["token": token])
                }
                return r
            }
    }

    public func removeToken(onLastClear: (() -> Void)? = nil) -> ()? {
        guard var refs: Set<String> = get(key: SecureStorage.refKey) else {
            print("trying to clear a token without references")
            return nil
        }
        print("removeToken.refs \(refs)")
        guard let _ = refs.remove(bundleId) else {
            print("trying to clear a token not present in the references")
            return nil
        }
        print("removeToken.refs.remove(bundleId) \(refs)")
        return set(refs, forKey: SecureStorage.refKey).flatMap { _ in
            if !refs.isEmpty {
                return ()
            }
            return remove(key: SecureStorage.authKey).flatMap { _ in
                onLastClear?()
                if sendNotif {
                    NotificationCenter.default.post(name: .DidClearAuthToken, object: nil)
                }
                return ()
            }
        }
    }

    public func removeAllTokens() -> ()? {
        remove(key: SecureStorage.authKey).flatMap { _ in
            remove(key: SecureStorage.refKey).flatMap { _ in
            }
        }
    }

    public func set<D: Codable>(_ value: D, forKey key: String) -> ()? {
        guard let data = try? JSONEncoder().encode(value) else {
            print(KeychainError.jsonSerializationError)
            return nil
        }

        print("save data: \(data)")

        let attributes = [kSecClass: kSecClassGenericPassword,
                          kSecAttrAccount: key,
                          kSecAttrService: serviceName,
                          kSecAttrAccessGroup: group,
                          kSecAttrSynchronizable: true,
                          kSecValueData: data] as [String: Any]

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            if status == errSecDuplicateItem { // duplicate detected (code -25299). User did not log out before logging again
                print("duplicate detected, updating data instead")
                return update(value, forKey: key)
            } else {
                print(KeychainError.unhandledError(status: status))
                return nil
            }
        }
        return ()
    }

    public func save<D: Codable>(key: String, value: D) {
        if let _ = set(value, forKey: key) {
            //TODO: supprimer une fois que tous les usages sont migrés aux fonctions spécifique des jetons
            if key == SecureStorage.authKey {
                print("send SecureStorage.save.DidSetAuthToken")
                NotificationCenter.default.post(name: .DidSetAuthToken, object: nil)
            }
            print("SecureStorage.save success")
        }
    }

    private func update<D: Codable>(_ value: D, forKey key: String) -> ()? {
        let query = [kSecClass: kSecClassGenericPassword,
                     kSecAttrService: serviceName,
                     kSecAttrAccessGroup: group,
                     kSecAttrSynchronizable: true,
                     kSecAttrAccount: key] as [String: Any]

        guard let data = try? JSONEncoder().encode(value) else {
            print(KeychainError.jsonSerializationError)
            return nil
        }

        let attributes = [kSecAttrAccount: key,
                          kSecAttrService: serviceName,
                          kSecAttrAccessGroup: group,
                          kSecAttrSynchronizable: true,
                          kSecValueData: data] as [String: Any]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard status != errSecItemNotFound else {
            print(KeychainError.noToken)
            return nil
        }

        guard status == errSecSuccess else {
            print(KeychainError.unhandledError(status: status))
            return nil
        }

        return ()
    }

    public func get<D: Codable>(key: String) -> D? {
        let attributes = [kSecClass: kSecClassGenericPassword,
                          kSecAttrAccount: key,
                          kSecAttrService: serviceName,
                          kSecAttrAccessGroup: group,
                          kSecAttrSynchronizable: true,
                          kSecMatchLimit: kSecMatchLimitOne,
                          kSecReturnAttributes: false,
                          kSecReturnData: true] as [String: Any]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &item)
        guard status != errSecItemNotFound else {
            print(KeychainError.noToken)
            return nil
        }
        guard status == errSecSuccess else {
            print(KeychainError.unhandledError(status: status))
            return nil
        }

        guard let existingItem = item as? Data else {
            print(KeychainError.unexpectedTokenData)
            return nil
        }

        do {
            let decode: D = try JSONDecoder().decode(D.self, from: existingItem)
            print("SecureStorage.get success")
            return decode
        } catch {
            print(KeychainError.jsonDeserializationError(error: error))
            return nil
        }
    }

    public func take<D: Codable>(key: String) -> D? {
        let value: D? = self.get(key: key)
        clear(key: key)
        print("SecureStorage.take success")
        return value
    }

    public func remove(key: String) -> ()? {
        let attributes: [String: Any] = [kSecClass: kSecClassGenericPassword,
                                         kSecAttrService: serviceName,
                                         kSecAttrAccessGroup: group,
                                         kSecAttrSynchronizable: true,
                                         kSecAttrAccount: key] as [String: Any]

        let status = SecItemDelete(attributes as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            print(KeychainError.unhandledError(status: status))
            return nil
        }
        return ()
    }

    public func clear(key: String) {
        remove(key: key).map {
            //TODO: supprimer une fois que tous les usages sont migrés aux fonctions spécifique des jetons
            if key == SecureStorage.authKey {
                NotificationCenter.default.post(name: .DidClearAuthToken, object: nil)
            }
            print("SecureStorage.clear success")
        }
    }
}

enum KeychainError: Error {
    case noToken
    case unexpectedTokenData
    case jsonSerializationError
    case jsonDeserializationError(error: Error)
    case unhandledError(status: OSStatus)
}

extension NSNotification.Name {
    static let DidSetAuthToken = Notification.Name("DidSetAuthToken")
    static let DidClearAuthToken = Notification.Name("DidClearAuthToken")
}
