//
//  CameraService.swift
//  GourmetShareMap
//

import AVFoundation

enum CameraServiceError: LocalizedError {
    case unavailable
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .unavailable: "この端末ではカメラを利用できません。"
        case .captureFailed: "写真を撮影できませんでした。もう一度お試しください。"
        }
    }
}

/// AVCaptureSession を使った写真撮影。
/// AVCaptureSession はスレッドセーフではないため、セッションの操作はすべて専用キュー（sessionQueue）上で行う。
nonisolated final class CameraService: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "GourmetShareMap.CameraService")
    private let photoOutput = AVCapturePhotoOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var isConfigured = false
    private var captureContinuation: CheckedContinuation<Data, any Error>?

    /// カメラの利用許可。未確認なら許可ダイアログを出す。
    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }

    /// 使用中のカメラ。プレビューの向きの計算に使う。
    var currentDevice: AVCaptureDevice? {
        sessionQueue.sync { currentInput?.device }
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            sessionQueue.async {
                do {
                    try self.configureIfNeeded()
                    if !self.session.isRunning { self.session.startRunning() }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    /// 背面／前面カメラを切り替える。
    func switchCamera() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                defer { continuation.resume() }
                guard let current = self.currentInput else { return }
                let position: AVCaptureDevice.Position = current.device.position == .back ? .front : .back
                guard
                    let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                    let input = try? AVCaptureDeviceInput(device: device)
                else { return }

                self.session.beginConfiguration()
                defer { self.session.commitConfiguration() }
                self.session.removeInput(current)
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.currentInput = input
                } else {
                    self.session.addInput(current)
                }
            }
        }
    }

    /// 写真を撮影し、画像ファイルのデータ（HEIC / JPEG、EXIF 付き）を返す。
    /// - Parameter rotationAngle: 端末の向きに合わせた回転角度（`RotationCoordinator` の値）。
    func capturePhoto(rotationAngle: CGFloat) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                guard self.session.isRunning, self.captureContinuation == nil else {
                    continuation.resume(throwing: CameraServiceError.captureFailed)
                    return
                }
                self.captureContinuation = continuation
                if let connection = self.photoOutput.connection(with: .video),
                   connection.isVideoRotationAngleSupported(rotationAngle) {
                    connection.videoRotationAngle = rotationAngle
                }
                self.photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input),
            session.canAddOutput(photoOutput)
        else { throw CameraServiceError.unavailable }

        session.addInput(input)
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .balanced
        currentInput = input
        isConfigured = true
    }
}

// 撮影結果は AVFoundation のスレッドから呼ばれるため、メインアクターに隔離しない。
extension CameraService: nonisolated AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        let data = photo.fileDataRepresentation()
        sessionQueue.async {
            guard let continuation = self.captureContinuation else { return }
            self.captureContinuation = nil
            if let data, error == nil {
                continuation.resume(returning: data)
            } else {
                continuation.resume(throwing: error ?? CameraServiceError.captureFailed)
            }
        }
    }
}
