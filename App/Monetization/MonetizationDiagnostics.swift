import Foundation
import os

/// Build-environment detection used to decide how much monetization diagnostic
/// detail is safe to expose. TestFlight and Apple Sandbox builds are receipt-tagged
/// `sandboxReceipt`; App Store builds are not.
enum MonetizationBuild {
    static let isDebug: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    /// True for DEBUG, Apple Sandbox and TestFlight builds. False for App Store builds.
    static let isSandbox: Bool = {
        if isDebug { return true }
        guard let receiptURL = Bundle.main.appStoreReceiptURL else { return false }
        return receiptURL.lastPathComponent == "sandboxReceipt"
    }()
}

/// Monetization logging. Unlike `print`, this reaches Console.app and `sysdiagnose`
/// for TestFlight builds, where paywall configuration problems actually surface.
enum MonetizationLog {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.balthasardeweert.earnyourscreentime",
        category: "Monetization"
    )

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
