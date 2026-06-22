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

/// Wire-format codec for hopper node profile v2 (server configure / QR / export).
enum HopProfileCodec {
    static let profileVersion = 2

    enum Field {
        static let version = "v"
        static let name = "name"
        static let host = "host"
        static let port = "port"
        static let user = "user"
        static let privateKey = "private_key"
        static let installDir = "install_dir"
        static let serverVersion = "server_version"
        static let minAppVersion = "min_app_version"
        static let hostKey = "host_key"
    }

    static let unknownVersion = "unknown"

    static func exportDictionary(_ profile: HopNodeProfile) -> [String: Any] {
        var dict: [String: Any] = [
            Field.version: profileVersion,
            Field.name: exportName(profile),
            Field.host: profile.trimmedHost,
            Field.port: String(profile.port),
            Field.user: profile.trimmedUser,
            Field.privateKey: profile.privateKey,
            Field.installDir: profile.resolvedInstallDir,
            Field.serverVersion: profile.serverVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? unknownVersion : profile.serverVersion.trimmingCharacters(in: .whitespacesAndNewlines),
            Field.minAppVersion: profile.minAppVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? unknownVersion : profile.minAppVersion.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
        if !profile.hostKeys.isEmpty {
            dict[Field.hostKey] = profile.hostKeys
        }
        return dict
    }

    static func parse(_ payload: String) throws -> HopNodeProfile {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HopQRParser.ParseError.emptyPayload }

        guard let data = trimmed.data(using: .utf8) else {
            throw HopQRParser.ParseError.invalidJSON
        }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let json = object as? [String: Any] else {
            throw HopQRParser.ParseError.invalidJSON
        }

        if let version = intValue(in: json, keys: [Field.version]), version != profileVersion {
            throw HopQRParser.ParseError.invalidJSON
        }

        let host = stringValue(in: json, keys: [Field.host, "server"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !host.isEmpty else { throw HopQRParser.ParseError.missingHost }

        let user = stringValue(in: json, keys: [Field.user, "username"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !user.isEmpty else { throw HopQRParser.ParseError.missingUser }

        let privateKey = stringValue(in: json, keys: [Field.privateKey, "privateKey"]) ?? ""
        guard !privateKey.isEmpty else { throw HopQRParser.ParseError.missingPrivateKey }

        let portString = stringValue(in: json, keys: [Field.port]) ?? String(HopConstants.defaultSSHPort)
        let port = Int(portString) ?? HopConstants.defaultSSHPort

        return HopNodeProfile(
            name: stringValue(in: json, keys: [Field.name, "title", "remarks"]) ?? "",
            host: host,
            port: port,
            user: user,
            privateKey: privateKey,
            hostKeys: parseHostKeys(json),
            installDir: stringValue(in: json, keys: [Field.installDir, "installDir", "hopper_dir"]) ?? "",
            serverVersion: stringValue(in: json, keys: [Field.serverVersion, "serverVersion"]) ?? "",
            minAppVersion: stringValue(in: json, keys: [Field.minAppVersion, "minAppVersion"]) ?? ""
        )
    }

    private static func exportName(_ profile: HopNodeProfile) -> String {
        if !profile.trimmedName.isEmpty { return profile.trimmedName }
        if !profile.trimmedHost.isEmpty { return profile.trimmedHost }
        return "Untitled"
    }

    private static func parseHostKeys(_ json: [String: Any]) -> [String] {
        if let keys = json[Field.hostKey] as? [String] {
            return keys
        }
        if let single = json[Field.hostKey] as? String, !single.isEmpty {
            return [single]
        }
        if let keys = json["hostKeys"] as? [String] {
            return keys
        }
        return []
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

    private static func intValue(in dictionary: [String: Any], keys: [String]) -> Int? {
        guard let raw = stringValue(in: dictionary, keys: keys) else { return nil }
        return Int(raw)
    }
}

private extension HopNodeProfile {
    var resolvedInstallDir: String {
        let trimmed = installDir.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? HopConstants.defaultInstallDir : trimmed
    }
}
