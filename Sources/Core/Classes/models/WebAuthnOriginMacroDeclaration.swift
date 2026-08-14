import Foundation

/// A WebAuthn origin checked when your app compiles, instead of when it launches.
///
/// ```swift
/// SdkConfig(domain: "example.reach5.net", clientId: "…",
///           originWebAuthn: #WebAuthnOrigin("https://auth.example.com"))
/// ```
///
/// The literal must already be a serialized origin — a scheme, a host, and a port only when it is not the
/// scheme's default. A path, a trailing slash, an uppercase host or `:443` are errors with a fix-it, because
/// the SDK would drop them when it sends the origin, leaving your configuration and what the server receives
/// silently different.
///
/// Only for an origin you write in your source. One read from a plist or a remote configuration goes to
/// ``SdkConfig/init(domain:clientId:customScheme:redirectUri:mfaUri:accountRecoveryUri:emailVerificationUri:originWebAuthn:)``
/// as a plain `URL`, which validates it the same way at init.
@freestanding(expression)
public macro WebAuthnOrigin(_ origin: StaticString) -> URL =
    #externalMacro(module: "Reach5Macros", type: "WebAuthnOriginMacro")
