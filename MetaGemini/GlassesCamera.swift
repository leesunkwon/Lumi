//
//  GlassesCamera.swift
//  MetaGemini
//

import Foundation
import MWDATCamera
import MWDATCore
import Observation

enum GlassesCameraError: LocalizedError {
    case cameraPermissionDenied
    case cameraUnavailable
    case streamDidNotStart
    case photoCaptureFailed
    case photoCaptureTimedOut

    var errorDescription: String? {
        switch self {
        case .cameraPermissionDenied:
            return "Meta AI 앱에서 Lumi의 안경 카메라 권한을 허용해주세요."
        case .cameraUnavailable:
            return "안경 카메라를 시작하지 못했습니다. 안경을 착용하고 연결 상태를 확인해주세요."
        case .streamDidNotStart:
            return "안경 카메라 연결이 중단되었습니다. 다시 시도해주세요."
        case .photoCaptureFailed:
            return "안경에서 사진을 받지 못했습니다. 잠시 후 다시 시도해주세요."
        case .photoCaptureTimedOut:
            return "사진을 받는 시간이 초과되었습니다. 안경 연결 상태를 확인해주세요."
        }
    }
}

@Observable
@MainActor
final class GlassesCamera {
    @ObservationIgnored private let wearables: WearablesInterface
    @ObservationIgnored private let deviceSelector: AutoDeviceSelector
    @ObservationIgnored private var deviceSession: DeviceSession?
    @ObservationIgnored private var camera: MWDATCamera.Camera?
    @ObservationIgnored private var photoToken: AnyListenerToken?
    @ObservationIgnored private var streamStateToken: AnyListenerToken?
    @ObservationIgnored private var photoContinuation: CheckedContinuation<Data, Error>?
    @ObservationIgnored private var streamStartContinuation: CheckedContinuation<Void, Error>?
    @ObservationIgnored private var photoTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var streamStartTimeoutTask: Task<Void, Never>?

    init(wearables: WearablesInterface) {
        self.wearables = wearables
        self.deviceSelector = AutoDeviceSelector(wearables: wearables)
    }

    func capturePhoto() async throws -> Data {
        defer { teardown() }

        let session = try wearables.createSession(deviceSelector: deviceSelector)
        deviceSession = session
        try session.start()
        try await waitForSessionToStart(session)

        let permission = try await wearables.checkPermissionStatus(.camera)
        if permission != .granted {
            guard try await wearables.requestPermission(.camera) == .granted else {
                throw GlassesCameraError.cameraPermissionDenied
            }
        }

        let configuration = StreamConfiguration(
            videoCodec: .raw,
            resolution: .low,
            frameRate: 15
        )
        guard let camera = try session.addCamera(config: configuration) else {
            throw GlassesCameraError.cameraUnavailable
        }
        self.camera = camera

        let stream = camera.stream
        photoToken = stream.photoDataPublisher.listen { [weak self] photoData in
            Task { @MainActor [weak self, data = photoData.data] in
                self?.finishPhotoCapture(.success(data))
            }
        }

        try await startStreamAndWait(stream)

        return try await withCheckedThrowingContinuation { continuation in
            photoContinuation = continuation
            photoTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled else { return }
                self?.finishPhotoCapture(.failure(GlassesCameraError.photoCaptureTimedOut))
            }

            guard stream.capturePhoto(format: .jpeg) else {
                finishPhotoCapture(.failure(GlassesCameraError.photoCaptureFailed))
                return
            }
        }
    }

    private func waitForSessionToStart(_ session: DeviceSession) async throws {
        if session.state == .started { return }

        for await state in session.stateStream() {
            switch state {
            case .started:
                return
            case .stopped:
                throw GlassesCameraError.streamDidNotStart
            default:
                continue
            }
        }

        throw GlassesCameraError.streamDidNotStart
    }

    private func startStreamAndWait(_ stream: MWDATCamera.Stream) async throws {
        try await withCheckedThrowingContinuation { continuation in
            streamStartContinuation = continuation
            streamStateToken = stream.statePublisher.listen { [weak self] state in
                Task { @MainActor [weak self] in
                    self?.handleStreamState(state)
                }
            }

            stream.start()
            streamStartTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                self?.finishStreamStart(.failure(GlassesCameraError.streamDidNotStart))
            }
        }
    }

    private func handleStreamState(_ state: StreamState) {
        switch state {
        case .streaming:
            finishStreamStart(.success(()))
        case .stopped:
            finishStreamStart(.failure(GlassesCameraError.streamDidNotStart))
        default:
            break
        }
    }

    private func finishStreamStart(_ result: Result<Void, Error>) {
        streamStartTimeoutTask?.cancel()
        streamStartTimeoutTask = nil
        streamStateToken = nil

        guard let streamStartContinuation else { return }
        self.streamStartContinuation = nil
        streamStartContinuation.resume(with: result)
    }

    private func finishPhotoCapture(_ result: Result<Data, Error>) {
        photoTimeoutTask?.cancel()
        photoTimeoutTask = nil

        guard let photoContinuation else { return }
        self.photoContinuation = nil
        photoContinuation.resume(with: result)
    }

    private func teardown() {
        finishStreamStart(.failure(GlassesCameraError.streamDidNotStart))
        streamStartTimeoutTask?.cancel()
        streamStartTimeoutTask = nil
        photoTimeoutTask?.cancel()
        photoTimeoutTask = nil
        photoToken = nil
        streamStateToken = nil

        if let photoContinuation {
            self.photoContinuation = nil
            photoContinuation.resume(throwing: GlassesCameraError.photoCaptureFailed)
        }

        camera?.stop()
        deviceSession?.stop()
        camera = nil
        deviceSession = nil
    }
}
