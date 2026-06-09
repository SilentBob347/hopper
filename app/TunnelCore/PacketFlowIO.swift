import Foundation
import NetworkExtension

final class PacketFlowIO: @unchecked Sendable {
    private let packetFlow: NEPacketTunnelFlow
    private let queue = DispatchQueue(label: "com.aengix.hopper.packetFlow")

    init(packetFlow: NEPacketTunnelFlow) {
        self.packetFlow = packetFlow
    }

    func readPackets() async -> ([Data], [NSNumber]) {
        await withCheckedContinuation { continuation in
            queue.async {
                self.packetFlow.readPackets { packets, protocols in
                    continuation.resume(returning: (packets, protocols))
                }
            }
        }
    }

    func writePackets(_ packets: [Data], withProtocols protocols: [NSNumber]) {
        queue.async {
            self.packetFlow.writePackets(packets, withProtocols: protocols)
        }
    }
}
