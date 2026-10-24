//
//  CameraViewModel.swift
//  GourmetShareMap
//

import AVFoundation
import Observation

@Observable
final class CameraViewModel {
    enum State {
        case starting
        case running
        /// シミュレータなどカメラがない端末
        case unavailable
        case denied
    }

    private(set) var state: State = .starting
    private(set) var isCapturing = false

    let service = CameraService()

    @ObservationIgnored private weak var previewLayer: AVCaptureVideoPreviewLayer?
    @ObservationIgnored private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?

    func start() async {
        guard await CameraService.requestAccess() else {
            state = .denied
            return
        }
        do {
            try await service.start()
            state = .running
            updateRotationCoordinator()
        } catch {
            state = .unavailable
        }
    }

    func stop() {
        service.stop()
    }

    /// プレビュー用レイヤーにセッションをつなぐ。
    func attach(_ layer: AVCaptureVideoPreviewLayer) {
        layer.session = service.session
        previewLayer = layer
        updateRotationCoordinator()
    }

    func capture() async throws -> Data {
        isCapturing = true
        defer { isCapturing = false }
        // 縦持ちの背面カメラの場合は 90 度。端末の向きに合わせて RotationCoordinator が計算する。
        let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? 90
        return try await service.capturePhoto(rotationAngle: angle)
    }

    func switchCamera() async {
        await service.switchCamera()
        updateRotationCoordinator()
    }

    /// 端末の向きに合わせて回転角度を計算する RotationCoordinator（iOS 17 以降の推奨 API）を作り直す。
    private func updateRotationCoordinator() {
        guard let previewLayer, let device = service.currentDevice else { return }
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        applyPreviewRotation()
    }

    /// プレビューを端末の向きに合わせて回転させる。端末を回転するとプレビューのレイアウトが変わるので、そのたびに呼ぶ。
    func applyPreviewRotation() {
        guard let coordinator = rotationCoordinator,
              let connection = previewLayer?.connection else { return }
        let angle = coordinator.videoRotationAngleForHorizonLevelPreview
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }
}
