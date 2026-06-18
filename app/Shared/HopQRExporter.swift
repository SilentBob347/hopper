import Foundation

enum HopQRExporter {
    static func exportJSON(_ profile: HopNodeProfile) -> String {
        var dict: [String: Any] = [
            "v": 2,
            "host": profile.trimmedHost,
            "port": String(profile.port),
            "user": profile.trimmedUser,
            "private_key": profile.privateKey,
        ]

        if !profile.trimmedName.isEmpty {
            dict["name"] = profile.trimmedName
        }
        if !profile.hostKeys.isEmpty {
            dict["host_key"] = profile.hostKeys
        }

        let install = profile.installDir.trimmingCharacters(in: .whitespacesAndNewlines)
        if !install.isEmpty {
            dict["install_dir"] = install
        }

        let data = (try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys, .prettyPrinted]))
            ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
