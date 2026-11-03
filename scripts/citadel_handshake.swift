// Injected into the pinned Citadel ClientSession.swift by patch_dependencies.py.
final class ClientHandshakeHandler: ChannelInboundHandler, Sendable {
    typealias InboundIn = Any

    private struct DeadlineState {
        var timer: Scheduled<Void>?
        var finished = false
        var paused = false
    }
    private let deadline = NIOLockedValueBox(DeadlineState())
    private let promise: EventLoopPromise<Void>
    private let eventLoop: EventLoop
    private let loginTimeout: TimeAmount
    let logger = Logger(label: "nl.orlandos.citadel.handshake")

    public var authenticated: EventLoopFuture<Void> { promise.futureResult }

    init(eventLoop: EventLoop, loginTimeout: TimeAmount) {
        self.eventLoop = eventLoop
        self.loginTimeout = loginTimeout
        promise = eventLoop.makePromise(of: Void.self)
        promise.futureResult.whenComplete { [deadline] _ in
            deadline.withLockedValue {
                $0.finished = true
                $0.timer?.cancel()
                $0.timer = nil
            }
        }
        resumeTimeout()
    }

    func pauseTimeout() {
        deadline.withLockedValue {
            $0.paused = true
            $0.timer?.cancel()
            $0.timer = nil
        }
    }

    func resumeTimeout() {
        deadline.withLockedValue { $0.paused = false }
        eventLoop.execute { [deadline, eventLoop, loginTimeout, promise] in
            deadline.withLockedValue { state in
                guard !state.finished, !state.paused else { return }
                state.timer?.cancel()
                state.timer = eventLoop.scheduleTask(in: loginTimeout) {
                    promise.fail(ChannelError.connectTimeout(loginTimeout))
                }
            }
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is UserAuthSuccessEvent { promise.succeed(()) }
        context.fireUserInboundEventTriggered(event)
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        promise.fail(error)
    }

    func channelInactive(context: ChannelHandlerContext) {
        promise.fail(ChannelError.eof)
        context.fireChannelInactive()
    }

    deinit {
        struct Disconnected: Error {}
        promise.fail(Disconnected())
    }
}

/// Human approval is outside the network deadline. Both the key-exchange
/// before validation and authentication after it remain time bounded.
private struct HandshakeHostKeyValidator: NIOSSHClientServerAuthenticationDelegate, Sendable {
    let base: SSHHostKeyValidator
    let handshake: ClientHandshakeHandler

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        handshake.pauseTimeout()
        let decision = validationCompletePromise.futureResult.eventLoop.makePromise(of: Void.self)
        decision.futureResult.whenComplete { result in
            handshake.resumeTimeout()
            validationCompletePromise.completeWith(result)
        }
        base.validateHostKey(hostKey: hostKey, validationCompletePromise: decision)
    }
}
