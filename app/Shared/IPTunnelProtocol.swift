import Foundation

enum IPTunnelFrameType: UInt8 {
    case data = 1
    case keepalive = 2
}

struct IPTunnelFrame {
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
        data[0] = 1
        data[1] = type.rawValue
        data.storeUInt16BE(UInt16(payload.count), at: 2)
        if !payload.isEmpty {
            data.replaceSubrange(Self.headerLength..<(Self.headerLength + payload.count), with: payload)
        }
        return data
    }

    static func decode(from data: Data) throws -> IPTunnelFrame {
        guard data.count >= headerLength else { throw IPTunnelProtocolError.truncated }
        guard data[0] == 1 else { throw IPTunnelProtocolError.badVersion }

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
        }
    }
}

enum IPTunnelProtocolError: Error {
    case truncated
    case badVersion
    case badType
    case packetTooLarge
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
