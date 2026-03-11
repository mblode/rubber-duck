import RubberDuckRemoteCore
import SwiftUI

struct SessionsTab: View {
    @EnvironmentObject private var appModel: RemoteDaemonAppModel

    var body: some View {
        Group {
            if appModel.sessions.isEmpty {
                EmptyStateView(
                    icon: "folder",
                    title: "No Sessions",
                    subtitle: "Run `duck [path]` on your Mac to attach a workspace and create a session."
                )
            } else {
                List {
                    ForEach(appModel.sessions) { session in
                        Button {
                            Task { await appModel.openSession(session) }
                        } label: {
                            SessionRow(
                                session: session,
                                isSelected: session.id == appModel.activeSession?.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    await appModel.refresh()
                }
            }
        }
    }
}
