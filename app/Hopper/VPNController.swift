import Foundation
import NetworkExtension

@MainActor
final class VPNController: ObservableObject {
    @Published private(set) var state: AppState
    @Published private(set) var vpnStatus: NEVPNStatus = .invalid
    @Published private(set) var provisionStatus: String?
    @Published var errorMessage: String?

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?

    init() {
        state = ProfileStore.load()
        Task { await reloadVPN() }
    }

    var isConnected: Bool { vpnStatus == .connected }
    var isBusy: Bool { vpnStatus == .connecting || vpnStatus == .disconnecting }

    // MARK: - Servers

    func addServer(_ server: HopNodeProfile) {
        state.addServer(server)
        persist()
    }

    func deleteServers(at offsets: IndexSet) {
        state.removeServers(at: offsets)
        persist()
    }

    // MARK: - Chains

    @discardableResult
    func addChain(name: String = "") -> UUID {
        let id = state.addChain(name: name)
        persist()
        return id
    }

    func deleteChains(at offsets: IndexSet) {
        state.removeChains(at: offsets)
        persist()
    }

    func selectChain(_ id: UUID?) {
        state.selectChain(id)
        persist()
    }

    func renameChain(id: UUID, name: String) {
        state.renameChain(id: id, name: name)
        persist()
    }

    func moveHopInChain(chainID: UUID, from source: IndexSet, to destination: Int) {
        state.moveHopInChain(chainID: chainID, from: source, to: destination)
        persist()
    }

    func addServerToChain(chainID: UUID, serverID: UUID) {
        state.addServerToChain(chainID: chainID, serverID: serverID)
        persist()
    }

    func removeHopFromChain(chainID: UUID, at offsets: IndexSet) {
        state.removeHopFromChain(chainID: chainID, at: offsets)
        persist()
    }

    // MARK: - VPN

    func connect() async {
        guard let entry = state.entryHop else {
            reportError("Select a chain with at least one server (entry → exit).")
            return
        }
        errorMessage = nil
        provisionStatus = nil
        ProfileStore.clearLastTunnelError()

        let hops = state.activeHops
        do {
            provisionStatus = "Provisioning chain (exit → entry)…"
            _ = try await ChainProvisioner.provision(chain: hops) { [weak self] index, total, message in
                Task { @MainActor in
                    self?.provisionStatus = "[\(total - index)/\(total)] \(message)"
                }
            }
            provisionStatus = "Starting VPN…"

            let manager = try await ensureManager(hop: entry)
            self.manager = manager
            observeStatus()
            try manager.connection.startVPNTunnel(options: TunnelBootstrap.options(hop: entry))
            provisionStatus = nil
        } catch {
            provisionStatus = nil
            reportError(HopErrorDetails.describe(error))
        }
    }

    func disconnect() {
        manager?.connection.stopVPNTunnel()
    }

    func toggle() async {
        if isConnected || isBusy {
            disconnect()
        } else {
            await connect()
        }
    }

    private func persist() {
        ProfileStore.save(state)
    }

    private func ensureManager(hop: HopNodeProfile) async throws -> NETunnelProviderManager {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        let manager = managers.first(where: Self.isHopperManager) ?? NETunnelProviderManager()

        manager.localizedDescription = HopConstants.appDisplayName
        manager.isEnabled = true
        manager.protocolConfiguration = Self.makeProtocol(hop: hop)

        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()

        guard manager.protocolConfiguration is NETunnelProviderProtocol else {
            throw VPNError.invalidProtocol
        }

        vpnStatus = manager.connection.status
        return manager
    }

    private func reloadVPN() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            manager = managers.first(where: Self.isHopperManager)
            vpnStatus = manager?.connection.status ?? .invalid
            observeStatus()
        } catch {
            reportError(HopErrorDetails.describe(error))
        }
    }

    private func observeStatus() {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }
        guard let connection = manager?.connection else { return }
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: connection,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.vpnStatus = self.manager?.connection.status ?? .invalid
                if self.vpnStatus == .disconnected {
                    await self.readTunnelError()
                }
            }
        }
    }

    private func readTunnelError() async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        if let saved = ProfileStore.loadLastTunnelError() {
            reportError(saved)
            return
        }
        guard let session = manager?.connection as? NETunnelProviderSession else { return }
        session.fetchLastDisconnectError { [weak self] error in
            Task { @MainActor in
                guard let self, let error else { return }
                self.reportError(HopErrorDetails.describe(error))
            }
        }
    }

    private func reportError(_ message: String) {
        let detail = HopErrorDetails.describeMessage(message)
        errorMessage = detail
        TunnelLog.error("[App] \(detail)")
    }

    private static func isHopperManager(_ manager: NETunnelProviderManager) -> Bool {
        (manager.protocolConfiguration as? NETunnelProviderProtocol)?
            .providerBundleIdentifier == HopConstants.tunnelBundleID
    }

    private static func makeProtocol(hop: HopNodeProfile) -> NETunnelProviderProtocol {
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = HopConstants.tunnelBundleID
        proto.serverAddress = hop.trimmedHost
        proto.providerConfiguration = TunnelBootstrap.options(hop: hop)
        return proto
    }
}

enum VPNError: LocalizedError {
    case invalidProtocol

    var errorDescription: String? {
        switch self {
        case .invalidProtocol:
            return "VPN protocol configuration is invalid. Reinstall the app and try again."
        }
    }
}
