#!/usr/bin/env python3
"""Idempotent compatibility and flow-control fixes for pinned checkouts."""
import argparse
from pathlib import Path
import stat


def write_source(path, text):
    # SwiftPM checkouts can be read-only. Only this checkout copy changes.
    path.chmod(path.stat().st_mode | stat.S_IWUSR)
    path.write_text(text)


def replace_once(path, before, after):
    text = path.read_text()
    if after in text:
        return
    if text.count(before) != 1:
        raise RuntimeError(f"Unexpected dependency source: {path}")
    write_source(path, text.replace(before, after, 1))


def patch(checkouts):
    powerline = next(checkouts.glob("SwiftTerm/Sources/**/PowerlineRenderer.swift"))
    text = powerline.read_text()
    while "Array(Array(flameLowerPath.dropFirst()))" in text:
        text = text.replace("Array(Array(flameLowerPath.dropFirst()))", "Array(flameLowerPath.dropFirst())")
    if "Array(flameLowerPath.dropFirst())" not in text:
        if "flameLowerPath.dropFirst()" not in text:
            raise RuntimeError("Unexpected SwiftTerm PowerlineRenderer")
        text = text.replace("flameLowerPath.dropFirst()", "Array(flameLowerPath.dropFirst())")
    write_source(powerline, text)

    tty = checkouts / "Citadel/Sources/Citadel/TTY/Client/TTY.swift"
    replace_once(tty,
        "    internal let sequence: AsyncThrowingStream<ExecCommandOutput, Error>",
        """    internal let sequence: AsyncThrowingStream<ExecCommandOutput, Error>
    internal let channel: Channel?

    internal init(sequence: AsyncThrowingStream<ExecCommandOutput, Error>, channel: Channel? = nil) {
        self.sequence = sequence
        self.channel = channel
    }""")
    replace_once(tty,
        "        var iterator: AsyncThrowingStream<ExecCommandOutput, Error>.AsyncIterator",
        """        var iterator: AsyncThrowingStream<ExecCommandOutput, Error>.AsyncIterator
        let channel: Channel?""")
    replace_once(tty,
        "            try await iterator.next()",
        """            // PTY reads follow consumer demand all the way to NIO.
            channel?.read()
            return try await iterator.next()""")
    replace_once(tty,
        "AsyncIterator(iterator: sequence.makeAsyncIterator())",
        "AsyncIterator(iterator: sequence.makeAsyncIterator(), channel: channel)")
    replace_once(tty,
        "        mode: CommandMode\n    ) async throws -> (channel: Channel, output:",
        "        mode: CommandMode,\n        paced: Bool = false\n    ) async throws -> (channel: Channel, output:")
    replace_once(tty,
        "                channel.pipeline.addHandlers(handler)",
        """                channel.pipeline.addHandlers(handler).flatMap {
                    channel.setOption(ChannelOptions.autoRead, value: !paced)
                }""")
    replace_once(tty,
        "            mode: .pty(request)\n",
        "            mode: .pty(request), paced: true\n")
    replace_once(tty,
        """        do {
            let inbound = TTYOutput(sequence: output)
            try await perform(inbound, TTYStdinWriter(channel: channel))
            try await close()
        } catch {
            try await close()
            throw error
        }
    }

    /// Creates a TTY session""",
        """        try await withTaskCancellationHandler {
            do {
                let inbound = TTYOutput(sequence: output, channel: channel)
                try await perform(inbound, TTYStdinWriter(channel: channel))
                try await close()
            } catch {
                try? await close()
                throw error
            }
        } onCancel: {
            // Closing the child wakes a suspended stream or writer.
            channel.close(promise: nil)
        }
    }

    /// Creates a TTY session""")

    session = checkouts / "Citadel/Sources/Citadel/ClientSession.swift"
    serializer = checkouts / "Citadel/Sources/Citadel/SFTP/SFTPSerializer.swift"
    replace_once(serializer,
        "            out.writeSSHString(rename.newPath)\n            out.writeInteger(rename.flags)",
        "            out.writeSSHString(rename.newPath)\n            // SFTP v3 RENAME has no flags field.")
    replace_once(session, "import NIO\n", "import NIO\n#if canImport(Darwin)\nimport Darwin\n#endif\n")
    replace_once(session,
        "        return try await bootstrap.connect(host: settings.host, port: settings.port).flatMap { channel in",
        """        _ = bootstrap.channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_KEEPALIVE), value: 1)
        #if canImport(Darwin)
        _ = bootstrap.channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_KEEPALIVE), value: 30)
        _ = bootstrap.channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_KEEPINTVL), value: 10)
        _ = bootstrap.channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_KEEPCNT), value: 3)
        #endif
        return try await bootstrap.connect(host: settings.host, port: settings.port).flatMap { channel in""")

    nio = checkouts / "swift-nio-ssh/Sources/NIOSSH/NIOSSHHandler.swift"
    replace_once(nio,
        "    private func dropAllPendingGlobalRequests(_ error: Error) {",
        """    /// Event-loop-only heartbeat; either request success or refusal
    /// proves that the authenticated peer has responded.
    public func sendKeepAlive(promise: EventLoopPromise<ByteBuffer?>) {
        sendGlobalRequestMessage(.init(wantReply: true,
            type: .unknown("keepalive@openssh.com", ByteBuffer())), promise: promise)
    }

    private func dropAllPendingGlobalRequests(_ error: Error) {""")
    client = checkouts / "Citadel/Sources/Citadel/Client.swift"
    replace_once(client,
        "    public func onDisconnect(perform onDisconnect: @escaping @Sendable () -> ()) {",
        """    /// A transport heartbeat without opening an exec channel.
    public func sendKeepAlive() async throws {
        do {
            _ = try await eventLoop.flatSubmit { [sshHandler = session.sshHandler, eventLoop] in
                let promise = eventLoop.makePromise(of: ByteBuffer?.self)
                sshHandler.value.sendKeepAlive(promise: promise)
                return promise.futureResult
            }.get()
        } catch let error as NIOSSHError where error.type == .globalRequestRefused {
            // Refusal of an unknown request is a valid live response.
            return
        }
    }

    public func onDisconnect(perform onDisconnect: @escaping @Sendable () -> ()) {""")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("checkouts", type=Path)
    patch(parser.parse_args().checkouts)
    print("Pinned dependency patches applied")
