import Foundation

struct HopChain: Codable, Equatable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    /// Ordered server IDs: first = entry, last = exit.
    var hopIDs: [UUID] = []

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var displayName: String {
        let trimmed = trimmedName
        return trimmed.isEmpty ? "Untitled chain" : trimmed
    }
}
