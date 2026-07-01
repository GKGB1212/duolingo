//
//  ITBizEnglishApp.swift
//  ITBizEnglish
//
//  App entry point.
//

import SwiftUI

@main
struct ITBizEnglishApp: App {
    var body: some Scene {
        WindowGroup {
            // Gate: the app needs at least one AI key. Without one, the user
            // sees the key-onboarding screen instead of the app.
            KeyGateView()
        }
    }
}
