import Foundation

enum HopQRParser {
    enum ParseError: LocalizedError {
        case emptyPayload
        case invalidJSON
        case missingHost
        case missingUser
        case missingPrivateKey

        var errorDescription: String? {
            switch self {
            case .emptyPayload: return "The QR code is empty."
            case .invalidJSON: return "The QR code contains invalid JSON."
            case .missingHost: return "The hop config is missing a host."
            case .missingUser: return "The hop config is missing a user."
            case .missingPrivateKey: return "The hop config is missing a private key."
            }
        }
    }

    static func parse(_ payload: String) throws -> HopNodeProfile {
        try HopProfileCodec.parse(payload)
    }
}
