import Citadel
import Crypto
import Foundation
import NIO
import NIOSSH

enum HopSSHError: LocalizedError {
    case invalidPrivateKey

    var errorDescription: String? {
        switch self {
        case .invalidPrivateKey:
            return "Could not parse the SSH private key from the hop profile."
        }
    }
}

enum HopSSH {
    static let sharedEventLoop = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private static let eventLoop = sharedEventLoop

    static func settings(for node: HopNodeProfile) throws -> SSHClientSettings {
        let privateKey: Curve25519.Signing.PrivateKey
        do {
            privateKey = try Curve25519.Signing.PrivateKey(sshEd25519: node.privateKey)
        } catch {
            throw HopSSHError.invalidPrivateKey
        }
        let authMethod = SSHAuthenticationMethod.ed25519(username: node.trimmedUser, privateKey: privateKey)

        var settings = SSHClientSettings(
            host: node.trimmedHost,
            port: node.port,
            authenticationMethod: { authMethod },
            hostKeyValidator: .acceptAnything()
        )
        settings.group = eventLoop
        settings.connectTimeout = .seconds(60)
        settings.loginTimeout = .seconds(60)
        return settings
    }

    static func connect(_ node: HopNodeProfile) async throws -> SSHClient {
        try await SSHClient.connect(to: settings(for: node))
    }

    static func runCommand(on client: SSHClient, _ command: String) async throws -> String {
        try await runCommand(on: client, command, onLine: nil)
    }

    static func runCommand(
        on client: SSHClient,
        _ command: String,
        onLine: (@Sendable (String) -> Void)?
    ) async throws -> String {
        if let onLine {
            return try await runCommandStreaming(on: client, command, onLine: onLine)
        }
        let buffer = try await client.executeCommand(command, mergeStreams: false)
        return String(buffer: buffer)
    }

    private static func runCommandStreaming(
        on client: SSHClient,
        _ command: String,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        var collected = ""
        var pending = ""
        let stream = try await client.executeCommandStream(command)

        func flushPending(asFinal: Bool = false) {
            while let newline = pending.firstIndex(of: "\n") {
                let line = String(pending[..<newline])
                pending = String(pending[pending.index(after: newline)...])
                onLine(line)
            }
            if asFinal, !pending.isEmpty {
                onLine(pending)
                pending = ""
            }
        }

        for try await output in stream {
            let chunk: String
            switch output {
            case .stdout(let buffer), .stderr(let buffer):
                chunk = String(buffer: buffer)
            }
            collected += chunk
            pending += chunk
            flushPending()
        }
        flushPending(asFinal: true)
        return collected
    }

    static func withSession<T>(
        on node: HopNodeProfile,
        _ work: (SSHClient) async throws -> T
    ) async throws -> T {
        let client = try await connect(node)
        do {
            let result = try await work(client)
            try? await client.close()
            return result
        } catch {
            try? await client.close()
            throw error
        }
    }
}
