import AVFoundation
import Testing

@testable import AimFind

struct CameraGateTests {
    @Test func noCameraWinsOverAuthorization() {
        #expect(CameraGate.outcome(hasCamera: false, status: .authorized) == .noCamera)
    }

    @Test func authorizedOpensCamera() {
        #expect(CameraGate.outcome(hasCamera: true, status: .authorized) == .ready)
    }

    @Test func notDeterminedIsLeftToSystemPrompt() {
        #expect(CameraGate.outcome(hasCamera: true, status: .notDetermined) == .ready)
    }

    @Test func deniedAndRestrictedAreBlocked() {
        #expect(CameraGate.outcome(hasCamera: true, status: .denied) == .denied)
        #expect(CameraGate.outcome(hasCamera: true, status: .restricted) == .denied)
    }
}
