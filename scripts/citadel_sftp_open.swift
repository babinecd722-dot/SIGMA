    public func openSFTP(
        logger: Logger = .init(label: "nl.orlandos.citadel.sftp")
    ) async throws -> SFTPClient {
        try await eventLoop.flatSubmit { [eventLoop, sshHandler = session.sshHandler] in
            let createChannel = eventLoop.makePromise(of: Channel.self)
            let createClient = eventLoop.makePromise(of: SFTPClient.self)
            let ready = eventLoop.makePromise(of: SFTPClient.self)

            // Bound the entire exchange, including the server's VERSION.
            // Failing an already-created channel promise does not wake a
            // caller suspended on VERSION (the upstream timeout did that).
            let deadline = eventLoop.scheduleTask(in: .seconds(15)) {
                ready.fail(SFTPError.missingResponse)
            }
            ready.futureResult.whenComplete { outcome in
                deadline.cancel()
                if case .failure = outcome {
                    // Only this child belongs to us; sibling terminals and
                    // transfers on the authenticated transport stay alive.
                    createChannel.futureResult.whenSuccess { channel in
                        channel.close(promise: nil)
                    }
                }
            }
            createChannel.futureResult.whenFailure { error in
                createClient.fail(error)
            }
            sshHandler.value.createChannel(createChannel) { channel, _ in
                SFTPClient.setupChannelHanders(channel: channel, logger: logger)
                    .map { client in createClient.succeed(client) }
            }

            let opening = createChannel.futureResult.flatMap { channel in
                createClient.futureResult.flatMap { client in
                    channel.triggerUserOutboundEvent(
                        SSHChannelRequestEvent.SubsystemRequest(subsystem: "sftp", wantReply: true)
                    ).flatMap {
                        channel.writeAndFlush(SFTPMessage.initialize(.init(version: .v3)))
                    }.flatMap {
                        client.responses.sftpVersion.futureResult
                    }.flatMapThrowing { serverVersion in
                        guard serverVersion.version == .v3 else {
                            throw SFTPError.unsupportedVersion(serverVersion.version)
                        }
                        logger.info("SFTP connection opened and ready")
                        return client
                    }
                }
            }
            opening.cascade(to: ready)
            return ready.futureResult
        }.get()
    }
