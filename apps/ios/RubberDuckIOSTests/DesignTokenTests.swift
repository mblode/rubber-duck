import SwiftUI
import Testing
@testable import RubberDuckIOS

@Suite("Design tokens")
struct DesignTokenTests {
    @Test("Spacing constants are positive and follow 8pt grid")
    func spacingConstants() {
        let spacings: [CGFloat] = [
            Theme.spacing4,
            Theme.spacing8,
            Theme.spacing12,
            Theme.spacing16,
            Theme.spacing20,
            Theme.spacing24,
            Theme.spacing32,
        ]
        for spacing in spacings {
            #expect(spacing > 0)
        }
        #expect(Theme.spacing4 == 4)
        #expect(Theme.spacing8 == 8)
        #expect(Theme.spacing12 == 12)
        #expect(Theme.spacing16 == 16)
        #expect(Theme.spacing20 == 20)
        #expect(Theme.spacing24 == 24)
        #expect(Theme.spacing32 == 32)
    }

    @Test("Corner radii are positive")
    func cornerRadii() {
        #expect(Theme.cornerRadiusSmall > 0)
        #expect(Theme.cornerRadius > 0)
        #expect(Theme.cornerRadiusLarge > 0)
        #expect(Theme.cornerRadiusSmall < Theme.cornerRadius)
        #expect(Theme.cornerRadius < Theme.cornerRadiusLarge)
    }
}
