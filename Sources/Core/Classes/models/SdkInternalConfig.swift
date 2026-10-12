import Foundation

public class SdkInternalConfig {
    public let loggingEnabled: Bool
    /// The configuration of the SDK's `URLSession`. Internal: lets tests route requests to a fake backend.
    let sessionConfiguration: URLSessionConfiguration

    public convenience init(loggingEnabled: Bool = false) {
        self.init(loggingEnabled: loggingEnabled, sessionConfiguration: .default)
    }

    init(loggingEnabled: Bool, sessionConfiguration: URLSessionConfiguration) {
        self.loggingEnabled = loggingEnabled
        self.sessionConfiguration = sessionConfiguration
    }
}
