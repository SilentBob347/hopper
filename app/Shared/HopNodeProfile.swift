import Foundation

struct HopNodeProfile: Codable, Equatable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var host: String = ""
    var port: Int = HopConstants.defaultSSHPort
    var user: String = ""
    var privateKey: String = ""
    var hostKeys: [String] = []
    /// Server bundle path from QR v2 (`install_dir`), e.g. `~/hopper`.
    var installDir: String = ""
    /// Hopper server bundle version from deploy/QR v2 (`server_version`).
    var serverVersion: String = ""
    /// Minimum app version required by the server (`min_app_version`).
    var minAppVersion: String = ""

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedUser: String {
        user.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var displayName: String {
        if !trimmedName.isEmpty { return trimmedName }
        if !trimmedHost.isEmpty { return trimmedHost }
        return "Untitled"
    }

}
