//
//  CameraViewModelTests.swift
//  GourmetShareMapTests
//

// CameraViewModelの深い状態遷移テスト(.running/.denied/.unavailableの再現)は、
// CameraServiceが具象型で直接保持されており注入できないため今回は対象外。
// 本番コードにCameraServicingプロトコルを新設してDIできるようにする設計判断が必要なため、
// 開発者の判断を待って別タスクで対応する。

import Testing
@testable import GourmetShareMap

@MainActor
struct CameraViewModelTests {
    @Test func initialStateIsStartingAndNotCapturing() {
        let viewModel = CameraViewModel()

        guard case .starting = viewModel.state else {
            Issue.record("生成直後のstateは.startingであるべき")
            return
        }
        #expect(viewModel.isCapturing == false)
    }
}
