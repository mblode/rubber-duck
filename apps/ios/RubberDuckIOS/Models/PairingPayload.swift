import Foundation
import RubberDuckRemoteCore

struct PairingPayload: Decodable {
    let host: String
    let token: String
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case host
        case token
        case displayName
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decode(String.self, forKey: .host)
        token = try container.decode(String.self, forKey: .token)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? container.decodeIfPresent(String.self, forKey: .name)
    }

    static func parse(_ value: String) throws -> PairingPayload {
        if let data = value.data(using: .utf8),
           let payload = try? JSONDecoder().decode(PairingPayload.self, from: data) {
            return payload
        }

        guard let components = URLComponents(string: value),
              let host = components.queryItem(named: "host"),
              let token = components.queryItem(named: "token") else {
            throw RemoteDaemonError.messageFailed(
                "The QR code is not a valid Rubber Duck pairing payload."
            )
        }

        return PairingPayload(
            host: host,
            token: token,
            displayName: components.queryItem(named: "displayName")
                ?? components.queryItem(named: "name")
        )
    }

    private init(host: String, token: String, displayName: String?) {
        self.host = host
        self.token = token
        self.displayName = displayName
    }
}

private extension URLComponents {
    func queryItem(named name: String) -> String? {
        queryItems?.first(where: { $0.name == name })?.value
    }
}
