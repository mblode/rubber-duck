import Foundation
import Network

// MARK: - DaemonConnectionState

enum DaemonConnectionState {
    case disconnected
    case connecting
    case connected
}

// MARK: - DaemonSocketClient

/// Lightweight NDJSON client that connects to the CLI daemon's Unix domain socket.
/// Runs exclusively on MainActor. Tolerates daemon absence — connection failures
/// set state to `.disconnected` without throwing.
@MainActor
final class DaemonSocketClient {

    // MARK: - Error

    enum ClientError: Error, LocalizedError {
        case daemonUnavailable
        case timeout
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .daemonUnavailable:
                return "RubberDuck daemon is not running. Start it with `duck [path]`."
            case .timeout:
                return "Daemon request timed out."
            case .requestFailed(let message):
                return message
            }
        }
    }

    // MARK: - Properties

    private(set) var connectionState: DaemonConnectionState = .disconnected
    var isConnected: Bool { connectionState == .connected }

    /// Called on MainActor when a pushed event (no request id) arrives from the daemon.
    var onEvent: (([String: Any]) -> Void)?

    /// Called on MainActor when a previously-established connection drops unexpectedly.
    var onDisconnect: (() -> Void)?

    /// Called on MainActor when a connection becomes ready.
    var onConnect: (() -> Void)?

    private var connection: NWConnection?
    private var connectContinuations: [CheckedContinuation<Void, Never>] = []
    private var connectTimeoutWorkItem: DispatchWorkItem?
    private var pendingRequests: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var pendingTimeouts: [String: DispatchWorkItem] = [:]
    private var receiveBuffer = Data()
    private let socketPath: String
    private let timeoutSeconds: Double

    // MARK: - Init

    init(socketPath: String, timeoutSeconds: Double = 10) {
        self.socketPath = socketPath
        self.timeoutSeconds = timeoutSeconds
    }

    // MARK: - Connection

    /// Attempts to connect to the daemon socket.
    /// Silently succeeds or fails — never throws. Check `isConnected` after awaiting.
    func connect() async {
        switch connectionState {
        case .connected:
            return
        case .connecting:
            await withCheckedContinuation { [weak self] (continuation: CheckedContinuation<Void, Never>) in
                self?.connectContinuations.append(continuation)
            }
            return
        case .disconnected:
            break
        }

        connectionState = .connecting
        logDebug("DaemonSocketClient: Connecting to \(socketPath)")

        let conn = NWConnection(to: .unix(path: socketPath), using: .tcp)
        connection = conn

        await withCheckedContinuation { [weak self] (continuation: CheckedContinuation<Void, Never>) in
            guard let self else {
                continuation.resume()
                return
            }
            self.connectContinuations.append(continuation)
            let timeoutWorkItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                MainActor.assumeIsolated {
                    guard self.connectionState == .connecting, !self.connectContinuations.isEmpty else { return }
                    logDebug("DaemonSocketClient: Connection timed out for \(self.socketPath)")
                    self.connectionState = .disconnected
                    self.connection?.cancel()
                    self.connection = nil
                    self.resumeConnectContinuations()
                }
            }
            self.connectTimeoutWorkItem?.cancel()
            self.connectTimeoutWorkItem = timeoutWorkItem
            DispatchQueue.main.asyncAfter(deadline: .now() + self.timeoutSeconds, execute: timeoutWorkItem)
            conn.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    guard let self else { return }
                    MainActor.assumeIsolated {
                        self.handleConnectionState(state)
                    }
                }
            }
            conn.start(queue: .main)
        }
    }

    private func handleConnectionState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            let wasConnected = connectionState == .connected
            connectionState = .connected
            logDebug("DaemonSocketClient: Connected")
            resumeConnectContinuations()
            startReceiving()
            if !wasConnected {
                onConnect?()
            }

        case .failed(let error):
            guard !connectContinuations.isEmpty else {
                // Post-connect failure: clean up
                logDebug("DaemonSocketClient: Connection lost: \(error.localizedDescription)")
                disconnect()
                return
            }
            connectionState = .disconnected
            connection = nil
            logDebug("DaemonSocketClient: Connection failed: \(error.localizedDescription)")
            resumeConnectContinuations()

        case .cancelled:
            guard !connectContinuations.isEmpty else { return }
            if connectionState != .connected {
                connectionState = .disconnected
            }
            connection = nil
            resumeConnectContinuations()

        case .waiting(let error):
            logDebug("DaemonSocketClient: Connection waiting: \(error.localizedDescription)")

        default:
            break
        }
    }

    func disconnect() {
        logDebug("DaemonSocketClient: Disconnecting")
        let wasConnected = connectionState == .connected
        connectionState = .disconnected
        cancelConnectTimeout()
        resumeConnectContinuations()
        connection?.cancel()
        connection = nil
        receiveBuffer = Data()

        // Fail all pending requests
        let pending = pendingRequests
        let timeouts = pendingTimeouts
        pendingRequests = [:]
        pendingTimeouts = [:]
        for (_, workItem) in timeouts { workItem.cancel() }
        for (_, continuation) in pending {
            continuation.resume(throwing: ClientError.daemonUnavailable)
        }

        if wasConnected {
            onDisconnect?()
        }
    }

    private func resumeConnectContinuations() {
        cancelConnectTimeout()
        let continuations = connectContinuations
        connectContinuations.removeAll(keepingCapacity: true)
        for continuation in continuations {
            continuation.resume()
        }
    }

    private func cancelConnectTimeout() {
        connectTimeoutWorkItem?.cancel()
        connectTimeoutWorkItem = nil
    }

    // MARK: - Request/Response

    /// Sends a request to the daemon and awaits the response.
    /// Throws `ClientError.daemonUnavailable` if not connected, `ClientError.timeout` after `timeoutSeconds`.
    func request(method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        guard isConnected, let conn = connection else {
            throw ClientError.daemonUnavailable
        }

        let requestId = UUID().uuidString
        let msg: [String: Any] = ["id": requestId, "method": method, "params": params]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: msg, options: []) else {
            throw ClientError.requestFailed("Failed to serialize request")
        }
        var line = jsonData
        line.append(0x0A) // newline delimiter

        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(throwing: ClientError.daemonUnavailable)
                return
            }

            self.pendingRequests[requestId] = continuation

            // Schedule timeout
            let timeoutWork = DispatchWorkItem { [weak self] in
                guard let self else { return }
                MainActor.assumeIsolated {
                    guard let cont = self.pendingRequests.removeValue(forKey: requestId) else { return }
                    self.pendingTimeouts.removeValue(forKey: requestId)
                    logDebug("DaemonSocketClient: Request \(method) timed out")
                    cont.resume(throwing: ClientError.timeout)
                }
            }
            self.pendingTimeouts[requestId] = timeoutWork
            DispatchQueue.main.asyncAfter(deadline: .now() + self.timeoutSeconds, execute: timeoutWork)

            conn.send(content: line, completion: .contentProcessed({ _ in }))
        }
    }

    // MARK: - Receiving

    private func startReceiving() {
        guard let conn = connection else { return }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            DispatchQueue.main.async {
                guard let self else { return }
                MainActor.assumeIsolated {
                    if let data, !data.isEmpty {
                        self.receiveBuffer.append(data)
                        self.processBuffer()
                    }
                    if error != nil || isComplete {
                        logDebug("DaemonSocketClient: Connection closed by remote")
                        self.disconnect()
                    } else {
                        self.startReceiving()
                    }
                }
            }
        }
    }

    private func processBuffer() {
        while let newlineIdx = receiveBuffer.firstIndex(of: 0x0A) {
            let lineData = Data(receiveBuffer[receiveBuffer.startIndex..<newlineIdx])
            receiveBuffer = Data(receiveBuffer[receiveBuffer.index(after: newlineIdx)...])

            guard !lineData.isEmpty,
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }
            dispatch(json)
        }
    }

    private func dispatch(_ json: [String: Any]) {
        // Response: has "id" and "ok" fields
        if let requestId = json["id"] as? String,
           let ok = json["ok"] as? Bool {
            if let cont = pendingRequests.removeValue(forKey: requestId) {
                pendingTimeouts.removeValue(forKey: requestId)?.cancel()
                if ok {
                    cont.resume(returning: json["data"] as? [String: Any] ?? [:])
                } else {
                    let errMsg = json["error"] as? String ?? "Request failed"
                    cont.resume(throwing: ClientError.requestFailed(errMsg))
                }
            }
            return
        }

        // Pushed event
        onEvent?(json)
    }
}
