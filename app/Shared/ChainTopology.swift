import Foundation

enum ChainTopology {
    static func chainOctet(chainID: UUID) -> Int {
        let hex = chainID.uuidString.replacingOccurrences(of: "-", with: "")
        var hash: UInt32 = 2_166_136_261
        for byte in hex.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return 1 + Int(hash % 254)
    }

    static func overlayCIDR(chainID: UUID) -> String {
        "10.64.\(chainOctet(chainID: chainID)).0/24"
    }

    static func overlaySubnet(chainID: UUID) -> String {
        "10.64.\(chainOctet(chainID: chainID)).0"
    }

    static func overlayMask() -> String {
        "255.255.255.0"
    }

    static func listenPort(chainID: UUID) -> Int {
        7400 + chainOctet(chainID: chainID)
    }

    static func overlayAddr(chainID: UUID, index: Int) -> String {
        "10.64.\(chainOctet(chainID: chainID)).\(HopConstants.overlayNodeOctet + index)"
    }
}

struct TunnelConnectContext: Codable, Equatable {
    let chainID: UUID
    let hopperPort: Int
    let overlayCIDR: String
    let deviceID: UUID
}
