cask "rubber-duck" do
  version "0.1.0"
  sha256 "d4bbee645f0ab6f55042622e010d680e04b5f2bb8b93fe1674f2c1b7b2b83e20"

  url "https://github.com/mblode/rubber-duck/releases/download/v#{version}/RubberDuck-#{version}.dmg"
  name "Rubber Duck"
  desc "macOS menu bar dictation app using OpenAI transcription"
  homepage "https://github.com/mblode/rubber-duck"

  depends_on macos: ">= :sequoia"
  auto_updates true

  app "Rubber Duck.app"

  zap trash: [
    "~/Library/Preferences/co.blode.rubber-duck.plist",
    "~/Library/Application Support/co.blode.rubber-duck",
  ]
end
