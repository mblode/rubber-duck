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

        let storedModel = defaults.string(forKey: "voiceAgentModel") ?? VoiceAgentModel.realtime.rawValue
        let model: String
        if VoiceAgentModel(rawValue: storedModel) != nil {
            model = storedModel
        } else {
            model = VoiceAgentModel.realtime.rawValue
            defaults.set(VoiceAgentModel.realtime.rawValue, forKey: "voiceAgentModel")
            logError("RuntimeSettingsLoader: Invalid stored model '\(storedModel)', falling back to \(VoiceAgentModel.realtime.rawValue)")
        }

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
