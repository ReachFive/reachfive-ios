import Foundation
import Reach5

class PasskeyAutoFillController: UIViewController {

    /// How long the modal request below is left on screen before its caller's task is canceled.
    private static let delayBeforeCancel: UInt64 = 3_000_000_000

    /// The task running the auto-fill request, kept so that ``cancelOngoingRequest(_:)`` can cancel it:
    /// UIKit never cancels a `Task` on its own, neither on dismiss nor on deinit, so without this handle
    /// the SDK's caller-cancellation path is unreachable from the app.
    private var autoFillTask: Task<Void, Never>?

    #if !targetEnvironment(macCatalyst)
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            print("PasskeyAutoFillController.viewDidAppear")

            if #available(iOS 16.0, *) {
                autoFillTask = Task {
                    guard let window = view.window else { fatalError("The view was not in the app's view hierarchy!") }
                    await handleAuthToken {
                        try await AppDelegate.reachfive().beginAutoFillAssistedPasskeyLogin(withRequest: NativeLoginRequest(anchor: window, origin: "PasskeyAutoFillController.viewDidAppear"))
                    }
                }
            }
        }
    #endif

    /// Cancels the caller's task while the auto-fill request is under way. Only the QuickType bar is on
    /// screen at that point, so a button is enough to reach this.
    ///
    /// Expected outcome: an alert reporting the technical error "The calling task was canceled" — the SDK
    /// deliberately does not report `.AuthCanceled` here, which apps answer by restarting an auto-fill
    /// request.
    @IBAction func cancelOngoingRequest(_ sender: Any) {
        print("PasskeyAutoFillController.cancelOngoingRequest: task \(autoFillTask == nil ? "absent" : "present")")
        autoFillTask?.cancel()
    }

    /// Starts a modal passkey request and cancels its caller's task after ``delayBeforeCancel``.
    ///
    /// The delay is what makes this observable: the system sheet covers the whole screen, so no button of
    /// ours could be tapped while the request is under way. `.Always` guarantees a sheet appears — it falls
    /// back to a QR code when no passkey is available locally.
    ///
    /// What to watch: whether the system sheet dismisses itself when the task is canceled, and whether the
    /// alert reports "The calling task was canceled".
    @IBAction func modalLoginThenCancel(_ sender: Any) {
        guard #available(iOS 16.0, *) else {
            presentAlert(title: "Modal login", message: "Passkey requires iOS 16")
            return
        }
        guard let window = view.window else { fatalError("The view was not in the app's view hierarchy!") }

        // The auto-fill request started on appear is left alone: submitting this one makes the SDK cancel it
        // with `.AuthCanceled`, which `presentErrorAlert` filters out. Canceling its task here instead would
        // raise the very same "calling task was canceled" alert and there would be no telling the two apart.
        let login = Task {
            await handleLoginFlow {
                try await AppDelegate.reachfive().login(
                    withRequest: NativeLoginRequest(anchor: window, origin: "PasskeyAutoFillController.modalLoginThenCancel"),
                    usingModalAuthorizationFor: [.Passkey],
                    display: .Always
                )
            }
        }

        Task {
            try? await Task.sleep(nanoseconds: Self.delayBeforeCancel)
            print("PasskeyAutoFillController.modalLoginThenCancel: canceling the caller's task")
            login.cancel()
        }
    }
}
