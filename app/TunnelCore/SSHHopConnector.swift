import Citadel
import Foundation

enum SSHHopConnectorError: LocalizedError {
    case chainOpenFailed(String)

    var errorDescription: String? {
        switch self {
        case .chainOpenFailed(let detail):
            return "Could not open chain tunnel: \(detail)"
        }
    }
}

struct SSHHopSession {
    let client: SSHClient
    let chainStream: SSHByteStream
}

enum SSHHopConnector {
    /// Connects to the entry hop only. Downstream hops are reached via server-side hopperd routing.
    static func connect(entry: HopNodeProfile, hopperPort: Int) async throws -> SSHHopSession {
        TunnelLog.info("SSH connect to \(entry.trimmedUser)@\(entry.trimmedHost):\(entry.port)")
        let client: SSHClient
        do {
            client = try await connect(node: entry)
            try await Task.sleep(nanoseconds: 300_000_000)
        } catch {
            throw wrap(error, step: "SSH connect to \(entry.trimmedHost)")
        }

        let chainStream: SSHByteStream
        do {
            chainStream = try await openChainStream(client: client, hopperPort: hopperPort)
        } catch {
            throw wrap(error, step: "hopper tunnel to 127.0.0.1:\(hopperPort)")
        }

        return SSHHopSession(client: client, chainStream: chainStream)
    }

    private static func openChainStream(client: SSHClient, hopperPort: Int) async throws -> SSHByteStream {
        var lastError: Error?
        for attempt in 1...6 {
            if attempt > 1 {
                try await Task.sleep(nanoseconds: 300_000_000)
            }
            TunnelLog.info("Opening hopper stream to 127.0.0.1:\(hopperPort) (attempt \(attempt))")
            do {
                return try await SSHByteStream.open(
                    client: client,
                    host: "127.0.0.1",
                    port: hopperPort
                )
            } catch {
                lastError = error
                TunnelLog.error("Chain stream attempt \(attempt) failed: \(HopErrorDetails.describe(error))")
            }
        }
        throw SSHHopConnectorError.chainOpenFailed(HopErrorDetails.describe(lastError ?? SSHByteStreamError.closed))
    }

    private static func wrap(_ error: Error, step: String) -> Error {
        let detail = HopErrorDetails.describe(error)
        TunnelLog.error("\(step) failed: \(detail)")
        if error is SSHHopConnectorError || error is HopSSHError || error is TunnelCoordinatorError {
            return error
        }
        return NSError(
            domain: HopConstants.mainBundleID,
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "\(step): \(detail)"]
        )
    }

    private static func connect(node: HopNodeProfile) async throws -> SSHClient {
        try await HopSSH.connect(node)
    }
}
