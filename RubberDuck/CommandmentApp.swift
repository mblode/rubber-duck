//
//  RubberDuckApp.swift
//  RubberDuck
//
//  Created by Matthew Blode.
//

import AppKit
import SwiftUI

@main
struct RubberDuckApp: App {
    private static let didRevealSettingsOnFirstLaunchKey = "didRevealSettingsOnFirstLaunch"

    @StateObject private var audioManager: AudioManager
    @StateObject private var hotkeyManager: HotkeyManager
    @StateObject private var transcriptionManager: TranscriptionManager
    @StateObject private var updateManager: UpdateManager
    @StateObject private var voiceCoordinator: VoiceSessionCoordinator
    @StateObject private var playbackManager: AudioPlaybackManager
    @StateObject private var workspaceManager: WorkspaceManager

    // Initialize Logger early
    private let logger = Logger.shared
    private static let menuBarLogoImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "logo", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }

        // Template icons adapt correctly to light/dark menu bar appearances.
        image.isTemplate = true
        image.size = NSSize(width: 20, height: 18)
        return image
    }()

    init() {
        logInfo("RubberDuckApp: Initializing")

        // Create managers first
        let audio = AudioManager()
        let transcription = TranscriptionManager()
        let hotkey = HotkeyManager()
        let updater = UpdateManager()
        let playback = AudioPlaybackManager()
        let rtClient = RealtimeClient()
        rtClient.instructions = SystemPrompt.voiceCodingAssistant
        let workspaces = WorkspaceManager()
        SettingsWindowController.shared.configure(
            transcriptionManager: transcription,
            audioManager: audio,
            updateManager: updater
        )

        // Initialize coordinator with the same instances
        let voiceCoord = VoiceSessionCoordinator(
            audioManager: audio,
            playbackManager: playback,
            realtimeClient: rtClient
        )
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

        // Now create the StateObjects
        _audioManager = StateObject(wrappedValue: audio)
        _hotkeyManager = StateObject(wrappedValue: hotkey)
        _transcriptionManager = StateObject(wrappedValue: transcription)
        _updateManager = StateObject(wrappedValue: updater)
        _voiceCoordinator = StateObject(wrappedValue: voiceCoord)
        _playbackManager = StateObject(wrappedValue: playback)
        _workspaceManager = StateObject(wrappedValue: workspaces)

        scheduleFirstLaunchSettingsRevealIfNeeded(transcriptionManager: transcription)

        // Log system info
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        logInfo("System: \(osVersion), App Version: \(appVersion)")
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(audioManager: audioManager,
                       hotkeyManager: hotkeyManager,
                       transcriptionManager: transcriptionManager,
                       updateManager: updateManager,
                       workspaceManager: workspaceManager)
        } label: {
            menuBarIcon
        }

        Settings {
            SettingsView()
                .environmentObject(transcriptionManager)
                .environmentObject(audioManager)
                .environmentObject(updateManager)
        }
    }

    private var menuBarIcon: Image {
        if let logoImage = Self.menuBarLogoImage {
            return Image(nsImage: logoImage)
        }
        return Image(systemName: "mic.fill")
    }

    private func scheduleFirstLaunchSettingsRevealIfNeeded(transcriptionManager: TranscriptionManager) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Self.didRevealSettingsOnFirstLaunchKey) == false else {
            return
        }

        // The app can be hidden behind menu bar overflow/hidden-menu utilities.
        // Reveal Settings once so first-time users always get a visible entry point.
        guard transcriptionManager.getAPIKey() == nil || !transcriptionManager.setupGuideDismissed else {
            return
        }

        defaults.set(true, forKey: Self.didRevealSettingsOnFirstLaunchKey)
        DispatchQueue.main.async {
            logInfo("RubberDuckApp: Revealing Settings on first launch for menu bar discoverability")
            SettingsWindowController.shared.show()
        }
    }
}
