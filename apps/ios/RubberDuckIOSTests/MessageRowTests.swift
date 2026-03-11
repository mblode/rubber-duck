import RubberDuckRemoteCore
import Testing
@testable import RubberDuckIOS

@Suite("MessageRow role mapping")
struct MessageRowTests {
    @Test("User role", arguments: [RemoteConversationRole.user])
    func userRole(role: RemoteConversationRole) {
        let entry = TestFixtures.makeEntry(role: role)
        let row = MessageRow(entry: entry)
        #expect(row.roleTitle == "You")
        #expect(row.roleIcon == "person.fill")
    }

    @Test("Assistant role", arguments: [RemoteConversationRole.assistant])
    func assistantRole(role: RemoteConversationRole) {
        let entry = TestFixtures.makeEntry(role: role)
        let row = MessageRow(entry: entry)
        #expect(row.roleTitle == "Duck")
        #expect(row.roleIcon == "cpu")
    }

    @Test("Tool role", arguments: [RemoteConversationRole.tool])
    func toolRole(role: RemoteConversationRole) {
        let entry = TestFixtures.makeEntry(role: role)
        let row = MessageRow(entry: entry)
        #expect(row.roleTitle == "Tool")
        #expect(row.roleIcon == "wrench.fill")
    }

    @Test("Status role", arguments: [RemoteConversationRole.status])
    func statusRole(role: RemoteConversationRole) {
        let entry = TestFixtures.makeEntry(role: role)
        let row = MessageRow(entry: entry)
        #expect(row.roleTitle == "Status")
        #expect(row.roleIcon == "info.circle")
    }
}
