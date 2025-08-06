import Foundation

// Declare a protocol to make possible the use of the type constraint below in KeyedEncodingContainer, because one cannot do a type constraint with enum
public protocol Diffable {
    func isEmpty() -> Bool
}

public enum Diff<Wrapped>: Diffable {
    case Update(Wrapped)
    case Delete
    case NoOp

    public func isEmpty() -> Bool {
        switch self {
        case .Update(_):
            false
        case .Delete:
            false
        case .NoOp:
            true
        }
    }

    public var value: Wrapped? {
        switch self {
        case .Update(let value):
            return value
        default:
            return nil
        }
    }

    public init(_ optional: Wrapped?) {
        switch optional {
        case .some(let value): self = .Update(value)
        case .none: self = .NoOp
        }
    }
}

extension Diff: Encodable where Wrapped: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .Update(value):
            try container.encode(value)
        case .Delete:
            try container.encodeNil() // will produce a json null
        case .NoOp:
            break // should not be called thanks to KeyedEncodingContainer skipping NoOp
        }
    }
}

extension KeyedEncodingContainer {
    public mutating func encode<T: Diffable>(_ value: T, forKey key: KeyedEncodingContainer<K>.Key) throws where T : Encodable {

        // Encode a NoOp field the same way a nil would be encoded, that is not be encoded at all.
        guard !value.isEmpty() else {
            return
        }
        // Don't know how to get access to the encoder for Diff, so just use another encode method from KeyedEncodingContainer that I haven't overridden
        try self.encodeIfPresent(value, forKey: key)
    }
}

public class ProfileUpdate: DictionaryEncodable {
    public var givenName: Diff<String>
    public var middleName: Diff<String>
    public var familyName: Diff<String>
    public var name: Diff<String>
    public var nickname: Diff<String>
    public var birthdate: Diff<String>
    public var picture: Diff<String>
    public var username: Diff<String>
    public var gender: Diff<String>
    public var email: Diff<String>
    public var phoneNumber: Diff<String>
    public var customIdentifier: Diff<String>
    public var locale: Diff<String>
    public var company: Diff<String>

    public init(
        givenName: Diff<String> = .NoOp,
        middleName: Diff<String> = .NoOp,
        familyName: Diff<String> = .NoOp,
        name: Diff<String> = .NoOp,
        nickname: Diff<String> = .NoOp,
        birthdate: Diff<String> = .NoOp,
        picture: Diff<String> = .NoOp,
        username: Diff<String> = .NoOp,
        gender: Diff<String> = .NoOp,
        email: Diff<String> = .NoOp,
        phoneNumber: Diff<String> = .NoOp,
        customIdentifier: Diff<String> = .NoOp,
        locale: Diff<String> = .NoOp,
        company: Diff<String> = .NoOp
    ) {
        self.givenName = givenName
        self.middleName = middleName
        self.familyName = familyName
        self.name = name
        self.nickname = nickname
        self.birthdate = birthdate
        self.picture = picture
        self.username = username
        self.gender = gender
        self.email = email
        self.phoneNumber = phoneNumber
        self.customIdentifier = customIdentifier
        self.locale = locale
        self.company = company
    }
}
