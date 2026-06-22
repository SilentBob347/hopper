import Foundation
import NetworkExtension

struct TunnelPrepareResult {
    let excludedRoutes: [String]
    let clientIPv4: String
    let overlaySubnet: String
}

enum TunnelCoordinatorError: LocalizedError {
    case missingHop
    case missingHopInOptions
    case missingContext

    var errorDescription: String? {
        switch self {
        case .missingHop: return "No server selected in the app."
        case .missingHopInOptions: return "Tunnel start options did not include the server profile."
        case .missingContext: return "Tunnel start options did not include chain context."
        }
    }
}

final class TunnelCoordinator {
    var onSessionFailure: (@Sendable (String) -> Void)?

    private var sshSession: SSHHopSession?
    private var ipEngine: IPTunnelEngine?

    func prepare(options: [String: NSObject]?) async throws -> TunnelPrepareResult {
        let hop: HopNodeProfile
        if let fromOptions = TunnelBootstrap.hop(from: options) {
            hop = fromOptions
            TunnelLog.info("Using hop from tunnel options: \(hop.trimmedHost)")
        } else if let fromStore = ProfileStore.load().entryHop {
            hop = fromStore
            TunnelLog.info("Using hop from app group: \(hop.trimmedHost)")
        } else {
            throw TunnelCoordinatorError.missingHopInOptions
        }

        guard let context = TunnelBootstrap.context(from: options) else {
            throw TunnelCoordinatorError.missingContext
        }

        TunnelLog.info("SSH entry \(hop.trimmedUser)@\(hop.trimmedHost):\(hop.port) chain=\(context.chainID)")
        let session = try await SSHHopConnector.connect(entry: hop, hopperPort: context.hopperPort)
        sshSession = session

        let clientIP = try await IPTunnelAssignClient.performAssign(
            on: session.chainStream,
            deviceID: context.deviceID,
            chainID: context.chainID
        )

        let excluded = Self.resolveExcludedIPv4(host: hop.trimmedHost)
        TunnelLog.info("Entry hop excluded from routes: \(excluded.joined(separator: ", "))")
        TunnelLog.info("Assigned client overlay IP: \(clientIP)")

        return TunnelPrepareResult(
            excludedRoutes: excluded,
            clientIPv4: clientIP,
            overlaySubnet: ChainTopology.overlaySubnet(chainID: context.chainID)
        )
    }

    func startRelay(packetFlow: NEPacketTunnelFlow) {
        guard let stream = sshSession?.chainStream else {
            handleSSHFailure("SSH chain stream is not available.")
            return
        }

        let engine = IPTunnelEngine(stream: stream, packetFlow: packetFlow)
        engine.onFailure = { [weak self] message in
            self?.handleSSHFailure(message)
        }
        ipEngine = engine
        engine.start()
        TunnelLog.info("L3 iptunnel engine running")
    }

    private static func resolveExcludedIPv4(host: String) -> [String] {
        guard let ip = resolveIPv4(host) else {
            TunnelLog.error("Could not resolve hop host for route exclusion: \(host)")
            return []
        }
        return [ip]
    }

    private static func resolveIPv4(_ host: String) -> String? {
        var storage = in_addr()
        if inet_pton(AF_INET, host, &storage) == 1 {
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &storage, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
            return String(cString: buffer)
        }

        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let result else { return nil }
        defer { freeaddrinfo(result) }

        var cursor: UnsafeMutablePointer<addrinfo>? = result
        while let node = cursor {
            if node.pointee.ai_family == AF_INET, let addr = node.pointee.ai_addr {
                var sockaddr = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                if inet_ntop(AF_INET, &sockaddr.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                    return String(cString: buffer)
                }
            }
            cursor = node.pointee.ai_next
        }
        return nil
    }

    func stop() {
        ipEngine?.stop()
        ipEngine = nil

        let session = sshSession
        sshSession = nil
        session?.chainStream.close()

        if let client = session?.client {
            Task {
                do {
                    try await client.close()
                    TunnelLog.info("SSH client closed")
                } catch {
                    TunnelLog.error("SSH client close: \(HopErrorDetails.describe(error))")
                }
            }
        }
    }

    private func handleSSHFailure(_ message: String) {
        TunnelLog.error(message)
        onSessionFailure?(message)
    }
}

enum IPTunnelAssignClient {
    static func performAssign(on stream: SSHByteStream, deviceID: UUID, chainID: UUID) async throws -> String {
        let req = AssignRequest(deviceID: deviceID.uuidString, chainID: chainID.uuidString)
        let reqData = try JSONEncoder().encode(req)
        let frame = IPTunnelFrame(type: .assignReq, payload: reqData)
        try await stream.write(frame.encoded())

        let responseData = try await stream.read()
        let respFrame = try IPTunnelFrame.decode(from: responseData)
        guard respFrame.type == .assignResp else {
            throw IPTunnelProtocolError.assignFailed("expected assign response")
        }
        let resp = try JSONDecoder().decode(AssignResponse.self, from: respFrame.payload)
        if let error = resp.error {
            throw IPTunnelProtocolError.assignFailed(error)
        }
        guard let addr = resp.addr else {
            throw IPTunnelProtocolError.assignFailed("missing addr")
        }
        return addr
    }
}
