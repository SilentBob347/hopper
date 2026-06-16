import SwiftUI

struct ServerLibraryView: View {
    @EnvironmentObject private var vpn: VPNController
    @State private var showScanner = false
    @State private var showImportJSON = false

    var body: some View {
        List {
            if vpn.state.servers.isEmpty {
                ContentUnavailableView(
                    "No servers",
                    systemImage: "server.rack",
                    description: Text("Scan a QR code or import JSON from deploy.sh shown in the browser.")
                )
            } else {
                ForEach(vpn.state.servers) { server in
                    NavigationLink {
                        ServerDetailView(serverID: server.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.displayName).font(.headline)
                            Text("\(server.trimmedUser)@\(server.trimmedHost):\(server.port)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in vpn.deleteServers(at: offsets) }
            }
        }
        .navigationTitle("Servers")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Import JSON") { showImportJSON = true }
                Button("Scan QR") { showScanner = true }
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
        .sheet(isPresented: $showImportJSON) {
            HopImportJSONView { hop in
                vpn.addServer(hop)
                showImportJSON = false
            }
        }
    }
}
