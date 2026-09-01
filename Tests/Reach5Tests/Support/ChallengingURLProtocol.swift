import Foundation

/// A `URLProtocol` that raises a server-trust challenge before answering, so the challenge travels the way a
/// real one does — up to the session delegate — instead of the delegate method being called directly.
final class ChallengingURLProtocol: URLProtocol {
    /// What the session delegate answered, recorded by the challenge's sender.
    enum Outcome: Equatable {
        case usedCredential
        case continuedWithoutCredential
        case cancelled
        case performedDefaultHandling
    }

    /// Set by the sender when the delegate answers, read by the test once the request is over.
    static let outcomes = OutcomeBox()

    final class OutcomeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Outcome?

        func record(_ outcome: Outcome) {
            lock.lock(); defer { lock.unlock() }
            value = outcome
        }

        var recorded: Outcome? {
            lock.lock(); defer { lock.unlock() }
            return value
        }

        func reset() {
            lock.lock(); defer { lock.unlock() }
            value = nil
        }
    }

    static func makeSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ChallengingURLProtocol.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let space = URLProtectionSpace(
            host: request.url?.host ?? "example.com",
            port: 443,
            protocol: "https",
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodServerTrust
        )
        let sender = Sender(protocolInstance: self)
        client?.urlProtocol(self, didReceive: URLAuthenticationChallenge(
            protectionSpace: space,
            proposedCredential: nil,
            previousFailureCount: 0,
            failureResponse: nil,
            error: nil,
            sender: sender
        ))
    }

    override func stopLoading() {}

    /// Answers a 200 once the challenge is settled, so the request completes and the test can assert.
    fileprivate func finishAfterChallenge() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    fileprivate func failAfterChallenge() {
        client?.urlProtocol(self, didFailWithError: URLError(.serverCertificateUntrusted))
    }

    /// Receives what the session delegate answered to the challenge. `URLSession` routes the disposition here
    /// rather than back to the `URLProtocol`, which is what makes the whole path observable.
    private final class Sender: NSObject, URLAuthenticationChallengeSender {
        private let protocolInstance: ChallengingURLProtocol

        init(protocolInstance: ChallengingURLProtocol) {
            self.protocolInstance = protocolInstance
        }

        func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {
            ChallengingURLProtocol.outcomes.record(.usedCredential)
            protocolInstance.finishAfterChallenge()
        }

        func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {
            ChallengingURLProtocol.outcomes.record(.continuedWithoutCredential)
            protocolInstance.finishAfterChallenge()
        }

        func cancel(_ challenge: URLAuthenticationChallenge) {
            ChallengingURLProtocol.outcomes.record(.cancelled)
            protocolInstance.failAfterChallenge()
        }

        func performDefaultHandling(for challenge: URLAuthenticationChallenge) {
            ChallengingURLProtocol.outcomes.record(.performedDefaultHandling)
            protocolInstance.finishAfterChallenge()
        }

        func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {
            protocolInstance.finishAfterChallenge()
        }
    }
}
