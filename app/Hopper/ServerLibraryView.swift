import SwiftUI

struct ServerLibraryView: View {
    @EnvironmentObject private var vpn: VPNController
    @Environment(\.dismiss) private var dismiss
    var chainID: UUID? = nil

    @State private var showScanner = false
    @State private var showImportJSON = false
    @State private var showDeploy = false

    private var isPickMode: Bool { chainID != nil }

    private var displayedServers: [HopNodeProfile] {
        guard let chainID else { return vpn.state.servers }
        guard let chain = vpn.state.chains.first(where: { $0.id == chainID }) else { return [] }
        let used = Set(chain.hopIDs)
        return vpn.state.servers.filter { !used.contains($0.id) }
    }

    var body: some View {
        List {
            if displayedServers.isEmpty {
                ContentUnavailableView(
                    "No servers",
                    systemImage: "server.rack",
                    description: Text(emptyDescription)
                )
            } else {
                ForEach(displayedServers) { server in
                    if isPickMode, let chainID {
                        Button {
                            vpn.addServerToChain(chainID: chainID, serverID: server.id)
                            dismiss()
                        } label: {
                            serverLabel(server)
                        }
                        .foregroundStyle(.primary)
                    } else {
                        NavigationLink {
                            ServerDetailView(serverID: server.id)
                        } label: {
                            serverLabel(server)
                        }
                    }
                }
                .onDelete { offsets in
                    guard !isPickMode else { return }
                    let idsToDelete = Set(offsets.map { displayedServers[$0].id })
                    var indices = IndexSet()
                    for (index, server) in vpn.state.servers.enumerated() where idsToDelete.contains(server.id) {
                        indices.insert(index)
                    }
                    if !indices.isEmpty {
                        vpn.deleteServers(at: indices)
                    }
                }
            }
        }
        .navigationTitle(isPickMode ? "Add server" : "Servers")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Deploy") { showDeploy = true }
                Button("Scan QR") { showScanner = true }
                Button("Import JSON") { showImportJSON = true }
            }
        }
        .sheet(isPresented: $showScanner) {
            QRCodeScannerView { payload in
                do {
                    let hop = try HopQRParser.parse(payload)
                    vpn.addServer(hop)
                    showScanner = false
                } catch {
                    vpn.errorMessage = error.localizedDescription
                }
            }
        }
        .sheet(isPresented: $showDeploy) {
            DeployServerView()
        }
        .sheet(isPresented: $showImportJSON) {
            HopImportJSONView { hop in
                vpn.addServer(hop)
                showImportJSON = false
            }
        }
    }

    private var emptyDescription: String {
        if isPickMode {
            return "Deploy a server, scan a QR code, or import JSON, then tap to add to this chain."
        }
        return "Deploy a server, scan a QR code, or import JSON."
    }

    @ViewBuilder
    private func serverLabel(_ server: HopNodeProfile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(server.displayName).font(.headline)
            Text("\(server.trimmedUser)@\(server.trimmedHost):\(server.port)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
