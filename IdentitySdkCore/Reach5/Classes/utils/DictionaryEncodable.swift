import Foundation

protocol DictionaryEncodable: Encodable {}

extension DictionaryEncodable {
    func dictionary() -> [String: Any]? {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let json = try? encoder.encode(self),
              let dict = try? JSONSerialization.jsonObject(with: json, options: []) as? [String: Any]
        else {
            return nil
        }
        return dict
    }
}
