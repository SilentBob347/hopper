import Foundation
import os

enum TunnelLog {
    private static let logger = Logger(subsystem: HopConstants.mainBundleID, category: "Tunnel")
    private static let prefix = "ɹǝddoH"

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        NSLog("[\(prefix)] %@", message)
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        NSLog("[\(prefix) ERROR] %@", message)
    }
}
