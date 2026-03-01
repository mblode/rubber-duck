//
//  AppComposer.swift
//  RubberDuck
//

import Foundation

@MainActor
struct AppManagers {
    let audioManager: AudioManager
    let hotkeyManager: HotkeyManager
    let configManager: AppConfigManager
    let updateManager: UpdateManager
    let playbackManager: AudioPlaybackManager
    let realtimeClient: RealtimeClient
    let workspaceManager: WorkspaceManager
    let voiceCoordinator: VoiceSessionCoordinator
    let daemonClient: DaemonSocketClient
}

@MainActor
enum AppComposer {
    private static let didRevealSettingsOnFirstLaunchKey = "didRevealSettingsOnFirstLaunch"

    static func buildManagers() -> AppManagers {
        logInfo("RubberDuckApp: Initializing")

        let audio = AudioManager()
        let transcription = AppConfigManager()
        let hotkey = HotkeyManager()
        let updater = UpdateManager()
        let playback = AudioPlaybackManager(audioManager: audio)
        let rtClient = RealtimeClient()
        let workspaces = WorkspaceManager()
        let daemonClient = DaemonSocketClient(socketPath: AppSupportPaths.daemonSocketURL().path)
        SettingsWindowController.shared.configure(
            configManager: transcription,
            audioManager: audio,
            updateManager: updater
        )

        let voiceCoord = VoiceSessionCoordinator(
            audioManager: audio,
            playbackManager: playback,
            realtimeClient: rtClient,
            daemonClient: daemonClient
        )
        hotkey.delegate = voiceCoord
        workspaces.onActiveWorkspaceChanged = { path in
            guard let path else { return }
            voiceCoord.setWorkspace(path)
        }
        workspaces.onActiveSessionChanged = { session in
            voiceCoord.setSession(session)
        }
        if let activeWorkspaceURL = workspaces.activeWorkspace?.url {
            voiceCoord.setWorkspace(activeWorkspaceURL)
        }
        voiceCoord.setSession(workspaces.activeSession)

        // When daemon drops, resume polling immediately (don't wait out the 5s suppression window)
        daemonClient.onDisconnect = { [weak workspaces] in
            workspaces?.clearDaemonPushSuppression()
        }
        daemonClient.onConnect = { [weak voiceCoord] in
            voiceCoord?.handleDaemonConnectionRestored()
        }

        // Route daemon push events to WorkspaceManager and VoiceSessionCoordinator
        daemonClient.onEvent = { [weak workspaces, weak voiceCoord] (event: [String: Any]) in
            guard let eventType = event["event"] as? String else { return }

            if eventType == "voice_session_changed",
               let data = event["data"] as? [String: Any],
               let workspacePath = data["workspacePath"] as? String {
                let sessionId = data["sessionId"] as? String
                let sessionName = data["sessionName"] as? String
                workspaces?.handleDaemonWorkspaceChanged(path: workspacePath, sessionId: sessionId, sessionName: sessionName)
            } else if eventType == "voice_say",
                      let data = event["data"] as? [String: Any],
                      let text = data["text"] as? String {
                voiceCoord?.sendTextMessage(text)
            }
        }

        // Start daemon connection in background (best-effort, non-blocking)
        Task {
            await daemonClient.connect()
            if daemonClient.isConnected {
                logInfo("RubberDuckApp: Connected to CLI daemon")
            } else {
                logDebug("RubberDuckApp: CLI daemon not running (voice tools will execute locally)")
            }
        }

        scheduleFirstLaunchSettingsRevealIfNeeded(configManager: transcription)

        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        logInfo("System: \(osVersion), App Version: \(appVersion)")

        return AppManagers(
            audioManager: audio,
            hotkeyManager: hotkey,
            configManager: transcription,
            updateManager: updater,
            playbackManager: playback,
            realtimeClient: rtClient,
            workspaceManager: workspaces,
            voiceCoordinator: voiceCoord,
            daemonClient: daemonClient
        )
    }

    private static func scheduleFirstLaunchSettingsRevealIfNeeded(configManager: AppConfigManager) {
        guard !AppEnvironment.isRunningTests else {
            return
        }

        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: didRevealSettingsOnFirstLaunchKey) == false else {
            return
        }

        guard configManager.getAPIKey() == nil || !configManager.setupGuideDismissed else {
            return
        }

        defaults.set(true, forKey: didRevealSettingsOnFirstLaunchKey)
        DispatchQueue.main.async {
            logInfo("RubberDuckApp: Revealing Settings on first launch for menu bar discoverability")
            SettingsWindowController.shared.show()
        }
    }
}
