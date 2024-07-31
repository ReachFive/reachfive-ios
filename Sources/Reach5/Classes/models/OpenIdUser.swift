import Foundation

public class OpenIdUser: Codable {
    public let id: String?
    public let name: String?
    public let preferredUsername: String?
    public let givenName: String?
    public let familyName: String?
    public let middleName: String?
    public let nickname: String?
    public let picture: String?
    public let website: String?
    public let email: String?
    public let emailVerified: Bool?
    public let gender: String?
    public let zoneinfo: String?
    public let locale: String?
    public let phoneNumber: String?
    public let phoneNumberVerified: Bool?
    public let address: ProfileAddress?
    
    public init(
        id: String?,
        name: String?,
        preferredUsername: String?,
        givenName: String?,
        familyName: String?,
        middleName: String?,
        nickname: String?,
        picture: String?,
        website: String?,
        email: String?,
        emailVerified: Bool?,
        gender: String?,
        zoneinfo: String?,
        locale: String?,
        phoneNumber: String?,
        phoneNumberVerified: Bool?,
        address: ProfileAddress?
    ) {
        self.id = id
        self.name = name
        self.preferredUsername = preferredUsername
        self.givenName = givenName
        self.familyName = familyName
        self.middleName = middleName
        self.nickname = nickname
        self.picture = picture
        self.website = website
        self.email = email
        self.emailVerified = emailVerified
        self.gender = gender
        self.zoneinfo = zoneinfo
        self.locale = locale
        self.phoneNumber = phoneNumber
        self.phoneNumberVerified = phoneNumberVerified
        self.address = address
    }
}

extension OpenIdUser {
    struct CodingData: Codable {
        var sub: String?
        var name: String?
        var preferredUsername: String?
        var givenName: String?
        var familyName: String?
        var middleName: String?
        var nickname: String?
        var picture: String?
        var website: String?
        var email: String?
        var emailVerified: Bool?
        var gender: String?
        var zoneinfo: String?
        var locale: String?
        var phoneNumber: String?
        var phoneNumberVerified: Bool?
        var address: ProfileAddress?
    }
}

extension OpenIdUser.CodingData {
    var openIdUser: OpenIdUser {
        OpenIdUser.init(
            id: sub,
            name: name,
            preferredUsername: preferredUsername,
            givenName: givenName,
            familyName: familyName,
            middleName: middleName,
            nickname: nickname,
            picture: picture,
            website: website,
            email: email,
            emailVerified: emailVerified,
            gender: gender,
            zoneinfo: zoneinfo,
            locale: locale,
            phoneNumber: phoneNumber,
            phoneNumberVerified: phoneNumberVerified,
            address: address
        )
    }
}
