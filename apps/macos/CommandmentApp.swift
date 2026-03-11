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
    @StateObject private var audioManager: AudioManager
    @StateObject private var hotkeyManager: HotkeyManager
    @StateObject private var configManager: AppConfigManager
    @StateObject private var updateManager: UpdateManager
    @StateObject private var voiceCoordinator: VoiceSessionCoordinator
    @StateObject private var playbackManager: AudioPlaybackManager
    @StateObject private var workspaceManager: WorkspaceManager

    private let logger = Logger.shared
    private static let menuBarLogoImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "logo", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = true
        image.size = NSSize(width: 20, height: 18)
        return image
    }()

    init() {
        let managers = AppComposer.buildManagers()
        _audioManager = StateObject(wrappedValue: managers.audioManager)
        _hotkeyManager = StateObject(wrappedValue: managers.hotkeyManager)
        _configManager = StateObject(wrappedValue: managers.configManager)
        _updateManager = StateObject(wrappedValue: managers.updateManager)
        _voiceCoordinator = StateObject(wrappedValue: managers.voiceCoordinator)
        _playbackManager = StateObject(wrappedValue: managers.playbackManager)
        _workspaceManager = StateObject(wrappedValue: managers.workspaceManager)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(audioManager: audioManager,
                       hotkeyManager: hotkeyManager,
                       configManager: configManager,
                       workspaceManager: workspaceManager)
        } label: {
            menuBarIcon
        }

        Settings {
            SettingsView()
                .environmentObject(configManager)
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
}
