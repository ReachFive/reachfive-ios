import Foundation
import Reach5

/// Reproduces, in the Sandbox, what an SSL-pinning layer does to the SDK's network calls.
///
/// The point is not the trust evaluation — no certificate is involved here — but the shape of the
/// interception: what such a layer answers when `/oauth/authorize` redirects to the app's custom scheme,
/// which is the one call whose result the SDK reads from a redirection rather than from a response.
///
/// Every strategy but ``refuseCertificate`` goes through the same detour a real integrator takes: swizzling
/// `URLSessionConfiguration.default` to slip a `URLProtocol` into the SDK's private sessions.
/// ``refuseCertificate`` goes through `SdkInternalConfig.authenticationChallengeHandler` instead — the
/// supported hook, which exists precisely so that detour is no longer needed.
enum NetworkInterceptionStrategy: String, CaseIterable {
    /// No interception at all: the reference.
    case none

    /// A layer that hands the redirection over — what a correctly written one does. The SDK intercepts as
    /// usual and the login goes through.
    case relayRedirection

    /// Refuses the redirection and forwards nothing, the way a rule that says "leave the ReachFive callback
    /// alone" ends up doing. The SDK's task then completes with no redirection, no response and no error.
    case refuseSilently

    /// Refuses the redirection but lets its response through, so the task ends on the 3xx and its `Location`
    /// header. The SDK reads the callback there.
    case refuseAndReturnRedirectResponse

    /// Lets `URLSession` follow the redirection without telling anyone. Loading a custom scheme fails with
    /// `unsupportedURL`, and the SDK reads the callback in the URL that failed.
    case followRedirection

    /// Sends the redirection to a block page of its own, the way a corporate proxy does. Nothing to recover:
    /// the SDK can only report where the redirection actually leads.
    case rewriteToBlockPage

    /// The pinning doing its job and refusing the certificate, through the SDK's supported hook. Every call
    /// fails, `/oauth/authorize` included.
    case refuseCertificate

    var label: String {
        switch self {
        case .none: "No interception"
        case .relayRedirection: "Relays the redirection"
        case .refuseSilently: "Refuses it, forwards nothing"
        case .refuseAndReturnRedirectResponse: "Refuses it, returns the 303"
        case .followRedirection: "Lets it be followed"
        case .rewriteToBlockPage: "Sends it to a block page"
        case .refuseCertificate: "Refuses the certificate"
        }
    }

    var summary: String {
        switch self {
        case .none: "Reference behaviour"
        case .relayRedirection: "Login works"
        case .refuseSilently: "Nothing left to the SDK"
        case .refuseAndReturnRedirectResponse: "Callback read from Location"
        case .followRedirection: "Callback read from unsupportedURL"
        case .rewriteToBlockPage: "Reports where it leads"
        case .refuseCertificate: "Through the supported hook"
        }
    }
}

enum NetworkInterception {
    static let defaultsKey = "networkInterceptionStrategy"

    /// Read once, when the first `ReachFive` is built. Changing it in the settings takes effect at the next
    /// launch: the swizzle has to be in place before the SDK asks for its `URLSessionConfiguration`, and the
    /// `ReachFive` instance keeps the sessions it built.
    static var strategy: NetworkInterceptionStrategy {
        get {
            UserDefaults.standard.string(forKey: defaultsKey)
                .flatMap(NetworkInterceptionStrategy.init(rawValue:)) ?? .none
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    /// The handler the Sandbox passes to `SdkInternalConfig`, `nil` unless the certificate is being refused.
    /// This is the whole of what an app should need to pin: no swizzling, and no way to reach the redirection.
    static var authenticationChallengeHandler: AuthenticationChallengeHandler? {
        guard strategy == .refuseCertificate else { return nil }
        return { _ in (.cancelAuthenticationChallenge, nil) }
    }

    /// Must run **before** the first `ReachFive` is built, since the SDK reads
    /// `URLSessionConfiguration.default` when it creates its sessions.
    /// Called every time a `ReachFive` instance is built, which an environment switch does again — hence the
    /// flag: `method_exchangeImplementations` swaps back on a second call, so it would uninstall itself.
    private static var installed = false

    static func installIfNeeded() {
        let strategy = strategy
        guard !installed, strategy != .none, strategy != .refuseCertificate else { return }

        print("ℹ️ Network interception installed: \(strategy.label)")

        // The detour a real integrator takes, reproduced as-is: exchange the implementation of
        // `+[NSURLSessionConfiguration defaultSessionConfiguration]` so every configuration the SDK asks for
        // comes back carrying our `URLProtocol`.
        guard let original = class_getClassMethod(URLSessionConfiguration.self, NSSelectorFromString("defaultSessionConfiguration")),
              let replacement = class_getClassMethod(URLSessionConfiguration.self, #selector(URLSessionConfiguration.interceptedDefaultSessionConfiguration))
        else {
            print("⚠️ Could not install the network interception")
            return
        }
        method_exchangeImplementations(original, replacement)
        installed = true
    }
}

extension URLSessionConfiguration {
    @objc class func interceptedDefaultSessionConfiguration() -> URLSessionConfiguration {
        // Not a recursion: the implementations are exchanged, so this call reaches the original.
        let configuration = interceptedDefaultSessionConfiguration()
        configuration.protocolClasses = [InterceptingURLProtocol.self] + (configuration.protocolClasses ?? [])
        return configuration
    }
}

/// Replays the request through a session of its own and answers its redirections according to the selected
/// ``NetworkInterceptionStrategy`` — the very shape a pinning layer takes when it needs to evaluate the
/// server's trust itself.
final class InterceptingURLProtocol: URLProtocol {
    private var innerTask: URLSessionTask?
    private var refusedRedirectResponse: HTTPURLResponse?
    private var relayedRedirection = false

    /// Ephemeral, so it is untouched by the swizzle above and cannot recurse into this protocol. The cookie
    /// storage is shared all the same: dropping the SDK's session cookies would break flows that have nothing
    /// to do with what is being demonstrated.
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme?.lowercased().hasPrefix("http") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // Names every request the interception got hold of: the only way to see, from a running app, that a
        // swizzle installed outside the SDK really reaches the sessions the SDK keeps private.
        print("ℹ️ [interception] intercepted \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")")
        innerTask = session.dataTask(with: request)
        innerTask?.resume()
    }

    override func stopLoading() {
        innerTask?.cancel()
    }
}

extension InterceptingURLProtocol: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Only the callback is at stake. A redirection between web pages is relayed whatever the strategy.
        guard let scheme = request.url?.scheme?.lowercased(), scheme != "http", scheme != "https" else {
            client?.urlProtocol(self, wasRedirectedTo: request, redirectResponse: response)
            completionHandler(request)
            return
        }

        print("ℹ️ [interception] redirection to \(request.url?.scheme ?? "?"):// — \(NetworkInterception.strategy.label)")

        switch NetworkInterception.strategy {
        case .relayRedirection:
            relayedRedirection = true
            client?.urlProtocol(self, wasRedirectedTo: request, redirectResponse: response)
            completionHandler(request)

        case .refuseSilently:
            completionHandler(nil)

        case .refuseAndReturnRedirectResponse:
            refusedRedirectResponse = response
            completionHandler(nil)

        case .followRedirection:
            completionHandler(request)

        case .rewriteToBlockPage:
            refusedRedirectResponse = HTTPURLResponse(
                url: response.url ?? request.url!,
                statusCode: 303,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": "https://blocked.example.com/ssl-pinning"]
            )
            completionHandler(nil)

        case .none, .refuseCertificate:
            completionHandler(request)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        client?.urlProtocol(self, didLoad: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // A refused redirection whose response is handed over all the same: the `Location` header travels with
        // it, which is what the SDK reads the callback from.
        if let refusedRedirectResponse {
            client?.urlProtocol(self, didReceive: refusedRedirectResponse, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        // The redirection was already handed over; whatever the inner session made of it afterwards is not the
        // caller's business.
        if relayedRedirection {
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        if let error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            // Nothing was ever delivered when the redirection was refused silently: that is the point of the
            // strategy, and what the SDK's task then sees.
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}
