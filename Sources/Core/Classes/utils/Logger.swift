import Foundation

class Logger {
    static let shared = Logger()
    var isEnabled = false

    private init() {}

    func log(request: URLRequest) {
        guard isEnabled else { return }

        print("➡️ REQUEST: \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")")
        if let body = request.httpBody, let pretty = body.prettyPrintedJSONString {
            print("  BODY: \(pretty)")
        }
    }

    func log(response: HTTPURLResponse, data: Data) {
        guard isEnabled else { return }

        print("⬅️ RESPONSE: \(response.statusCode) \(response.url?.absoluteString ?? "")")
        if let pretty = data.prettyPrintedJSONString {
            print("  BODY: \(pretty)")
        }
    }

    func log(parsedResponse: Any) {
        guard isEnabled else { return }
        print("✅ PARSED: \(parsedResponse)")
    }

    func log(error: Error) {
        guard isEnabled else { return }
        let message = switch error {
        case let rfe as ReachFiveError:
            rfe.description
        default:
            error.localizedDescription
        }
        print("❌ ERROR: \(message)")
    }
}

extension Data {
    var prettyPrintedJSONString: NSString? { /// NSString gives us a nice sanitized debugDescription
        guard let object = try? JSONSerialization.jsonObject(with: self, options: []),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
              let prettyPrintedString = NSString(data: data, encoding: String.Encoding.utf8.rawValue)
        else { return nil }

        return prettyPrintedString
    }
}

