import RubberDuckRemoteCore
import SwiftUI

struct SessionsTab: View {
    @EnvironmentObject private var appModel: RemoteDaemonAppModel
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if appModel.sessions.isEmpty {
                    EmptyStateView(
                        icon: "folder",
                        title: "No Sessions",
                        subtitle: "Run `duck [path]` on your Mac to attach a workspace and create a session."
                    )
                } else if filteredSessions.isEmpty {
                    List {
                        ContentUnavailableView.search(text: searchText)
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
                    }
                    .listStyle(.insetGrouped)
                    .searchable(text: $searchText, prompt: "Search sessions")
                } else {
                    List {
                        if let activeSession = filteredActiveSession {
                            Section("Current") {
                                sessionButton(for: activeSession)
                            }
                        }

                        if !otherFilteredSessions.isEmpty {
                            Section(listSectionTitle) {
                                ForEach(otherFilteredSessions) { session in
                                    sessionButton(for: session)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        await appModel.refresh()
                    }
                    .searchable(text: $searchText, prompt: "Search sessions")
                }
            }
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await appModel.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
    }

    private var filteredSessions: [RemoteSessionSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return appModel.sessions
        }

        return appModel.sessions.filter { session in
            session.name.localizedCaseInsensitiveContains(query) ||
            session.workspacePath.localizedCaseInsensitiveContains(query)
        }
    }

    private var filteredActiveSession: RemoteSessionSummary? {
        guard let activeSession = appModel.activeSession else {
            return nil
        }

        return filteredSessions.first(where: { $0.id == activeSession.id })
    }

    private var otherFilteredSessions: [RemoteSessionSummary] {
        filteredSessions.filter { $0.id != filteredActiveSession?.id }
    }

    private var listSectionTitle: String {
        filteredActiveSession == nil ? "Sessions" : "Other Sessions"
    }

    @ViewBuilder
    private func sessionButton(for session: RemoteSessionSummary) -> some View {
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
