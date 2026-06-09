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
    private static let eventLoop = MultiThreadedEventLoopGroup(numberOfThreads: 1)

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
        let buffer = try await client.executeCommand(command, mergeStreams: false)
        return String(buffer: buffer)
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
