import Citadel
import Foundation
import NIO
import NIOSSH

enum SSHByteStreamError: LocalizedError {
    case closed
    case invalidAddress

    var errorDescription: String? {
        switch self {
        case .closed:
            return "SSH tunnel stream closed by the server — check ~/.hopper/chains/<chain_id>/hopper-YYYY-MM-DD.log on the entry hop."
        case .invalidAddress:
            return "Could not open the local SSH forward channel."
        }
    }
}

final class SSHByteStream: @unchecked Sendable {
    private let channel: Channel
    private let lock = NSLock()
    private let writeLock = NSLock()
    private var pending = Data()
    private var waiters: [CheckedContinuation<Data, Error>] = []
    private var isClosed = false

    private init(channel: Channel) {
        self.channel = channel
    }

    static func open(
        client: SSHClient,
        host: String,
        port: Int
    ) async throws -> SSHByteStream {
        let originator = try SocketAddress(ipAddress: "127.0.0.1", port: 0)
        let channel = try await client.createDirectTCPIPChannel(
            using: SSHChannelType.DirectTCPIP(
                targetHost: host,
                targetPort: port,
                originatorAddress: originator
            )
        ) { channel in
            channel.eventLoop.makeSucceededFuture(())
        }

        let stream = SSHByteStream(channel: channel)
        try await stream.installReader()
        return stream
    }

    private func installReader() async throws {
        final class Reader: ChannelInboundHandler, @unchecked Sendable {
            typealias InboundIn = ByteBuffer
            let owner: SSHByteStream

            init(owner: SSHByteStream) {
                self.owner = owner
            }

            func channelRead(context: ChannelHandlerContext, data: NIOAny) {
                let buffer = unwrapInboundIn(data)
                if let bytes = buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes) {
                    owner.append(Data(bytes))
                }
            }

            func channelInactive(context: ChannelHandlerContext) {
                owner.markClosed()
            }

            func errorCaught(context: ChannelHandlerContext, error: Error) {
                owner.failAll(error)
                context.close(promise: nil)
            }
        }

        try await channel.pipeline.addHandler(Reader(owner: self)).get()
    }

    private func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return }

        pending.append(data)
        guard let waiter = waiters.first else { return }
        waiters.removeFirst()
        let chunk = pending
        pending = Data()
        waiter.resume(returning: chunk)
    }

    private func markClosed() {
        lock.lock()
        defer { lock.unlock() }
        isClosed = true
        let all = waiters
        waiters.removeAll()
        all.forEach { $0.resume(throwing: SSHByteStreamError.closed) }
    }

    private func failAll(_ error: Error) {
        lock.lock()
        defer { lock.unlock() }
        isClosed = true
        let all = waiters
        waiters.removeAll()
        all.forEach { $0.resume(throwing: error) }
    }

    func read() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if isClosed {
                lock.unlock()
                continuation.resume(throwing: SSHByteStreamError.closed)
                return
            }
            if !pending.isEmpty {
                let chunk = pending
                pending = Data()
                lock.unlock()
                continuation.resume(returning: chunk)
                return
            }
            waiters.append(continuation)
            lock.unlock()
        }
    }

    func readFully(_ count: Int) async throws -> Data {
        guard count > 0 else { return Data() }
        var result = Data()
        result.reserveCapacity(count)
        while result.count < count {
            lock.lock()
            if !pending.isEmpty {
                let need = count - result.count
                let take = min(need, pending.count)
                result.append(pending.prefix(take))
                pending.removeFirst(take)
                lock.unlock()
                continue
            }
            if isClosed {
                lock.unlock()
                throw SSHByteStreamError.closed
            }
            lock.unlock()

            let chunk = try await read()
            if chunk.isEmpty {
                continue
            }
            let need = count - result.count
            if chunk.count <= need {
                result.append(chunk)
            } else {
                result.append(chunk.prefix(need))
                lock.lock()
                pending = Data(chunk.dropFirst(need)) + pending
                lock.unlock()
            }
        }
        return result
    }

    func write(_ data: Data) async throws {
        writeLock.lock()
        defer { writeLock.unlock() }
        var buffer = channel.allocator.buffer(bytes: Array(data))
        try await channel.writeAndFlush(buffer).get()
    }

    func close() {
        channel.close(promise: nil)
    }
}
