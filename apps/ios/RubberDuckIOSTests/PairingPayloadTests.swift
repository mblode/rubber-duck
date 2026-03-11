import Testing
@testable import RubberDuckIOS

@Suite("PairingPayload parsing")
struct PairingPayloadTests {
    @Test("Parses valid JSON with host and token")
    func validJSON() throws {
        let json = #"{"host":"linktree","token":"abc123"}"#
        let payload = try PairingPayload.parse(json)
        #expect(payload.host == "linktree")
        #expect(payload.token == "abc123")
        #expect(payload.displayName == nil)
    }

    @Test("Parses JSON with displayName")
    func jsonWithDisplayName() throws {
        let json = #"{"host":"192.168.1.5","token":"xyz","displayName":"My Mac"}"#
        let payload = try PairingPayload.parse(json)
        #expect(payload.host == "192.168.1.5")
        #expect(payload.token == "xyz")
        #expect(payload.displayName == "My Mac")
    }

    @Test("Parses JSON with name fallback for displayName")
    func jsonWithNameFallback() throws {
        let json = #"{"host":"mac","token":"tok","name":"Studio"}"#
        let payload = try PairingPayload.parse(json)
        #expect(payload.displayName == "Studio")
    }

    @Test("Parses URL format with query params")
    func urlFormat() throws {
        let url = "rubberduck://pair?host=linktree&token=abc123"
        let payload = try PairingPayload.parse(url)
        #expect(payload.host == "linktree")
        #expect(payload.token == "abc123")
    }

    @Test("Parses URL format with displayName query param")
    func urlWithDisplayName() throws {
        let url = "rubberduck://pair?host=mac&token=tok&displayName=MacBook"
        let payload = try PairingPayload.parse(url)
        #expect(payload.displayName == "MacBook")
    }

    @Test("Invalid payload throws error")
    func invalidPayload() {
        #expect(throws: (any Error).self) {
            try PairingPayload.parse("not a valid payload")
        }
    }

    @Test("URL missing host throws error")
    func missingHost() {
        #expect(throws: (any Error).self) {
            try PairingPayload.parse("rubberduck://pair?token=abc")
        }
    }

    @Test("URL missing token throws error")
    func missingToken() {
        #expect(throws: (any Error).self) {
            try PairingPayload.parse("rubberduck://pair?host=mac")
        }
    }
}
