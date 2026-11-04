    internal func sendRequest(_ request: SFTPRequest) async throws -> SFTPResponse {
        try await self.eventLoop.flatSubmit {
            let requestId = request.requestId
            let promise = self.channel.eventLoop.makePromise(of: SFTPResponse.self)
            assert(self.responses.responses[requestId] == nil,
                   "Attempt to send request with request ID \(requestId) already in flight.")
            self.responses.responses[requestId] = promise

            // An accepted subsystem can still stop answering REALPATH,
            // READDIR, READ or WRITE. Bound each request, including a
            // stalled write, rather than leaving its caller suspended.
            let deadline = self.eventLoop.scheduleTask(in: .seconds(30)) {
                guard let pending = self.responses.responses.removeValue(forKey: requestId) else { return }
                pending.fail(SFTPError.missingResponse)
                // A timed-out SFTP child cannot safely serve its remaining
                // requests. Close that child only; SSH terminals and other
                // channels on the authenticated transport remain alive.
                self.channel.close(promise: nil)
            }
            promise.futureResult.whenComplete { _ in deadline.cancel() }

            let message = request.makeMessage()
            self.logger.trace("SFTP OUT: \(message.debugDescription)")
            self.channel.writeAndFlush(message).whenFailure { error in
                self.responses.responses.removeValue(forKey: requestId)?.fail(error)
                self.channel.close(promise: nil)
            }
            return promise.futureResult
        }.get()
    }
