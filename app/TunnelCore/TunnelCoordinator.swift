import Foundation
import NetworkExtension

enum TunnelCoordinatorError: LocalizedError {
    case missingHop
    case missingHopInOptions

    var errorDescription: String? {
        switch self {
        case .missingHop: return "No server selected in the app."
        case .missingHopInOptions: return "Tunnel start options did not include the server profile."
        }
    }
}

final class TunnelCoordinator {
    var onSessionFailure: (@Sendable (String) -> Void)?

    private var sshSession: SSHHopSession?
    private var ipEngine: IPTunnelEngine?

    func prepare(options: [String: NSObject]?) async throws -> [String] {
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

        TunnelLog.info("SSH entry \(hop.trimmedUser)@\(hop.trimmedHost):\(hop.port)")
        let session = try await SSHHopConnector.connect(entry: hop)
        sshSession = session

        let excluded = Self.resolveExcludedIPv4(host: hop.trimmedHost)
        TunnelLog.info("Entry hop excluded from routes: \(excluded.joined(separator: ", "))")
        return excluded
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
