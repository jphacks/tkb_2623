//
//  ContentView.swift
//  GourmetShareMap
//
//  Created by Keishi Kaneko on 2026/10/21.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var authViewModel = AuthViewModel()

    var body: some View {
        Group {
            if authViewModel.session != nil {
                HomeView()
            } else {
                SignInView()
            }
        }
        .environmentObject(authViewModel)
    }
}

private struct HomeView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
