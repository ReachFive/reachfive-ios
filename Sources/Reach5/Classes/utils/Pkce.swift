import Foundation
import CryptoSwift

public class Pkce: NSObject, Codable {
    public let codeVerifier: String
    public let codeChallenge: String
    public let codeChallengeMethod: String
    
    init(codeVerifier: String) {
        self.codeVerifier = codeVerifier
        codeChallenge = Data(Digest.sha256(Array(codeVerifier.utf8)))
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
        
        (1...length).forEach { _ in
            let randomIndex: Int = .random(in: 0..<string.count)
            let c = string.index(string.startIndex, offsetBy: randomIndex)
            randomString += String(string[c])
        }
        
        return randomString
    }
    
    public override var description: String {
        "PKCE codeVerifier=\(codeVerifier) codeChallenge=\(codeChallenge) codeChallengeMethod=\(codeChallengeMethod)"
    }
}
