//
//  GourmetShareMapApp.swift
//  GourmetShareMap
//
//  Created by Keishi Kaneko on 2026/10/21.
//

import GoogleMaps
import SwiftUI

@main
struct GourmetShareMapApp: App {
    // GMSServicesはメインスレッド専用で、かつGMSMapViewの生成前に呼ぶ必要がある。
    // App.init()はその両方を満たすため、AppDelegateを足さずにここで初期化する。
    init() {
        GMSServices.provideAPIKey(GoogleMapsConfig.apiKey)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
