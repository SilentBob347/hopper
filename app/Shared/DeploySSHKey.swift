import Foundation

struct DeploySSHKey: Codable, Equatable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var privateKey: String = ""
    var createdAt: Date = Date()
}
