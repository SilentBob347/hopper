import Citadel
import Foundation

enum ChainProvisionerError: LocalizedError {
    case emptyChain
    case invalidReadyJSON(String)
    case missingPubkey(String)
    case provisionFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyChain:
            return "Add at least one hop (entry → exit order)."
        case .invalidReadyJSON(let output):
            let tail = output.suffix(200)
            return "Server did not return ready JSON. Output: \(tail)"
        case .missingPubkey(let hop):
            return "Could not read SSH public key on \(hop)."
        case .provisionFailed(let detail):
            return detail
        }
    }
}

enum ChainProvisioner {
    typealias ProgressHandler = (_ index: Int, _ total: Int, _ message: String) -> Void

    /// Provisions hops from exit (last) to entry (first).
    static func provision(chain: [HopNodeProfile], onProgress: ProgressHandler? = nil) async throws -> [HopReadyReport] {
        guard !chain.isEmpty else { throw ChainProvisionerError.emptyChain }

        let total = chain.count
        var reports: [HopReadyReport] = []

        onProgress?(total - 1, total, "Stopping previous hopperd on all hops…")
        for hop in chain {
            await stopNode(hop)
        }

        for i in stride(from: total - 1, through: 0, by: -1) {
            let hop = chain[i]
            let label = hop.displayName
            onProgress?(i, total, "Configuring \(label)…")
            TunnelLog.info("Chain provision hop[\(i)] \(label)")

            if i < total - 1 {
                let downstream = chain[i + 1]
                let pubkey = try await fetchPubkey(from: hop)
                try await trustPubkey(pubkey, on: downstream)
            }

            let report = try await startNode(
                hop: hop,
                index: i,
                isExit: i == total - 1,
                next: i < total - 1 ? chain[i + 1] : nil
            )
            reports.append(report)
            onProgress?(i, total, "\(label) ready (\(report.mode) \(report.addr))")
        }

        return reports.reversed()
    }

    private static func stopNode(_ hop: HopNodeProfile) async {
        let install = hop.resolvedInstallDir
        let cmd = "cd \(shellQuote(install)) && ./start_server.sh --stop-only"
        do {
            try await HopSSH.withSession(on: hop) { client in
                _ = try await HopSSH.runCommand(on: client, cmd)
            }
            TunnelLog.info("Stopped previous hopperd on \(hop.displayName)")
        } catch {
            TunnelLog.info("Stop hopperd on \(hop.displayName) (non-fatal): \(HopErrorDetails.describe(error))")
        }
    }

    private static func fetchPubkey(from hop: HopNodeProfile) async throws -> String {
        try await HopSSH.withSession(on: hop) { client in
            let output = try await HopSSH.runCommand(on: client, "cat ~/.hopper/id_ed25519.pub")
            let key = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard key.hasPrefix("ssh-") else {
                throw ChainProvisionerError.missingPubkey(hop.displayName)
            }
            return key
        }
    }

    private static func trustPubkey(_ pubkey: String, on hop: HopNodeProfile) async throws {
        let install = hop.resolvedInstallDir
        let cmd = "cd \(shellQuote(install)) && ./start_server.sh --trust-pubkey \(shellQuote(pubkey)) --trust-only"
        try await HopSSH.withSession(on: hop) { client in
            _ = try await HopSSH.runCommand(on: client, cmd)
        }
        TunnelLog.info("Trusted upstream key on \(hop.displayName)")
    }

    private static func startNode(
        hop: HopNodeProfile,
        index: Int,
        isExit: Bool,
        next: HopNodeProfile?
    ) async throws -> HopReadyReport {
        let install = hop.resolvedInstallDir
        let addr = ChainTopology.overlayAddr(index: index)
        var args = [
            "--role", isExit ? "exit" : "relay",
            "--addr", addr,
            "--index", String(index),
            "--overlay", HopConstants.tunnelIPv4Subnet,
        ]
        args += ["--client-addr", HopConstants.tunnelIPv4Address]
        if let next {
            args += [
                "--next-host", next.trimmedHost,
                "--next-port", String(next.port),
                "--next-user", next.trimmedUser,
            ]
        }

        let argString = args.map(shellQuote).joined(separator: " ")
        let cmd = "cd \(shellQuote(install)) && ./start_server.sh \(argString)"

        return try await HopSSH.withSession(on: hop) { client in
            let output = try await HopSSH.runCommand(on: client, cmd)
            return try HopReadyReport.parse(from: output)
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private extension HopNodeProfile {
    var resolvedInstallDir: String {
        let trimmed = installDir.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? HopConstants.defaultInstallDir : trimmed
    }
}
