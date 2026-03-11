import Foundation

struct RuntimeSettings {
    let voice: String
    let model: String
    let autoAbortOnBargeIn: Bool
    let safeModeEnabled: Bool
}

enum RuntimeSettingsLoader {
    static func load(from defaults: UserDefaults) -> RuntimeSettings {
        let storedVoice = defaults.string(forKey: "voiceAgentVoice") ?? VoiceAgentVoice.marin.rawValue
        let voice: String
        if VoiceAgentVoice(rawValue: storedVoice) != nil {
            voice = storedVoice
        } else {
            voice = VoiceAgentVoice.marin.rawValue
            defaults.set(VoiceAgentVoice.marin.rawValue, forKey: "voiceAgentVoice")
            logError("RuntimeSettingsLoader: Invalid stored voice '\(storedVoice)', falling back to \(VoiceAgentVoice.marin.rawValue)")
        }

        let model = VoiceAgentModel.realtime.rawValue

        let autoAbortOnBargeIn: Bool
        if defaults.object(forKey: "autoAbortOnBargeIn") == nil {
            autoAbortOnBargeIn = true
        } else {
            autoAbortOnBargeIn = defaults.bool(forKey: "autoAbortOnBargeIn")
        }

        let safeModeEnabled = defaults.bool(forKey: "safeModeEnabled")

        return RuntimeSettings(
            voice: voice,
            model: model,
            autoAbortOnBargeIn: autoAbortOnBargeIn,
            safeModeEnabled: safeModeEnabled
        )
    }
}
