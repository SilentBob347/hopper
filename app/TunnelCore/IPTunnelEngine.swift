import Darwin
import Foundation
import NetworkExtension

final class IPTunnelEngine {
    private let stream: SSHByteStream
    private let packetIO: PacketFlowIO
    private var tasks: [Task<Void, Never>] = []
    private var inboundBuffer = Data()
    private let bufferLock = NSLock()

    var onFailure: (@Sendable (String) -> Void)?

    init(stream: SSHByteStream, packetFlow: NEPacketTunnelFlow) {
        self.stream = stream
        self.packetIO = PacketFlowIO(packetFlow: packetFlow)
    }

    func start() {
        TunnelLog.info("IPTunnelEngine starting")
        tasks.append(Task { await self.tunToSSH() })
        tasks.append(Task { await self.sshToTun() })
        tasks.append(Task { await self.keepaliveLoop() })
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        stream.close()
        TunnelLog.info("IPTunnelEngine stopped")
    }

    private func tunToSSH() async {
        while !Task.isCancelled {
            let (packets, _) = await packetIO.readPackets()
            if Task.isCancelled { return }
            if packets.isEmpty {
                try? await Task.sleep(nanoseconds: 5_000_000)
                continue
            }
            for packet in packets {
                guard !packet.isEmpty else { continue }
                let frame = IPTunnelFrame(type: .data, payload: packet)
                do {
                    try await stream.write(frame.encoded())
                } catch {
                    fail("TUN write to SSH failed: \(HopErrorDetails.describe(error))")
                    return
                }
            }
        }
    }

    private func sshToTun() async {
        while !Task.isCancelled {
            let chunk: Data
            do {
                chunk = try await stream.read()
            } catch {
                if Task.isCancelled { return }
                fail("SSH read failed: \(HopErrorDetails.describe(error))")
                return
            }
            if chunk.isEmpty {
                continue
            }

            bufferLock.lock()
            inboundBuffer.append(chunk)
            let buffer = inboundBuffer
            inboundBuffer = Data()
            bufferLock.unlock()

            var cursor = buffer
            while true {
                guard cursor.count >= IPTunnelFrame.headerLength else {
                    bufferLock.lock()
                    inboundBuffer = cursor
                    bufferLock.unlock()
                    break
                }

                guard cursor[0] == IPTunnelFrame.wireVersion else {
                    fail("Invalid iptunnel frame: badVersion (stream misaligned, head=\(Self.hexPreview(cursor)))")
                    return
                }

                guard IPTunnelFrameType(rawValue: cursor[1]) != nil else {
                    fail("Invalid iptunnel frame: badType (head=\(Self.hexPreview(cursor)))")
                    return
                }

                let payloadLength = Int(cursor.uint16BE(at: 2))
                guard payloadLength <= IPTunnelFrame.maxPacketLength else {
                    fail("Invalid iptunnel frame: packetTooLarge (\(payloadLength))")
                    return
                }

                let frameLength = IPTunnelFrame.headerLength + payloadLength
                guard cursor.count >= frameLength else {
                    bufferLock.lock()
                    inboundBuffer = cursor
                    bufferLock.unlock()
                    break
                }

                let frameData = cursor.prefix(frameLength)
                cursor = Data(cursor.dropFirst(frameLength))

                do {
                    let frame = try IPTunnelFrame.decode(from: frameData)
                    switch frame.type {
                    case .data:
                        packetIO.writePackets([frame.payload], withProtocols: [AF_INET as NSNumber])
                    case .keepalive, .assignReq, .assignResp:
                        break
                    }
                } catch {
                    fail("Invalid iptunnel frame: \(error) (head=\(Self.hexPreview(frameData)))")
                    return
                }
            }
        }
    }

    private func keepaliveLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            if Task.isCancelled { return }
            let frame = IPTunnelFrame(type: .keepalive)
            do {
                try await stream.write(frame.encoded())
            } catch {
                if Task.isCancelled { return }
                fail("SSH keepalive failed: \(HopErrorDetails.describe(error))")
                return
            }
        }
    }

    private func fail(_ message: String) {
        TunnelLog.error(message)
        onFailure?(message)
        stop()
    }

    private static func hexPreview(_ data: Data, limit: Int = 16) -> String {
        data.prefix(limit).map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}
