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
        rtClient.instructions = SystemPrompt.voiceCodingAssistant
        let workspaces = WorkspaceManager()
        SettingsWindowController.shared.configure(
            configManager: transcription,
            audioManager: audio,
            updateManager: updater
        )

        let voiceCoord = VoiceSessionCoordinator(
            audioManager: audio,
            playbackManager: playback,
            realtimeClient: rtClient
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
            voiceCoordinator: voiceCoord
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
