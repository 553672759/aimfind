// AimFind — 相机调起前的判定面：设备能力 + 授权状态 → 结果。

import AVFoundation

enum CameraGate {
    enum Outcome: Equatable {
        case ready
        case noCamera
        case denied
    }

    static func outcome(hasCamera: Bool, status: AVAuthorizationStatus) -> Outcome {
        guard hasCamera else { return .noCamera }
        switch status {
        case .authorized, .notDetermined: return .ready
        default: return .denied
        }
    }
}

@MainActor
enum CameraLauncher {
    static func prepare() async -> CameraGate.Outcome {
        let hasCamera = AVCaptureDevice.default(for: .video) != nil
        guard hasCamera else { return .noCamera }

        var status = AVCaptureDevice.authorizationStatus(for: .video)
        DebugLog.note("camera gate: hasCamera=\(hasCamera) status=\(status.rawValue)")
        if status == .notDetermined {
            let granted: Bool = await withCheckedContinuation { (resume: CheckedContinuation<Bool, Never>) in
                AVCaptureDevice.requestAccess(for: .video) { allowed in resume.resume(returning: allowed) }
            }
            status = granted ? .authorized : .denied
        }
        return CameraGate.outcome(hasCamera: true, status: status)
    }
}
