import Foundation
import Citadel
import NIO
import NIOConcurrencyHelpers
import NIOSSH

/// One multiplexed SSH transport to a profile: terminals, SFTP and
/// forwards share the single connection. Reconnects are transparent.
actor SSHConnection {
    enum State: Sendable, Equatable {
        case offline, connecting, online
    }

    let profile: ServerProfile
    private(set) var state: State = .offline

    private var client: Citadel.SSHClient?
    /// Single in-flight connect: concurrent ensureConnected() callers
    /// share one handshake instead of racing duplicate transports.
    private var connectTask: Task<Citadel.SSHClient, Error>?
    /// Callers currently waiting on the shared handshake. A waiting
    /// consumer that goes away (tab closed mid-connect) only abandons
    /// its own wait — the handshake itself is cancelled once the last
    /// consumer leaves, so a sibling tab's close never orphans the
    /// transport others still need.
    private var connectConsumers: [Int: Int] = [:]
    /// Bumped by close()/markDisconnected()/a new attempt — a
    /// late-finishing handshake from an older generation is dropped
    /// instead of adopted, and its settle notification is ignored.
    private var generation = 0
    /// Single transport probe shared by every caller; cancelled on
    /// teardown and when the app backgrounds.
    private var probeTask: Task<Bool, Never>?
    /// Identifies the owning probe so a finishing probe never clears a
    /// newer one from the slot.
    private var probeSeq = 0

    private let authMethodFor: @Sendable (ServerProfile) async throws -> SSHAuthenticationMethod
    private let validatorFor: @Sendable (ServerProfile, Int) async -> NIOSSHClientServerAuthenticationDelegate
    private let bastionResolver: @Sendable (UUID) async throws -> SSHConnection
    private let onStateChange: @Sendable (State) -> Void
    /// Fired when the in-flight handshake ends for any reason (success,
    /// failure, cancellation). The engine uses it to retire host-key
    /// prompts that belong to a dead connect attempt.
    private let onConnectSettled: @Sendable (Int) -> Void

    init(
        profile: ServerProfile,
        authMethodFor: @escaping @Sendable (ServerProfile) async throws -> SSHAuthenticationMethod,
        validatorFor: @escaping @Sendable (ServerProfile, Int) async -> NIOSSHClientServerAuthenticationDelegate,
        bastionResolver: @escaping @Sendable (UUID) async throws -> SSHConnection,
        onStateChange: @escaping @Sendable (State) -> Void,
        onConnectSettled: @escaping @Sendable (Int) -> Void = { _ in }
    ) {
        self.profile = profile
        self.authMethodFor = authMethodFor
        self.validatorFor = validatorFor
        self.bastionResolver = bastionResolver
        self.onStateChange = onStateChange
        self.onConnectSettled = onConnectSettled
    }

    var isConnected: Bool { client?.isConnected == true }

    /// A handshake is in flight right now — a probe would only be
    /// measuring an unfinished connect, and tearing it down mid-prompt
    /// kills host-key/password asks that are legitimately waiting.
    func isCurrentAttempt(_ gen: Int) -> Bool {
        generation == gen && connectTask != nil
    }

    var isConnecting: Bool { connectTask != nil }

    private func setState(_ s: State) {
        state = s
        onStateChange(s)
    }

    @discardableResult
    func ensureConnected() async throws -> Citadel.SSHClient {
        if let client, client.isConnected { return client }
        if let connectTask {
            let adopted = try await awaitSharedConnect(connectTask, generation: generation)
            // The shared task can complete while the transport was
            // already being torn down — never hand back a dead client.
            guard adopted.isConnected, client === adopted else {
                throw CancellationError()
            }
            return adopted
        }

        generation += 1
        let gen = generation
        let task = Task<Citadel.SSHClient, Error> { [weak self] in
            guard let self else { throw CancellationError() }
            defer {
                Task { await self.connectDidSettle(gen) }
            }
            await self.setState(.connecting)
            do {
                let connected = try await self.performConnect(generation: gen)
                // Cancelled mid-handshake or superseded by a newer
                // generation: adopt nothing — the finished transport
                // would become an orphan.
                let adopted = await self.adopt(connected, generation: gen, cancelled: Task.isCancelled)
                if !adopted {
                    Task { try? await connected.close() }
                    throw CancellationError()
                }
                return connected
            } catch {
                await self.connectFailed(gen)
                throw error
            }
        }
        connectTask = task
        return try await awaitSharedConnect(task, generation: gen)
    }

    /// Awaits the shared handshake as a counted consumer. Cancellation
    /// of the caller abandons only this wait — `Task.value` ignores
    /// caller cancellation, so the wait is a continuation race instead:
    /// whoever fires first (handshake result or the cancellation
    /// handler) resumes it exactly once. The handshake task keeps
    /// running while anyone still needs it and is torn down when the
    /// last consumer leaves with nothing to show for it.
    private func awaitSharedConnect(_ task: Task<Citadel.SSHClient, Error>, generation gen: Int) async throws -> Citadel.SSHClient {
        connectConsumers[gen, default: 0] += 1
        defer { consumerLeft(gen) }
        let connected = try await cancellableValue(of: task)
        try Task.checkCancellation()
        guard gen == generation, connected.isConnected, client === connected else { throw CancellationError() }
        return connected
    }

    /// A consumer finished waiting (answered or cancelled). When nobody
    /// is left waiting on a still-running handshake that hasn't adopted
    /// a client yet, the transport nobody needs is torn down — closing
    /// one connecting tab must not break siblings, but a handshake no
    /// one wants must not linger either.
    private func consumerLeft(_ gen: Int) {
        let count = max(0, (connectConsumers[gen] ?? 1) - 1)
        connectConsumers[gen] = count == 0 ? nil : count
        guard gen == generation, count == 0, client == nil, let task = connectTask else { return }
        // Retire the attempt fully: the bumped generation marks its
        // settle stale so a late finish can't publish — but its
        // pending prompts belong to this dead attempt and retire now.
        generation += 1
        task.cancel()
        connectTask = nil
        onConnectSettled(gen)
    }

    /// Called on the actor when a shared handshake task ends. A settle
    /// from an older generation belongs to a dead attempt — it must not
    /// clear a newer connect task or cancel newer prompts.
    private func connectDidSettle(_ gen: Int) {
        guard gen == generation else { return }
        connectTask = nil
        onConnectSettled(gen)
    }

    private func adopt(_ connected: Citadel.SSHClient, generation gen: Int, cancelled: Bool) -> Bool {
        guard gen == generation, !cancelled else { return false }
        client = connected
        // Transport dropped underneath us (network loss, server kill):
        // surface it instead of leaving a half-dead client adopted.
        connected.onDisconnect { [weak self, weak connected] in
            Task { await self?.transportDropped(connected) }
        }
        setState(.online)
        return true
    }

    /// A failed/cancelled attempt publishes offline only while it is
    /// still the current one — a stale task can never overwrite a
    /// newer attempt's connecting state.
    private func connectFailed(_ gen: Int) {
        guard gen == generation else { return }
        setState(.offline)
    }

    /// The live channel closed without us asking — drop the client so
    /// the next ensureConnected() re-handshakes, and publish offline.
    private func transportDropped(_ dropped: Citadel.SSHClient?) {
        guard let dropped, client === dropped else { return }
        client = nil
        setState(.offline)
    }

    /// Citadel's authenticationMethod closure is synchronous, while reading
    /// keys/passwords is async (Keychain + biometry). The method is prepared
    /// inside the connect task so callers never re-authenticate against an
    /// already-live transport, and cleared right after the handshake so
    /// secrets aren't retained for the connection's lifetime.
    private func performConnect(generation gen: Int) async throws -> Citadel.SSHClient {
        let auth = try await authMethodFor(profile)
        try Task.checkCancellation()
        let validator = await validatorFor(profile, gen)
        try Task.checkCancellation()

        var settings = SSHClientSettings(
            host: profile.host,
            port: profile.port,
            authenticationMethod: { auth },
            hostKeyValidator: .custom(validator)
        )
        // Strict crypto posture: the bundled algorithm set is already the
        // allowlist we want — AES256/128-GCM transport, ECDH + Curve25519
        // KEX, ed25519/ECDSA host keys. Citadel's `.all` would re-add
        // AES-CTR, group14-sha1 and ssh-rsa — deliberately not used.
        settings.connectTimeout = .seconds(12)

        if let jumpID = profile.jumpProfileID {
            let bastion = try await bastionResolver(jumpID)
            let hop = try await bastion.ensureConnected()
            return try await hop.jump(to: settings)
        }
        return try await SSHClient.connect(to: settings)
    }

    /// Opens a channel on the live transport; only a reused transport that
    /// turned out half-dead is dropped and retried once — failures on a
    /// fresh handshake (auth, host key, channel limits) surface as-is.
    /// A channel-level failure (open refusal, exec timeout, SFTP channel
    /// EOF) surfaces typed and leaves the pooled transport alone: other
    /// tabs and services still share it.
    private func withTransport<T>(_ work: (Citadel.SSHClient) async throws -> T) async throws -> T {
        let reused = client?.isConnected == true
        do {
            return try await work(ensureConnected())
        } catch {
            guard reused, !(error is CancellationError),
                  Self.isTransportFailure(error) else { throw error }
            await markDisconnected()
            return try await work(ensureConnected())
        }
    }

    /// Transport-death errors only: the TCP layer closed under the work
    /// or SSH reported the transport itself gone. Channel-level refusals
    /// (`channelSetupRejected`, `CommandFailed`, `channelCreationFailed`,
    /// `globalRequestRefused`) are deliberately absent — they must never
    /// poison the shared transport.
    private static func isTransportFailure(_ error: Error) -> Bool {
        switch error {
        case is ChannelError:
            // NIOSSH fails *child-channel* promises with ChannelError
            // too (.eof on channel close, .ioOnClosedChannel) — the two
            // are indistinguishable from the error alone, and a channel
            // error must never invalidate the shared transport. Genuine
            // TCP death arrives via onDisconnect → transportDropped or
            // as IOError/NIOSSHError instead.
            return false
        case let ssh as NIOSSHError:
            switch ssh.type {
            case .tcpShutdown, .creatingChannelAfterClosure,
                 .flowControlViolation, .protocolViolation:
                return true
            default:
                return false
            }
        case let io as IOError:
            switch io.errnoCode {
            case EPIPE, ECONNRESET, ECONNABORTED, ENOTCONN, ETIMEDOUT,
                 EHOSTDOWN, EHOSTUNREACH, ENETDOWN, ENETRESET, ENETUNREACH:
                return true
            default:
                return false
            }
        default:
            return false
        }
    }

    // MARK: - Channels

    func openShell(cols: Int, rows: Int, command: String? = nil) async throws -> ShellChannel {
        try await withTransport { client in
            let shell = ShellChannel()
            try await shell.open(on: client, cols: cols, rows: rows, command: command)
            return shell
        }
    }

    func openSFTP() async throws -> Citadel.SFTPClient {
        try await withTransport { try await $0.openSFTP() }
    }

    func execute(_ command: String) async throws -> String {
        let buffer = try await withTransport { client in
            // Exec channels can hang forever on a half-dead transport —
            // a deadline keeps the answer (and the caller) honest.
            try await withTimeout(.seconds(15)) {
                try await client.executeCommand(command, inShell: false)
            }
        }
        return String(buffer: buffer)
    }

    /// An SSH-level heartbeat proves a live peer without allocating an
    /// exec channel or interpreting a channel refusal as transport death.
    /// Concurrent callers share one in-flight probe per transport.
    func probe() async -> Bool {
        if let probeTask { return await probeTask.value }
        guard let client, client.isConnected else { return false }
        probeSeq += 1
        let seq = probeSeq
        let task = Task<Bool, Never> {
            do {
                try await withTimeout(.seconds(8)) {
                    try await client.sendKeepAlive()
                }
                return true
            } catch {
                return false
            }
        }
        probeTask = task
        let answer = await task.value
        // A newer probe (or cancelProbe) may already own the slot —
        // only the sequence owner clears it.
        guard probeSeq == seq else { return true }
        probeTask = nil
        return answer
    }

    /// Abandons an in-flight probe (backgrounding, teardown) — the exec
    /// channel dies with its task instead of holding a socket open.
    func cancelProbe() {
        probeSeq += 1
        probeTask?.cancel()
        probeTask = nil
    }

    /// Real deadline: the continuation is resumed by whichever lands
    /// first — the work result or the timeout — and the losing branch
    /// is abandoned, not awaited. (A task-group race would still wait
    /// for a stubborn child at scope exit, silently voiding the
    /// deadline.) The work task is cancelled when the race ends.
    private func withTimeout<T: Sendable>(_ timeout: Duration, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withOperationTimeout(timeout, work)
    }

    func close() async {
        let gen = generation
        generation += 1
        cancelProbe()
        connectTask?.cancel()
        connectTask = nil
        connectConsumers.removeAll()
        try? await client?.close()
        client = nil
        setState(.offline)
        onConnectSettled(gen)
    }

    func markDisconnected() {
        let gen = generation
        generation += 1
        let old = client
        client = nil
        cancelProbe()
        connectTask?.cancel()
        connectTask = nil
        connectConsumers.removeAll()
        setState(.offline)
        onConnectSettled(gen)
        if let old {
            Task { try? await old.close() }
        }
    }
}
