import Foundation

/// Service Provider Interface for internal or debugging purposes.
///
/// This protocol should not be implemented by external clients directly.
public protocol ReachFiveSpi {
    var isLoggingEnabled: Bool { get }
}

/// Default internal implementation of the ReachFiveSpi.
public struct DefaultReachFiveSpi: ReachFiveSpi {
    public let isLoggingEnabled: Bool
    
    public init(isLoggingEnabled: Bool = false) {
        self.isLoggingEnabled = isLoggingEnabled
    }
}
