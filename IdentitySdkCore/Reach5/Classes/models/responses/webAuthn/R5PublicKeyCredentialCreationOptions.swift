import Foundation

public class R5PublicKeyCredentialCreationOptions: Codable, DictionaryEncodable {
    public var rp: R5PublicKeyCredentialRpEntity
    public var user: R5PublicKeyCredentialUserEntity
    public var challenge: String
    public var pubKeyCredParams: [R5PublicKeyCredentialParameter]
    public var timeout: Int? = nil
    public var excludeCredentials: [R5PublicKeyCredentialDescriptor]? = nil
    public var authenticatorSelection: R5AuthenticatorSelectionCriteria? = nil
    public var attestation: String
    
    public init(rp: R5PublicKeyCredentialRpEntity, user: R5PublicKeyCredentialUserEntity, challenge: String, pubKeyCredParams: [R5PublicKeyCredentialParameter], timeout: Int?, excludeCredentials: [R5PublicKeyCredentialDescriptor]?, authenticatorSelection: R5AuthenticatorSelectionCriteria?, attestation: String) {
        self.rp = rp
        self.user = user
        self.challenge = challenge
        self.pubKeyCredParams = pubKeyCredParams
        self.timeout = timeout
        self.excludeCredentials = excludeCredentials
        self.authenticatorSelection = authenticatorSelection
        self.attestation = attestation
    }
}
