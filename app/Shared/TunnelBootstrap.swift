import Foundation

/// Payload passed from the app to the packet tunnel extension at connect time.
enum TunnelBootstrap {
    static let hopKey = "hop"

    static func hop(from options: [String: NSObject]?) -> HopNodeProfile? {
        guard let raw = options?[hopKey] else { return nil }
        let data: Data?
        if let d = raw as? Data { data = d }
        else if let d = raw as? NSData { data = d as Data }
        else { data = nil }
        guard let data else { return nil }
        return try? JSONDecoder().decode(HopNodeProfile.self, from: data)
    }

    static func options(hop: HopNodeProfile) -> [String: NSObject] {
        guard let data = try? JSONEncoder().encode(hop) else { return [:] }
        return [hopKey: data as NSData]
    }
}
