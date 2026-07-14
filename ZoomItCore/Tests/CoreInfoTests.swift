import Testing
import ZoomItCore

struct CoreInfoTests {
    @Test func versionIsSet() {
        #expect(CoreInfo.version == "0.1.0")
    }
}
