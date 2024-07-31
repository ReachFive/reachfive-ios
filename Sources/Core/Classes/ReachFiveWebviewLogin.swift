import Foundation
import BrightFutures
import AuthenticationServices

public extension ReachFive {
    
    func webviewLogin(_ request: WebviewLoginRequest) -> Future<AuthToken, ReachFiveError> {
        
        let promise = Promise<AuthToken, ReachFiveError>()
        
        let pkce = Pkce.generate()
        let scope = (request.scope ?? scope)
        let authURL = buildAuthorizeURL(pkce: pkce, state: request.state, nonce: request.nonce, scope: scope, origin: request.origin, provider: request.provider)
        
        // Initialize the session.
        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: reachFiveApi.sdkConfig.baseScheme) { callbackURL, error in
            if let error {
                let r5Error: ReachFiveError
                switch error._code {
                case 1: r5Error = .AuthCanceled
                case 2: r5Error = .TechnicalError(reason: "Presentation Context Not Provided")
                case 3: r5Error = .TechnicalError(reason: "Presentation Context Invalid")
                default:
                    r5Error = .TechnicalError(reason: "Unknown Error")
                }
                promise.failure(r5Error)
                return
            }
            
            guard let callbackURL else {
                promise.failure(.TechnicalError(reason: "No callback URL"))
                return
            }
            
            let params = URLComponents(url: callbackURL, resolvingAgainstBaseURL: true)?.queryItems
            guard let params, let code = params.first(where: { $0.name == "code" })?.value else {
                promise.failure(.TechnicalError(reason: "No authorization code", apiError: ApiError(fromQueryParams: params)))
                return
            }
            
            promise.completeWith(self.authWithCode(code: code, pkce: pkce))
        }
        
        // Set an appropriate context provider instance that determines the window that acts as a presentation anchor for the session
        session.presentationContextProvider = request.presentationContextProvider
        
        // Start the Authentication Flow
        // if the result of this method is false then the error will already have been processed and the promise failed in the callback
        session.start()
        return promise.future
    }
}
