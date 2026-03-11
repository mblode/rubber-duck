import Foundation

private let defaultRemotePairingPort = 43_111

@MainActor
final class RemotePairingController: ObservableObject {
    @Published private(set) var status: RemotePairingStatus?
    @Published private(set) var pairingLink: String?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let daemonClient: DaemonSocketClient

    init(
        daemonClient: DaemonSocketClient? = nil
    ) {
        self.daemonClient = daemonClient ?? DaemonSocketClient(
            socketPath: AppSupportPaths.daemonSocketURL().path,
            timeoutSeconds: 10,
            connectTimeoutSeconds: 1.0
        )
    }

    func loadStatus() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await fetchStatus(includeToken: false)
            status = snapshot.status
            errorMessage = nil
        } catch {
            status = nil
            errorMessage = error.localizedDescription
        }
    }

    func preparePairing() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let initial = try await fetchStatus(includeToken: true)
            var nextStatus = initial.status
            var nextToken = initial.authToken

            if !nextStatus.enabled || !nextStatus.listening || nextToken == nil {
                let configured = try await configureRemote(
                    enabled: true,
                    host: "0.0.0.0",
                    rotateToken: nextToken == nil,
                    includeToken: true
                )
                nextStatus = configured.status
                nextToken = configured.authToken ?? nextToken

                if nextToken == nil {
                    let refreshed = try await fetchStatus(includeToken: true)
                    nextStatus = refreshed.status
                    nextToken = refreshed.authToken
                }
            }

            status = nextStatus
            pairingLink = buildPairingLink(status: nextStatus, token: nextToken)
            errorMessage = nextToken == nil
                ? "Pairing token is unavailable. Try again or run `duck remote pair`."
                : nil
        } catch {
            status = nil
            pairingLink = nil
            errorMessage = error.localizedDescription
        }
    }

    private func buildPairingLink(status: RemotePairingStatus, token: String?) -> String? {
        guard let token, !token.isEmpty else {
            return nil
        }

        let publicURL = resolvePublicURL(from: status)
        guard let publicURL else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "rubberduck"
        components.host = "pair"
        components.queryItems = [
            URLQueryItem(name: "host", value: publicURL),
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "displayName", value: Host.current().localizedName ?? "Rubber Duck Mac"),
        ]
        return components.string
    }

    private func resolvePublicURL(from status: RemotePairingStatus) -> String? {
        if let httpURL = status.httpURL,
           let url = URL(string: httpURL),
           let host = url.host,
           !Self.isLoopbackHost(host) {
            let absoluteString = url.absoluteString
            return absoluteString.hasSuffix("/")
                ? String(absoluteString.dropLast())
                : absoluteString
        }

        let hostname = Host.current().localizedName
            ?? ProcessInfo.processInfo.hostName
        guard !hostname.isEmpty else {
            return nil
        }

        return "http://\(hostname):\(status.port)"
    }

    private func connectIfNeeded() async {
        if !daemonClient.isConnected {
            await daemonClient.connect()
        }
    }

    private func fetchStatus(includeToken: Bool) async throws -> RemotePairingSnapshot {
        await connectIfNeeded()

        let data = try await daemonClient.request(
            method: "remote_status",
            params: ["includeToken": includeToken]
        )

        guard let statusData = data["status"] as? [String: Any] else {
            throw DaemonSocketClient.ClientError.requestFailed(
                "Daemon returned an invalid remote status payload."
            )
        }

        return RemotePairingSnapshot(
            status: try RemotePairingStatus(json: statusData),
            authToken: data["authToken"] as? String
        )
    }

    private func configureRemote(
        enabled: Bool?,
        host: String? = nil,
        rotateToken: Bool,
        includeToken: Bool
    ) async throws -> RemotePairingSnapshot {
        await connectIfNeeded()

        var params: [String: Any] = [
            "rotateToken": rotateToken,
            "includeToken": includeToken,
        ]
        if let enabled {
            params["enabled"] = enabled
        }
        if let host {
            params["host"] = host
        }

        let data = try await daemonClient.request(
            method: "remote_configure",
            params: params
        )

        guard let statusData = data["status"] as? [String: Any] else {
            throw DaemonSocketClient.ClientError.requestFailed(
                "Daemon returned an invalid remote pairing payload."
            )
        }

        return RemotePairingSnapshot(
            status: try RemotePairingStatus(json: statusData),
            authToken: data["authToken"] as? String
        )
    }

    private static func isLoopbackHost(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized == "127.0.0.1"
            || normalized == "0.0.0.0"
            || normalized == "localhost"
            || normalized == "::1"
    }
}

struct RemotePairingStatus {
    let enabled: Bool
    let listening: Bool
    let host: String
    let port: Int
    let httpURL: String?
    let tokenConfigured: Bool
    let tokenUpdatedAt: String?
    let lastError: String?

    init(json: [String: Any]) throws {
        guard let enabled = json["enabled"] as? Bool,
              let listening = json["listening"] as? Bool,
              let host = json["host"] as? String,
              let port = json["port"] as? Int,
              let tokenConfigured = json["tokenConfigured"] as? Bool else {
            throw DaemonSocketClient.ClientError.requestFailed(
                "Remote status payload is missing required fields."
            )
        }

        self.enabled = enabled
        self.listening = listening
        self.host = host
        self.port = port
        self.httpURL = json["httpUrl"] as? String
        self.tokenConfigured = tokenConfigured
        self.tokenUpdatedAt = json["tokenUpdatedAt"] as? String
        self.lastError = json["lastError"] as? String
    }
}

private struct RemotePairingSnapshot {
    let status: RemotePairingStatus
    let authToken: String?
}
