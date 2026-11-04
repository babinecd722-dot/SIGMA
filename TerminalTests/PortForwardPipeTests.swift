import XCTest
import NIO
import NIOEmbedded
import NIOConcurrencyHelpers
@testable import Terminal

final class PortForwardPipeTests: XCTestCase {
    func testActiveForwardedChannelWaitsForTargetActivationBeforeReading() throws {
        let loop = EmbeddedEventLoop()
        let (a, b) = NIOPipeHandler.matchedPair()
        let fromSSH = ReadCounter()
        let fromTarget = ReadCounter()
        let forwarded = EmbeddedChannel(handler: fromSSH, loop: loop)
        try forwarded.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 1)).wait()
        let initialSSHReads = fromSSH.reads
        try forwarded.pipeline.addHandler(a).wait()
        XCTAssertEqual(fromSSH.reads, initialSSHReads, "No read before a target handler exists")
        let target = EmbeddedChannel(handlers: [fromTarget, b], loop: loop)
        defer { _ = try? forwarded.finish(acceptAlreadyClosed: true); _ = try? target.finish(acceptAlreadyClosed: true) }
        XCTAssertEqual(fromSSH.reads, initialSSHReads, "An inactive target must not release the forwarded gate")
        XCTAssertEqual(fromTarget.reads, 0)
        try target.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 2)).wait()
        XCTAssertEqual(fromSSH.reads, initialSSHReads + 1)
        XCTAssertEqual(fromTarget.reads, 1)
        target.isWritable = false
        target.pipeline.fireChannelWritabilityChanged()
        try forwarded.writeInbound(ByteBuffer(string: "FIRST"))
        XCTAssertEqual(fromSSH.reads, initialSSHReads + 1, "Backpressure must hold the next source read")
        target.isWritable = true
        target.pipeline.fireChannelWritabilityChanged()
        XCTAssertEqual(fromSSH.reads, initialSSHReads + 2)
        target.pipeline.fireChannelWritabilityChanged()
        XCTAssertEqual(fromSSH.reads, initialSSHReads + 2, "A repeated writability event must not duplicate a pending read")
    }

    func testRealTargetGreetingSurvivesBridgeStartup() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let target = try ServerBootstrap(group: group)
            .childChannelInitializer { $0.pipeline.addHandler(ImmediateGreeting()) }
            .bind(host: "127.0.0.1", port: 0).wait()
        defer { try? target.close().wait() }
        let targetPort = try XCTUnwrap(target.localAddress?.port)
        let forward = try ServerBootstrap(group: group)
            .childChannelInitializer { channel in
                NIOPipeHandler.connect(forwarded: channel, targetHost: "127.0.0.1", targetPort: targetPort)
            }.bind(host: "127.0.0.1", port: 0).wait()
        defer { try? forward.close().wait() }
        let received = group.next().makePromise(of: String.self)
        let timeout = received.futureResult.eventLoop.scheduleTask(in: .seconds(5)) { received.fail(PipeTestError.timeout) }
        defer { timeout.cancel() }
        let client = try ClientBootstrap(group: group)
            .channelInitializer { $0.pipeline.addHandler(ResponseCollector(result: received)) }
            .connect(host: "127.0.0.1", port: try XCTUnwrap(forward.localAddress?.port)).wait()
        defer { try? client.close().wait() }
        try client.writeAndFlush(ByteBuffer(string: "PING")).wait()
        XCTAssertEqual(try received.futureResult.wait(), "TARGET_HELLOPING")
    }

    func testTargetConnectionRefusalReleasesForwardedChannel() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let target = try ServerBootstrap(group: group).bind(host: "127.0.0.1", port: 0).wait()
        let port = try XCTUnwrap(target.localAddress?.port)
        try target.close().wait()
        let failedChild = group.next().makePromise(of: Channel.self)
        let timeout = failedChild.futureResult.eventLoop.scheduleTask(in: .seconds(5)) { failedChild.fail(PipeTestError.timeout) }
        defer { timeout.cancel() }
        let forward = try ServerBootstrap(group: group)
            .childChannelInitializer { channel in
                let opening = NIOPipeHandler.connect(forwarded: channel, targetHost: "127.0.0.1", targetPort: port)
                opening.whenFailure { _ in failedChild.succeed(channel) }
                return opening
            }.bind(host: "127.0.0.1", port: 0).wait()
        defer { try? forward.close().wait() }
        let client = try ClientBootstrap(group: group)
            .connect(host: "127.0.0.1", port: try XCTUnwrap(forward.localAddress?.port)).wait()
        defer { try? client.close().wait() }
        let child = try failedChild.futureResult.wait()
        try child.closeFuture.wait()
        XCTAssertFalse(child.isActive)
    }

    func testImmediateTargetGreetingAndMultipleChunksAreForwardedInOrder() throws {
        let loop = EmbeddedEventLoop()
        let (a, b) = NIOPipeHandler.matchedPair()
        let forwarded = EmbeddedChannel(handler: a, loop: loop)
        let target = EmbeddedChannel(handler: b, loop: loop)
        defer { _ = try? forwarded.finish(acceptAlreadyClosed: true); _ = try? target.finish(acceptAlreadyClosed: true) }
        try forwarded.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 1)).wait()
        try target.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 2)).wait()
        for message in ["GREETING", "second", "third"] {
            try target.writeInbound(ByteBuffer(string: message))
            XCTAssertEqual(try forwarded.readOutbound(as: ByteBuffer.self), ByteBuffer(string: message))
        }
        try forwarded.writeInbound(ByteBuffer(string: "REQUEST"))
        XCTAssertEqual(try target.readOutbound(as: ByteBuffer.self), ByteBuffer(string: "REQUEST"))
    }

    func testClosingEitherChannelClosesItsPeer() throws {
        let loop = EmbeddedEventLoop()
        let (a, b) = NIOPipeHandler.matchedPair()
        let forwarded = EmbeddedChannel(handler: a, loop: loop)
        let target = EmbeddedChannel(handler: b, loop: loop)
        try forwarded.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 1)).wait()
        try target.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 2)).wait()
        try target.close().wait()
        loop.run()
        XCTAssertFalse(target.isActive)
        XCTAssertFalse(forwarded.isActive, "A rejected or closed target must not leave its forwarded channel alive")
        _ = try forwarded.finish(acceptAlreadyClosed: true)
        _ = try target.finish(acceptAlreadyClosed: true)
    }
}

private enum PipeTestError: Error { case timeout }

private final class ReadCounter: ChannelOutboundHandler {
    typealias OutboundIn = ByteBuffer
    private(set) var reads = 0
    func read(context: ChannelHandlerContext) {
        reads += 1
        context.read()
    }
}

private final class ImmediateGreeting: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    func channelActive(context: ChannelHandlerContext) {
        context.writeAndFlush(NIOAny(ByteBuffer(string: "TARGET_HELLO")), promise: nil)
        context.fireChannelActive()
    }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        context.writeAndFlush(data, promise: nil)
    }
}

private final class ResponseCollector: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    let result: EventLoopPromise<String>
    private var bytes = ByteBuffer()
    init(result: EventLoopPromise<String>) { self.result = result }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var incoming = unwrapInboundIn(data)
        bytes.writeBuffer(&incoming)
        if bytes.readableBytes >= "TARGET_HELLOPING".utf8.count {
            result.succeed(String(buffer: bytes))
        }
    }
}
