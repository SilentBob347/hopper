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
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ParseError.emptyPayload }

        guard let data = trimmed.data(using: .utf8) else {
            throw ParseError.invalidJSON
        }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let json = object as? [String: Any] else {
            throw ParseError.invalidJSON
        }

        let host = stringValue(in: json, keys: ["host", "server"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !host.isEmpty else { throw ParseError.missingHost }

        let user = stringValue(in: json, keys: ["user", "username"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !user.isEmpty else { throw ParseError.missingUser }

        let privateKey = stringValue(in: json, keys: ["private_key", "privateKey"]) ?? ""
        guard !privateKey.isEmpty else { throw ParseError.missingPrivateKey }

        let portString = stringValue(in: json, keys: ["port"]) ?? String(HopConstants.defaultSSHPort)
        let port = Int(portString) ?? HopConstants.defaultSSHPort

        var hostKeys: [String] = []
        if let keys = json["host_key"] as? [String] {
            hostKeys = keys
        } else if let single = json["host_key"] as? String {
            hostKeys = [single]
        } else if let keys = json["hostKeys"] as? [String] {
            hostKeys = keys
        }

        let installDir = stringValue(in: json, keys: ["install_dir", "installDir", "hopper_dir"]) ?? ""

        return HopNodeProfile(
            name: stringValue(in: json, keys: ["name", "title", "remarks"]) ?? "",
            host: host,
            port: port,
            user: user,
            privateKey: privateKey,
            hostKeys: hostKeys,
            installDir: installDir
        )
    }

    private static func stringValue(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = dictionary.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value else {
                continue
            }
            if let string = value as? String { return string }
            if let number = value as? NSNumber { return number.stringValue }
        }
        return nil
    }
}
