#!/usr/bin/env python3
"""Idempotent compatibility and flow-control fixes for pinned checkouts."""
import argparse
from pathlib import Path
import stat
from patch_crypto_security import patch_crypto_security
from patch_terminal_security import patch_terminal_security
from patch_terminal_selection import patch_terminal_selection


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
    patch_crypto_security(checkouts, replace_once, write_source)
    powerline = next(checkouts.glob("SwiftTerm/Sources/**/PowerlineRenderer.swift"))
    text = powerline.read_text()
    while "Array(Array(flameLowerPath.dropFirst()))" in text:
        text = text.replace("Array(Array(flameLowerPath.dropFirst()))", "Array(flameLowerPath.dropFirst())")
    if "Array(flameLowerPath.dropFirst())" not in text:
        if "flameLowerPath.dropFirst()" not in text:
            raise RuntimeError("Unexpected SwiftTerm PowerlineRenderer")
        text = text.replace("flameLowerPath.dropFirst()", "Array(flameLowerPath.dropFirst())")
    write_source(powerline, text)

    patch_terminal_selection(checkouts, replace_once, write_source)

    tty = checkouts / "Citadel/Sources/Citadel/TTY/Client/TTY.swift"
    replace_once(tty,
        "    public struct CommandFailed: Error {",
        """    /// A PTY vanished without a process exit status (disconnect/reboot).
    public struct PTYClosedWithoutExit: Error, Sendable {
        public init() {}
    }

    public struct CommandFailed: Error {""")
    replace_once(tty,
        """                } else if let exitCode = exitCode.withLockedValue({ $0 }), exitCode != 0 {
                    streamContinuation.finish(throwing: CommandFailed(exitCode: exitCode))
                } else {
                    streamContinuation.finish()
                }""",
        """                } else if let status = exitCode.withLockedValue({ $0 }) {
                    if status == 0 { streamContinuation.finish() }
                    else { streamContinuation.finish(throwing: CommandFailed(exitCode: status)) }
                } else if case .pty = mode {
                    // Parent-channel shutdown can race its isConnected flag.
                    // Missing exit status is not a user typing exit/logout.
                    streamContinuation.finish(throwing: PTYClosedWithoutExit())
                } else {
                    streamContinuation.finish()
                }""")
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
        "        mode: CommandMode,\n        paced: Bool = false,\n        ptyCommand: String? = nil\n    ) async throws -> (channel: Channel, output:")
    replace_once(tty,
        "                channel.pipeline.addHandlers(handler)",
        """                channel.pipeline.addHandlers(handler).flatMap {
                    channel.setOption(ChannelOptions.autoRead, value: !paced)
                }""")
    replace_once(tty,
        "            mode: .pty(request)\n",
        "            mode: .pty(request), paced: true, ptyCommand: command\n")
    replace_once(tty,
        """    public func withPTY(
        _ request: SSHChannelRequestEvent.PseudoTerminalRequest,
        environment:""",
        """    public func withPTY(
        _ request: SSHChannelRequestEvent.PseudoTerminalRequest,
        command: String? = nil,
        environment:""")
    replace_once(tty,
        """        case .pty(let request):
            try await channel.triggerUserOutboundEvent(request)
            fallthrough""",
        """        case .pty(let request):
            try await channel.triggerUserOutboundEvent(request)
            if let command = ptyCommand {
                // SSH exec starts inside the PTY without ever entering
                // the interactive shell's echo, scrollback or history.
                try await channel.triggerUserOutboundEvent(SSHChannelRequestEvent.ExecRequest(
                    command: command, wantReply: true
                ))
            } else {
                try await channel.triggerUserOutboundEvent(SSHChannelRequestEvent.ShellRequest(
                    wantReply: true
                ))
            }""")
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
                // A successful stream already carried exit-status zero;
                // sshd may have closed its child before our cleanup runs.
                try? await close()
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
    # Keep the handshake deadline separate from interactive host-key approval.
    text = session.read_text()
    start = text.index("final class ClientHandshakeHandler:")
    end = text.index("\npublic struct SSHClientSettings:", start)
    handler = Path(__file__).with_name("citadel_handshake.swift").read_text().rstrip()
    prefix = handler[:handler.index("final class ClientHandshakeHandler:")]
    while prefix and text[:start].endswith(prefix):
        start -= len(prefix)
    write_source(session, text[:start] + handler + "\n" + text[end:])
    replace_once(session,
        """            loginTimeout: .seconds(10)
        )
        var clientConfiguration = SSHClientConfiguration(
            userAuthDelegate: settings.authenticationMethod(),
            serverAuthDelegate: settings.hostKeyValidator""",
        """            loginTimeout: .seconds(30)
        )
        var clientConfiguration = SSHClientConfiguration(
            userAuthDelegate: settings.authenticationMethod(),
            serverAuthDelegate: HandshakeHostKeyValidator(base: settings.hostKeyValidator, handshake: handshakeHandler)""")
    sftp_client = checkouts / "Citadel/Sources/Citadel/SFTP/Client/SFTPClient.swift"
    text = sftp_client.read_text()
    request_start = text.index("    internal func sendRequest(_ request: SFTPRequest) async throws -> SFTPResponse {")
    request_end = text.index("\n    /// Set the attributes of a file", request_start)
    request = Path(__file__).with_name("citadel_sftp_request.swift").read_text().rstrip()
    text = text[:request_start] + request + "\n" + text[request_end:]
    start = text.index("    public func openSFTP(\n")
    end = text.index("\n}\n\n/// A tracker for in-flight SFTP requests.", start)
    opening = Path(__file__).with_name("citadel_sftp_open.swift").read_text().rstrip()
    write_source(sftp_client, text[:start] + opening + text[end:])
    replace_once(sftp_client,
        "    fileprivate init(channel: Channel, responses: SFTPResponses, logger: Logger) {",
        "    init(channel: Channel, responses: SFTPResponses, logger: Logger) {")
    sftp_inbound = checkouts / "Citadel/Sources/Citadel/SFTP/Client/SFTPClientInboundHandler.swift"
    replace_once(sftp_inbound,
        "    func channelRead(context: ChannelHandlerContext, data: NIOAny) {",
        """    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is ChannelFailureEvent {
            // A rejected subsystem may leave the SSH child open. Surface
            // its refusal immediately instead of waiting forever for VERSION.
            responses.sftpVersion.fail(CitadelError.channelFailure)
            context.close(promise: nil)
        } else {
            context.fireUserInboundEventTriggered(event)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {""")
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
    replace_once(session,
        """                handshakeHandler.authenticated
            }.flatMap {""",
        """                handshakeHandler.authenticated.flatMapError { error in
                    // A refused key or failed login must not leave an
                    // unowned authenticated TCP socket alive.
                    channel.close().flatMapError { _ in
                        channel.eventLoop.makeSucceededVoidFuture()
                    }.flatMapThrowing { throw error }
                }
            }.flatMap {""")

    nio = checkouts / "swift-nio-ssh/Sources/NIOSSH/NIOSSHHandler.swift"
    signature = checkouts / "swift-nio-ssh/Sources/NIOSSH/Keys And Signatures/NIOSSHSignature.swift"
    # GHSA-998x-vgvp-xwpc / CVE-2026-43798. Backport upstream
    # 31cdc3c3391a10460dedf1170530cf651d2ca496 to the pinned fork:
    # hostile KEX signatures are parsed before host-key verification.
    replace_once(signature,
        "    private init(r: ByteBuffer, s: ByteBuffer, pointSize: Int) {",
        "    private init(r: ByteBuffer, s: ByteBuffer, pointSize: Int) throws {")
    replace_once(signature,
        """        let sByteView = s.mpIntView

        let rByteStartingOffset = pointSize - rByteView.count""",
        """        let sByteView = s.mpIntView

        guard rByteView.count <= pointSize, sByteView.count <= pointSize else {
            throw NIOSSHError.invalidSSHMessage(reason: "ECDSA signature mpint exceeds curve point size")
        }

        let rByteStartingOffset = pointSize - rByteView.count""")
    replace_once(signature,
        "        let helper = ECDSASignatureHelper(r: r, s: s, pointSize: Signature.pointSize)",
        "        let helper = try ECDSASignatureHelper(r: r, s: s, pointSize: Signature.pointSize)")
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
    patch_terminal_security(checkouts)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("checkouts", type=Path)
    patch(parser.parse_args().checkouts)
    print("Pinned dependency patches applied")
