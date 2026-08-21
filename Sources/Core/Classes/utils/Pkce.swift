import CryptoKit
import Foundation

public class Pkce: NSObject, Codable {
    public let codeVerifier: String
    public let codeChallenge: String
    public let codeChallengeMethod: String

    init(codeVerifier: String) {
        self.codeVerifier = codeVerifier
        codeChallenge = Data(SHA256.hash(data: Data(codeVerifier.utf8)))
            .toBase64Url()
            .trimmingCharacters(in: .whitespaces)
        codeChallengeMethod = "S256"
    }

    public static func generate() -> Pkce {
        let codeVerifier = random(length: 125)
        return Pkce(codeVerifier: codeVerifier)
    }

    static func random(length: Int) -> String {
        let string = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

        guard length > 0 else {
            return ""
        }

        var randomString = ""

        for _ in 1 ... length {
            let randomIndex: Int = .random(in: 0 ..< string.count)
            let c = string.index(string.startIndex, offsetBy: randomIndex)
            randomString += String(string[c])
        }

        return randomString
    }

    override public var description: String {
        "PKCE codeVerifier=\(codeVerifier) codeChallenge=\(codeChallenge) codeChallengeMethod=\(codeChallengeMethod)"
    }
}
