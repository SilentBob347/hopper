import Foundation

/// Payload passed from the app to the packet tunnel extension at connect time.
enum TunnelBootstrap {
    static let hopKey = "hop"
    static let contextKey = "context"

    static func hop(from options: [String: NSObject]?) -> HopNodeProfile? {
        guard let raw = options?[hopKey] else { return nil }
        let data: Data?
        if let d = raw as? Data { data = d }
        else if let d = raw as? NSData { data = d as Data }
        else { data = nil }
        guard let data else { return nil }
        return try? JSONDecoder().decode(HopNodeProfile.self, from: data)
    }

    static func context(from options: [String: NSObject]?) -> TunnelConnectContext? {
        guard let raw = options?[contextKey] else { return nil }
        let data: Data?
        if let d = raw as? Data { data = d }
        else if let d = raw as? NSData { data = d as Data }
        else { data = nil }
        guard let data else { return nil }
        return try? JSONDecoder().decode(TunnelConnectContext.self, from: data)
    }

    static func options(hop: HopNodeProfile, context: TunnelConnectContext) -> [String: NSObject] {
        var result: [String: NSObject] = [:]
        if let hopData = try? JSONEncoder().encode(hop) {
            result[hopKey] = hopData as NSData
        }
        if let ctxData = try? JSONEncoder().encode(context) {
            result[contextKey] = ctxData as NSData
        }
        return result
    }
}
