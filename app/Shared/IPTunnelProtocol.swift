import Foundation

enum IPTunnelFrameType: UInt8 {
    case data = 1
    case keepalive = 2
    case assignReq = 3
    case assignResp = 4
}

struct IPTunnelFrame {
    static let wireVersion: UInt8 = 2
    static let headerLength = 4
    static let maxPacketLength = 65_535

    var type: IPTunnelFrameType
    var payload: Data

    init(type: IPTunnelFrameType, payload: Data = Data()) {
        self.type = type
        self.payload = payload
    }

    func encoded() -> Data {
        var data = Data(count: Self.headerLength + payload.count)
        data[0] = Self.wireVersion
        data[1] = type.rawValue
        data.storeUInt16BE(UInt16(payload.count), at: 2)
        if !payload.isEmpty {
            data.replaceSubrange(Self.headerLength..<(Self.headerLength + payload.count), with: payload)
        }
        return data
    }

    static func decode(from data: Data) throws -> IPTunnelFrame {
        guard data.count >= headerLength else { throw IPTunnelProtocolError.truncated }
        guard data[0] == wireVersion else { throw IPTunnelProtocolError.badVersion }

        guard let type = IPTunnelFrameType(rawValue: data[1]) else {
            throw IPTunnelProtocolError.badType
        }

        let payloadLength = Int(data.uint16BE(at: 2))
        guard payloadLength <= maxPacketLength else { throw IPTunnelProtocolError.packetTooLarge }

        switch type {
        case .data:
            guard payloadLength > 0, data.count >= headerLength + payloadLength else {
                throw IPTunnelProtocolError.truncated
            }
            let payload = data.subdata(in: headerLength..<(headerLength + payloadLength))
            return IPTunnelFrame(type: type, payload: payload)
        case .keepalive:
            guard payloadLength == 0 else { throw IPTunnelProtocolError.truncated }
            return IPTunnelFrame(type: type)
        case .assignReq, .assignResp:
            guard data.count >= headerLength + payloadLength else {
                throw IPTunnelProtocolError.truncated
            }
            let payload = payloadLength > 0
                ? data.subdata(in: headerLength..<(headerLength + payloadLength))
                : Data()
            return IPTunnelFrame(type: type, payload: payload)
        }
    }
}

struct AssignRequest: Codable {
    let deviceID: String
    let chainID: String

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case chainID = "chain_id"
    }
}

struct AssignResponse: Codable {
    let addr: String?
    let leaseTTL: Int?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case addr, error
        case leaseTTL = "lease_ttl"
    }
}

enum IPTunnelProtocolError: Error, LocalizedError {
    case truncated
    case badVersion
    case badType
    case packetTooLarge
    case assignFailed(String)

    var errorDescription: String? {
        switch self {
        case .truncated:
            return "IPTunnel frame truncated — the hopper stream closed or sent a partial packet."
        case .badVersion:
            return """
            IPTunnel protocol mismatch (expected v2). hopperd on the entry server may be outdated or the wrong process is listening on the chain port. \
            Try Connect with “restart hopperd”, or on the server run: hopperctl start --chain-id … (after hopper update).
            """
        case .badType:
            return "IPTunnel frame had an unknown type — hopperd may be outdated."
        case .packetTooLarge:
            return "IPTunnel packet exceeds maximum size."
        case .assignFailed(let detail):
            return "Overlay address assignment failed: \(detail)"
        }
    }
}

extension Data {
    func uint16BE(at offset: Int) -> UInt16 {
        UInt16(self[offset]) << 8 | UInt16(self[offset + 1])
    }

    mutating func storeUInt16BE(_ value: UInt16, at offset: Int) {
        self[offset] = UInt8((value >> 8) & 0xFF)
        self[offset + 1] = UInt8(value & 0xFF)
    }
}
