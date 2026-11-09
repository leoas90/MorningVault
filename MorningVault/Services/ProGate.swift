import Foundation

/// Which features are Pro. Until StoreKit lands this is a build flag: on for Debug and
/// TestFlight (sandbox receipt) so the gated UI can be exercised, off for App Store builds.
/// Later this reads `Transaction.currentEntitlements`.
enum ProGate {
    static var isUnlocked: Bool {
        #if DEBUG
        return true
        #else
        return isTestFlight
        #endif
    }

    /// TestFlight installs carry a sandbox receipt.
    static var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }
}
